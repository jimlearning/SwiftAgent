# AgentRuntime 架构文档

AgentRuntime 是 SwiftAgent 的中央 AI Agent 执行层，参考 Apple [FoundationModels](https://developer.apple.com/documentation/FoundationModels) 框架设计。它用一套与提供商无关、协议驱动的架构替代了旧的 `LLMClient` + `QueryEngine` 栈，由 `LanguageModelSessionImpl` 编排完整的 Agent 循环。

---

## 1. 总览

```
┌─────────────────────────────────────────────────────────┐
│                  集成层 (Integration Layer)              │
│  ThreadViewModel (App)    │    ChatCommand (CLI)         │
├─────────────────────────────────────────────────────────┤
│                  会话层 (Session Layer)                  │
│  LanguageModelSessionImpl ─── actor, 掌管主循环          │
│  ├─ Transcript (对话历史)                                │
│  ├─ ResponseStream = AsyncThrowingStream<SessionEvent>   │
│  └─ 8 个子系统引用                                       │
├────────────────────┬──────────┬─────────────────────────┤
│   提供者层          │ 工具     │ 子系统                   │
│  AnthropicProvider │ 64 工具  │ SQLiteMemoryStore (actor)│
│  DeepSeekProvider  │ 3 批次   │ AgentPermissionBridge    │
│  OpenAIProvider    │          │ MCPBootstrapper (actor)  │
├────────────────────┴──────────┴─────────────────────────┤
│  核心类型: Transcript, SessionEvent, Usage, Response     │
│  AgentPermission (13 种), AgentRuntimeError (19 种)      │
└─────────────────────────────────────────────────────────┘
```

**设计原则：**

- **与提供商无关** — App/CLI 代码永远不会接触到 API 专用类型。所有通信通过 `SessionEvent` 和 `Transcript` 流转。
- **快照语义** — `textDelta` 和 `thinkingDelta` 携带的是累积后的完整值，而非增量片段。消费端直接替换，而非拼接。
- **Actor 隔离** — `LanguageModelSessionImpl`、`StreamingGenerationChannel`、`SQLiteMemoryStore` 和 `DefaultToolEngine` 均为 actor。Provider 结构体是 `Sendable` 值类型。
- **对齐 FoundationModels (2026-06-27)** — P0/P1/P2 对齐已完成：`LanguageModelExecutorConfiguration`、`LanguageModelExecutorGenerationRequest`、`ContextOptions`、`GenerationOptions`（SamplingMode, ToolCallingMode）、`LanguageModelCapabilities`（Capability 枚举, `contains(_:)`）、`SessionToolDefinition.parameters`、增强的 `AgentRuntimeError` info structs、`Prompt`/`Instructions`/`PromptAttachment` 类型、`TranscriptErrorHandlingPolicy`、`Tool` 协议 `Output` 关联类型。详见 §2。

---

## 2. 核心协议与类型系统

### 2.1 LanguageModel + LanguageModelExecutor

```
LanguageModel (Sendable)              LanguageModelExecutor (Sendable)
├─ capabilities: LanguageModelCapabilities   ├─ model: any LanguageModel
├─ displayName: String                       └─ respond(to:tools:options:
└─ makeExecutor() -> any LanguageModelExecutor        streamingInto:) async throws
```

**`LanguageModel`**（`Providers/LanguageModel.swift:55`）是一个工厂协议。它持有配置信息（API Key、base URL、model ID）但不持有运行时状态。唯一的 `makeExecutor()` 方法为每个模型创建推理后端。

**`LanguageModelExecutor`**（`Providers/LanguageModelExecutor.swift:57`）是执行推理的内部协议，只有一个方法：

```swift
func respond(
    to transcript: Transcript,
    tools: [SessionToolDefinition],
    options: GenerationOptions,
    streamingInto channel: GenerationChannel
) async throws
```

每个 Provider 结构体同时遵循**两个**协议——`makeExecutor()` 返回 `self`。

**`LanguageModelCapabilities`**（`Providers/LanguageModel.swift:7`）描述模型能力：`supportsStreaming`、`supportsToolUse`、`supportsThinking`、`supportsVision`、`contextWindow`、`maxOutputTokens`、`providerDisplayName`。

**`GenerationOptions`**（`Providers/LanguageModelExecutor.swift:31`）携带生参参数：`maxTokens`、`temperature`、`reasoningBudget`、`stream`。

**`SessionToolDefinition`**（`Providers/LanguageModelExecutor.swift:11`）是传递给执行器的规范化工具形态：`name`、`description`、`inputSchema: JSONSchema`、`deferLoading`。

### 2.2 GenerationChannel

`Providers/GenerationChannel.swift:8` — 执行器与运行时之间的流式抽象。六个方法，全部 `async`：

| 方法                                   | 用途             |
| -------------------------------------- | ---------------- |
| `send(textDelta:)`                     | 累积文本快照     |
| `send(thinkingDelta:)`                 | 累积思考快照     |
| `send(toolCallRequest:id:name:input:)` | 模型请求工具执行 |
| `send(toolCallCompleted:id:output:)`   | 工具执行完成     |
| `complete(stopReason:usage:)`          | 本轮正常结束     |
| `fail(with:)`                          | 流式过程中的错误 |

两种具体实现：

- **`StreamingGenerationChannel`**（`StreamingGenerationChannel.swift:15`）— 公开 actor，桥接到 `AsyncThrowingStream` 的 continuation。用于流式的 `streamResponse(to:)` 路径。
- **`CollectingChannel`**（`LanguageModelSessionImpl.swift:8`）— 私有 actor，将事件记录在本地。用于非流式的 `respond(to:)` 路径，事后检查。

### 2.3 LanguageModelSession

`LanguageModelSession.swift:68` — 中央编排器协议。只有 actor 类型可以遵循：

```swift
public protocol LanguageModelSession: Actor {
    var modelProvider: any LanguageModel { get }
    var memoryStore: any SessionMemoryStore { get }
    var permissionEngine: any SessionPermissionEngine { get }
    var toolEngine: any ToolEngine { get }
    var contextManager: any SessionContextManager { get }
    var profileManager: any ProfileManager { get }
    var graphEngine: (any AgentGraph)? { get }
    var hookSystem: any SessionHookSystem { get }
    var isResponding: Bool { get }

    func respond(to prompt: String) async throws -> Response
    func streamResponse(to prompt: String) -> ResponseStream
}
```

八个子系统属性，两个入口方法。`isResponding` 防止并发轮次（抛出 `.rateLimited`）。

### 2.4 SessionEvent

`SessionEvent.swift:18` — 与提供商无关的流式事件枚举。执行器与会话之间的所有通信都通过这 6 种 case：

```swift
public enum SessionEvent: Sendable {
    case textDelta(String)              // 累积文本（非 token 增量）
    case thinkingDelta(String)          // 累积思考（非 token 增量）
    case toolCallRequested(id: String, name: String, input: Data)
    case toolCallCompleted(id: String, output: ToolOutputValue, isError: Bool)
    case turnCompleted(usage: Usage?, stopReason: String?)
    case error(AgentRuntimeError)
}
```

核心设计：`textDelta` 和 `thinkingDelta` 携带的是**替换值**（完整快照），而非增量片段。这避免了消费端拼接部分字符串导致的"双重渲染"bug。

### 2.5 Transcript

`Transcript.swift:5` — 可编解码的对话历史，包含 7 种类型化条目：

```swift
public enum Entry: Sendable, Codable {
    case instruction(String)                          // 系统提示
    case prompt(String)                               // 用户消息
    case response(String)                             // 模型文本响应
    case thinking(String)                             // 模型推理
    case toolCall(id: String, name: String, input: Data)
    case toolOutput(id: String, output: String, isError: Bool)
    case system(String)                               // 系统通知
}
```

Transcript 在多轮对话中累积，并通过 `memoryStore.store(key:"latest", namespace:"sessions", value: transcript)` 持久化到内存存储中。

### 2.6 Usage、Response、ResponseStream

- **`Usage`**（`Usage.swift:5`）— 丰富的 token 计数，与 Claude Code 的 `NonNullUsage` 对齐：`inputTokens`、`outputTokens`、`cacheCreationInputTokens`、`cacheReadInputTokens`、`serverToolUse`、`cacheCreation`、`inferenceGeo`、`iterations`、`speed`、`costUSD`、`contextWindow`、`maxOutputTokens`。
- **`Response`**（`Response.swift:8`）— 非流式 `respond(to:)` 的返回结果：`transcript`、`usage`、`stopReason`。
- **`ResponseStream`**（`Response.swift:29`）— `AsyncThrowingStream<SessionEvent, Error>`。消费端通过 `for try await event in stream` 迭代。

### 2.7 FoundationModels 对齐类型 (P1/P2)

为匹配 Apple FoundationModels API 表面（iOS 26+/27+）而新增的类型：

**`Prompt`**（`Providers/Prompt.swift`）— 带类型的提示词抽象，替代会话 API 中的裸 `String`：

```swift
public protocol PromptRepresentable: Sendable {
    func resolvePrompt() -> Prompt
}
public struct Prompt: Sendable, PromptRepresentable {
    public let content: String
    public init(_ content: String)
    public init(@PromptBuilder _ builder: () -> Prompt)
}
```

`String` 遵循 `PromptRepresentable` 以实现无缝采用。`@PromptBuilder` 是用于组合式提示词构建的结果构建器。`PromptAttachment` 包装多模态内容（`.image`、`.file`、`.url`），`ImageAttachmentContent` 携带图像元数据（格式、细节级别）。

**`Instructions`**（`Providers/Instructions.swift`）— 带类型的系统指令：

```swift
public struct Instructions: Sendable {
    public let content: String
    public init(_ content: String)
    public init(@InstructionsBuilder _ builder: () -> Instructions)
}
```

`@InstructionsBuilder` 支持从字符串和 `Instructions` 值组合组装指令。

**`TranscriptErrorHandlingPolicy`**（`Providers/TranscriptErrorHandlingPolicy.swift`）— 生成过程中的错误处理策略：

```swift
public struct TranscriptErrorHandlingPolicy: Sendable {
    public var toolErrorStrategy: ToolErrorStrategy     // .retry, .skip, .abort, .reportToModel
    public var contextOverflowStrategy: ContextOverflowStrategy  // .truncateOldest, .compress, .abort
    public var maxToolErrorRetries: Int
}
```

这些类型已定义可用，但尚未接入 `LanguageModelSessionImpl`（会话 API 在过渡期间仍接受裸 `String` 以保持向后兼容）。

---

## 3. Agent 循环

### 3.1 LanguageModelSessionImpl

`LanguageModelSessionImpl.swift:55` — 实现 `LanguageModelSession` 的具体 actor。创建时传入 8 个子系统引用：

```swift
public init(
    modelProvider: any LanguageModel,
    memoryStore: any SessionMemoryStore,
    permissionEngine: any SessionPermissionEngine,
    toolEngine: any ToolEngine,
    contextManager: any SessionContextManager = NoOpSessionContextManager(),
    profileManager: any ProfileManager = NoOpProfileManager(),
    graphEngine: (any AgentGraph)? = nil,
    hookSystem: any SessionHookSystem = NoOpSessionHookSystem(),
    systemPrompt: String? = nil
)
```

如果提供了 system prompt，会以 `.instruction(prompt)` 追加到全新的 transcript 中。

### 3.2 防重入守卫

`LanguageModelSessionImpl.swift:101` — `assertNotResponding()` 在开始新轮次前检查 `isResponding`。如果已有正在进行的轮次，抛出 `.rateLimited`。`isResponding` 在轮次开始时设为 `true`，在 `defer` 块中恢复为 `false`。

### 3.3 流式路径

```
用户发送 "run ls"
    │
    ▼
streamResponse(to: "run ls")
    │
    ├─ transcript.entries.append(.prompt("run ls"))
    ├─ 创建 StreamingGenerationChannel + setContinuation
    ├─ executor.respond(to: transcript, tools, options, streamingInto: channel)
    │       │
    │       ├─ SSE 字节流 → SSE 解析器 → channel.send(textDelta:)
    │       ├─                              channel.send(thinkingDelta:)
    │       ├─                              channel.send(toolCallRequest:)
    │       └─                              channel.complete(stopReason:usage:)
    │
    ├─ 读取 channel.accumulatedThinking → transcript.entries.append(.thinking)
    ├─ 读取 channel.accumulatedText → transcript.entries.append(.response)
    │
    ├─ recordedToolCalls?
    │   │ 有
    │   ├─ 对每个调用:
    │   │   ├─ executeTool(name:input:) → 权限检查 → toolEngine.execute
    │   │   ├─ transcript.entries.append(.toolCall)
    │   │   ├─ transcript.entries.append(.toolOutput)
    │   │   └─ continuation.yield(.toolCallCompleted)
    │   └─ 循环：用更新后的 transcript 重新调用执行器
    │
    └─ 无 → memoryStore.store(transcript) → continuation.finish()
```

关键的顺序保证：**thinking → text → toolCall → toolOutput** 在 transcript 中严格维持。这是 thinking-mode API（DeepSeek、Anthropic）所要求的——它们会验证 block 的顺序。

### 3.4 非流式路径

`LanguageModelSessionImpl.swift:160` — `respond(to:)` 遵循相同的模式，但使用 `CollectingChannel`。事件在本地收集，等执行器完成后统一检查。工具调用触发重新提示（最多 50 次迭代）。返回 `Response(transcript, usage, stopReason)`。

### 3.5 工具执行

`LanguageModelSessionImpl.swift:113` — `executeTool(name:input:)`：

1. 通信类工具（`SendUserMessage`、`TaskOutput`）跳过权限检查。
2. 其他所有工具：通过 `permissionForTool(_:)` 将名称映射为 `AgentPermission`，调用 `permissionEngine.check(permission)`，然后 `toolEngine.execute(name:input:)`。
3. 失败时：将 `.toolOutput(id:output:isError:true)` 追加到 transcript——模型可以对错误做出响应。

### 3.6 Channel 对比

|            | CollectingChannel                 | StreamingGenerationChannel         |
| ---------- | --------------------------------- | ---------------------------------- |
| 可见性     | private actor                     | public actor                       |
| 存储方式   | `events: [SessionEvent]` 数组     | `AsyncThrowingStream` continuation |
| 工具追踪   | events 数组包含 toolCallRequested | `recordedToolCalls` 数组           |
| 使用场景   | `respond(to:)` 非流式             | `streamResponse(to:)` 流式         |
| 完成后守卫 | `isFinished` 标志                 | `isFinished` 标志                  |

---

## 4. 提供者系统

### 4.1 共享架构

三个 Provider 遵循同一模式：

```
┌──────────────────────────────────────────┐
│  Provider 结构体 (LanguageModel +        │
│  LanguageModelExecutor + Sendable)       │
│                                          │
│  respond(to:tools:options:streamingInto:)│
│    ├─ Transcript 翻译器 → 线路字典       │
│    ├─ Tool 翻译器 → 线路字典             │
│    ├─ URLRequest 组装                    │
│    ├─ URLSession.bytes(for:) → SSE 行    │
│    └─ SSE 解析器 → GenerationChannel     │
└──────────────────────────────────────────┘
```

### 4.2 AnthropicProvider

`Providers/Anthropic/AnthropicProvider.swift:8` — 目标端点 `/v1/messages`。

- **Transcript 翻译**：`AnthropicTranscriptTranslator` — 将 Transcript 条目映射为 `{role, content: [{type, text/tool_use/tool_result/thinking}]}` 数组，带角色刷新逻辑。
- **Tool 翻译**：`AnthropicToolTranslator` — 将 `SessionToolDefinition` 映射为 `{name, description, input_schema}`。
- **SSE 解析**：`AnthropicSSEParser` — 处理 `content_block_start/delta/stop`、`message_delta`、`message_stop`、`error`。
- **内容累积**：`AnthropicContentAccumulator` — 按索引累积 `input_json_delta`，使用 `safeParseJSON` 处理双重 JSON 字符串化。
- **模型能力**：Sonnet 4.6、Opus 4.7、Haiku 4.5，上下文窗口 200K，最大输出 32K/32K/8K。

### 4.3 DeepSeekProvider

`Providers/DeepSeek/DeepSeekProvider.swift:15` — 通过 `APICompatibility` 枚举支持双 API 兼容模式：

| 模式 | 端点 | Transcript 翻译器 | SSE 解析器 |
|------|------|-------------------|------------|
| `.anthropicCompatible` | `/anthropic/v1/messages` | `translateAnthropicCompat()` | `DeepSeekSSEParser`（→`AnthropicSSEParser`） |
| `.openAICompatible` | `/v1/chat/completions` | `translateChatCompletions()` | `ChatCompletionsSSEParser` |

两个翻译器均委托给规范实现并附加 DeepSeek 后处理：
- `translateAnthropicCompat` → `AnthropicTranscriptTranslator.translate`，然后剥离 `cache_control` 键和空的 `signature`（思考块）。
- `translateChatCompletions` → `OpenAITranscriptTranslator.translateChatCompletions`。
- `DeepSeekToolTranslator` 遵循相同的委托模式，分别委托给 `AnthropicToolTranslator` 和 `OpenAIToolTranslator`。

与 Anthropic 的关键差异：

- 剥离 `anthropic-beta` 头和 `cache_control` 标记（DeepSeek 拒绝它们）。
- 思考块在 Anthropic 模式下保留为 `{"type": "thinking", "thinking": text}`，在 Chat Completions 模式下使用 `reasoning_content`（DeepSeek 要求重提示时包含此字段）。
- `translateResponses` 保留供未来使用（待 DeepSeek 支持 Responses API 后切换）。
- 模型：`deepseek-v4-pro`（128K 上下文，32K 输出）、`deepseek-v4-flash`（128K 上下文，8K 输出）、`deepseek-chat`、`deepseek-reasoner`。

### 4.4 OpenAIProvider

`Providers/OpenAI/OpenAIProvider.swift:8` — 目标端点 `/v1/responses`（OpenAI Responses API，2025+）。

- **Transcript 翻译**：`OpenAITranscriptTranslator.translateResponses` — Responses API 类型化条目（message、reasoning、function_call、tool_call_output）。
- **Tool 翻译**：`OpenAIToolTranslator.translateResponses` — `{"type": "function", "function": {name, description, parameters}}`。
- **SSE 解析**：`ResponsesSSEParser` — 基于事件的 SSE（`response.output_text.delta`、`response.function_call_arguments.delta`、`response.completed`）。
- **o4 推理**：将 `reasoningBudget` 映射为 `reasoning_effort`（"low"/"medium"/"high"），对推理模型省略 temperature。
- **Chat Completions 支持**：`OpenAITranscriptTranslator` 和 `OpenAIToolTranslator` 同时提供 `translateChatCompletions` 方法，供使用旧格式的 Provider 使用（例如 DeepSeek 的 `openAICompatible` 模式）。

---

## 5. 流式基础设施

### 5.1 StreamingGenerationChannel

`StreamingGenerationChannel.swift:15` — 将执行器输出桥接到消费端的公开 actor。核心设计：

- **快照语义**：`send(textDelta:)` 和 `send(thinkingDelta:)` 使用**替换**模式——每次调用覆盖 `accumulatedText`/`accumulatedThinking` 并产出完整值。执行器提供的是累积总量，而非增量片段。
- **完成后守卫**：`complete()` 或 `fail()` 之后，`isFinished = true`——之后所有 send 操作静默丢弃。防止轮次完成后出现悬空事件。
- **工具追踪**：`recordedToolCalls: [(id, name, input)]`——Agent 循环在执行器完成后检查此数组，决定执行工具还是结束。
- **Continuation 生命周期**：`setContinuation()` 存储流的 continuation。`fail(with:)` 调用 `continuation.finish(throwing:)`；正常完成从 Agent 循环调用 `continuation.finish()`。

线程安全：`recordedToolCalls` 和 `accumulatedText`/`accumulatedThinking` 为 `public private(set)`——写入受 actor 保护，读取使用 `await`。

### 5.2 SSE 解析器

每个 Provider 有自己的 SSE 解析器，但共享相同的输出接口（都写入 `GenerationChannel`）：

- **`AnthropicSSEParser`** — 解析 Anthropic SSE 事件：`content_block_start`（注册工具调用）、`content_block_delta`（text/thinking/input_json）、`content_block_stop`（完成工具调用）、`message_delta`（usage/stop_reason）、`error`。
- **`DeepSeekSSEParser`** — 仅支持 Anthropic 模式；完全委托给 `AnthropicSSEParser`。Chat Completions 路径由 `ChatCompletionsSSEParser` 直接处理。
- **`ResponsesSSEParser`** — 解析 OpenAI Responses API 基于事件的 SSE：`response.output_text.delta`、`response.reasoning.delta`、`response.function_call_arguments.delta`、`response.output_item.done`、`response.completed`。
- **`ChatCompletionsSSEParser`** — 解析 Chat Completions SSE：`choices[0].delta.content` → text、`choices[0].delta.reasoning_content` → 思考、`choices[0].delta.tool_calls` → tool call、`choices[0].finish_reason` → complete。由 DeepSeek `openAICompatible` 模式使用。

### 5.3 Transcript 翻译器

将 `Transcript` 转换为特定 Provider 的线路格式的纯函数：

| 翻译器 | 输入 | 输出 | 格式 |
|--------|------|------|------|
| `AnthropicTranscriptTranslator.translate` | Transcript | `(messages, system)` | Anthropic Messages API |
| `DeepSeekTranscriptTranslator.translateAnthropicCompat` | Transcript | `(messages, system)` | Anthropic Messages（委托 + 剥离 cache_control） |
| `DeepSeekTranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions（委托给 `OpenAITranscriptTranslator`） |
| `DeepSeekTranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API（委托给 `OpenAITranscriptTranslator`） |
| `OpenAITranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions messages[] 带角色刷新 |
| `OpenAITranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API 类型化输入条目 |

所有翻译器都包含角色刷新逻辑：连续的相同角色条目合并到一条消息中；角色变化（user↔assistant）或工具边界触发刷新。DeepSeek 翻译器委托给规范的 Anthropic/OpenAI 翻译器，并附加格式特定的后处理。

---

## 6. 工具系统

### 6.1 RuntimeAgentTool 协议

`Tools/RuntimeAgentTool.swift:16` — 带有关联 `Arguments` 类型的 `Tool` 协议：

```swift
public protocol Tool<Arguments>: Sendable {
    associatedtype Arguments: Codable & Sendable
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    func call(arguments: Arguments) async throws -> ToolOutputValue
    func _callFromData(_ input: Data) async throws -> ToolOutputValue
}
```

`_callFromData` 是类型擦除的入口——将 JSON `Data` 解码为 `Arguments` 并委托给 `call(arguments:)`。这使得 `DefaultToolEngine` 能够通过 `any Tool` 存在类型执行任意工具。

协议包含 `RuntimeAgentTool` 类型别名以保持向后兼容。

### 6.2 ToolMetadata

`Tools/ToolMetadata.swift` — 与工具实现分离的操作元数据：

```swift
public struct ToolMetadata: Sendable {
    var searchHint: String?
    var isEnabled: Bool
    var isReadOnly: Bool
    var isConcurrencySafe: Bool
    var isDestructive: Bool
    var interruptBehavior: InterruptBehavior
    var activityDescription: String?
    var requiresApproval: Bool
    var permissionCategory: AgentPermission?
}
```

以 `(any Tool, ToolMetadata)` 对的形式注册到 `DefaultToolEngine`。

### 6.3 批次注册表

工具分为 3 个批次以支持并行加载：

| 批次     | 数量 | 类别                                                         | 文件                        |
| -------- | ---- | ------------------------------------------------------------ | --------------------------- |
| Batch 1  | ~15  | 只读：FileRead、Grep、Glob、WebSearch、WebFetch、ListSkills 等 | `Batch1ToolRegistry.swift`  |
| Batch 23 | ~9   | 文件修改 + 命令：FileWrite、FileEdit、Bash、NotebookEdit、LSP | `Batch23ToolRegistry.swift` |
| Batch 45 | ~36  | 任务/Agent/工作流/MCP/定时任务/通知：AgentTool、TaskCreate、MCPTool、SkillTool 等 | `Batch45ToolRegistry.swift` |

每个注册表暴露 `static func tools(...) -> [(any Tool, ToolMetadata)]`，参数通过依赖注入传入（工作目录、MCP 客户端等）。

### 6.4 DefaultToolEngine

`SubsystemStubs.swift:8` — 遵循 `ToolEngine` 的 actor 工具注册表：

```swift
public actor DefaultToolEngine: ToolEngine {
    func register(tool: any Tool, metadata: ToolMetadata)
    func getDefinition(name: String) -> SessionToolDefinition?
    func getAllDefinitions() -> [SessionToolDefinition]
    func execute(name: String, input: Data) async throws -> ToolOutputValue
}
```

工具存储在 `[String: (any Tool, ToolMetadata)]` 字典中。`execute` 通过 `_callFromData` 解码输入并返回 `ToolOutputValue`。

### 6.5 ToolOutputValue

`Tools/ToolOutputValue.swift:9` — 工具结果的二分支枚举：

```swift
public enum ToolOutputValue: Sendable {
    case string(String)
    case blocks([OutputBlock])
}
```

`OutputBlock` 有 `type`（`text`、`code`、`diff`、`image`、`error`）和 `content: String`。`stringValue` 计算属性提供文本降级方案。

---

## 7. 权限系统

### 7.1 AgentPermission

`Providers/AgentPermission.swift:10` — 涵盖文件系统、网络、设备和执行领域的 13 种权限：

```swift
public enum AgentPermission: Sendable, CaseIterable {
    case readFiles(paths: Set<String>)
    case writeFiles(paths: Set<String>)
    case network(domains: Set<String>)
    case contacts, calendar, location
    case camera, microphone
    case runCommands, delete
    case all, `default`, plan
}
```

`toolName` 计算属性将每种权限映射到规范的工具名称（如 `.runCommands → "Bash"`、`.readFiles → "Read"`），用于与旧版 `PermissionEngine` 集成。

### 7.2 SessionPermissionEngine

`Providers/AgentPermission.swift:103` — 单方法协议：

```swift
public protocol SessionPermissionEngine: Sendable {
    func check(_ permission: AgentPermission) async throws -> Bool
}
```

### 7.3 AgentPermissionBridge

`Providers/Permission/AgentPermissionBridge.swift:12` — 将旧版 `PermissionEngine` 适配到 `SessionPermissionEngine`。将每个 `AgentPermission` case 映射为基于工具名称的权限检查，通过封装引擎将关联的路径/域名编码到输入字典中。

---

## 8. 内存/存储

### 8.1 SessionMemoryStore 协议

`Providers/SessionMemoryStore.swift:40` — 泛型 key-namespace 存储：

```swift
public protocol SessionMemoryStore: Sendable {
    func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws
    func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T?
    func search<T: Codable & Sendable>(query: String, namespace: String) async throws -> [T]
    func summarize(namespace: String) async throws -> String
    func forget(key: String, namespace: String) async throws
    func listNamespaces() async throws -> [String]
}
```

### 8.2 SQLiteMemoryStore

`Providers/Memory/SQLiteMemoryStore.swift:13` — 基于 actor 的实现，使用 SQLite3 C API（无第三方依赖）。

- **WAL 日志模式**提升并发读取性能。
- **4 次 schema 迁移**：`schema_version` 表、`memory_entries` 表（key、namespace、value JSON BLOB、updated_at）、namespace 和 updated_at 索引。
- **全部使用参数化查询**——不使用字符串拼接。
- **通过 actor 串行化访问**——所有 CRUD 调用都是 `async`。
- 值以 JSON BLOB 存储——`Codable` 类型通过 `JSONEncoder`/`JSONDecoder` 编解码。

---

## 9. 错误分类

`AgentRuntimeError.swift:5` — 涵盖 5 个领域的 19 种错误，全部遵循 `LocalizedError`。镜像 Apple 的 `LanguageModelError` 模式，使用专用 info struct 提供丰富的错误上下文。

### 9.1 错误信息结构体（对齐 Apple）

模仿 Apple `LanguageModelError` 嵌套 info 类型的六个专用结构体：

| 结构体                  | 属性                                     | Apple 来源                                 |
| ----------------------- | ---------------------------------------- | ------------------------------------------ |
| `ContextSizeExceeded`   | `maxTokens: Int`, `requestedTokens: Int` | `LanguageModelError.ContextSizeExceeded`   |
| `RateLimited`           | `retryAfter: TimeInterval?`              | `LanguageModelError.RateLimited`           |
| `Refusal`               | `reason: String`                         | `LanguageModelError.Refusal`               |
| `Timeout`               | `duration: TimeInterval?`                | `LanguageModelError.Timeout`               |
| `GuardrailViolation`    | `guardrail: String`, `reason: String`    | `LanguageModelError.GuardrailViolation`    |
| `UnsupportedCapability` | `capability: String`                     | `LanguageModelError.UnsupportedCapability` |

### 9.2 按领域分类的错误类型

| 领域                  | 错误类型                                                     |
| --------------------- | ------------------------------------------------------------ |
| **模型 (Model)**      | `rateLimited(RateLimited)`、`unauthorized(reason:)`、`serverError(statusCode:body:)`、`timeout(Timeout)`、`contextSizeExceeded(ContextSizeExceeded)`、`invalidResponse(reason:)`、`refusal(Refusal)`、`guardrailViolation(GuardrailViolation)`、`unsupportedCapability(UnsupportedCapability)` |
| **内存 (Memory)**     | `storageFull(availableBytes:)`、`keyNotFound(key:namespace:)`、`migrationFailed(fromVersion:toVersion:reason:)` |
| **权限 (Permission)** | `permissionDenied(permission:reason:)`、`sandboxViolation(resource:)` |
| **工具 (Tool)**       | `toolNotFound(name:)`、`toolExecutionFailed(name:reason:)`、`toolValidationFailed(name:field:reason:)` |
| **图 (Graph)**        | `cycleDetected(nodes:)`、`nodeFailed(nodeID:reason:)`        |

每种错误都提供了可供 UI 展示的 `errorDescription`。模型类错误（rateLimited、timeout、contextSizeExceeded、refusal、guardrailViolation、unsupportedCapability）携带结构化信息供编程处理——重试等待时间、token 计数、拒绝原因等。

---

## 10. 集成层

### 10.1 App：ThreadViewModel

`ViewModels/ThreadViewModel.swift:40` — 对话线程的 `@MainActor` ViewModel。

**会话创建**：`AppViewModel.makeSession()` 创建 `LanguageModelSessionImpl`，包含：

- `DeepSeekProvider`（Anthropic 兼容模式，`deepseek-v4-pro`）
- `SQLiteMemoryStore` 位于 `~/.swift-agent/projects/<path>/`
- `AgentPermissionBridge` 封装旧版 `PermissionEngine`
- `DefaultToolEngine` 加载 Batch1 + Batch23 工具

**流处理**（`send()` L257 → `startAgentRun()` L293）：

1. 追加用户消息，创建助手占位符，设置 `state = .executing`
2. 调用 `session.streamResponse(to: trimmed)` → 返回 `AsyncThrowingStream`
3. `for try await event in stream` 分发到 `handleSessionEvent()`：
   - `.textDelta` / `.thinkingDelta` → 追加到助手消息块
   - `.toolCallRequested` / `.toolCallCompleted` → 添加 `ToolUseBlock` / `ToolResultBlock`
   - `.turnCompleted(usage:)` → 记录 token 用量
   - `.error` → 设置 `state = .failed`，取消流式
4. 流耗尽 → `handleStreamComplete()` → 完成消息，持久化到 JSONL，处理排队消息

**持久化**：消息分为思考块和非思考块，各自作为独立的 JSONL 条目写入，通过 `parentUuid` 链式连接（Claude Code 格式）。文件 I/O 在 `Task.detached` 中运行。

### 10.2 App：AppViewModel

`ViewModels/AppViewModel.swift` — 管理 API Key 解析、Provider 配置和会话工厂（`makeSession()`）。当前模型选择通过 `currentModel` 发布（默认：`deepseek-v4-pro`）。权限模式（`default`/`acceptEdits`/`bypassPermissions`/`plan`）驱动 `AgentPermissionBridge` 配置。

### 10.3 CLI：ChatCommand

`ChatCommand.swift` — 以内联方式创建 `LanguageModelSessionImpl`，使用相同的 4 个依赖。迭代 `streamResponse(to:)`，通过 `SessionEventRenderer` 将 `SessionEvent` 值渲染为 ANSI 终端输出。

---

## 11. 子系统桩与未来预留槽位

### 11.1 空操作实现

`SubsystemStubs.swift:53` 为尚未实现的协议提供了三个桩：

- **`NoOpSessionContextManager`** — 遵循 `SessionContextManager`（空协议）。未来：上下文窗口追踪与自动压缩。
- **`NoOpProfileManager`** — 遵循 `ProfileManager`（空协议）。未来：Agent 身份、人格和行为配置。
- **`NoOpSessionHookSystem`** — 遵循 `SessionHookSystem`（空协议）。未来：生命周期钩子（pre-prompt、post-response、pre-tool）。

### 11.2 AgentGraph

`Graph/AgentGraph.swift:10` — 仅为协议级别的类型槽位，用于多 Agent 编排：

```swift
public protocol AgentGraph: Sendable {
    var nodes: [any AgentNode] { get }
    func validate() throws
}
```

预留给未来的 WWDC27 AgentKit `WorkflowGraph` 集成。`LanguageModelSessionImpl.graphEngine` 为 optional——当没有多 Agent 图处于活跃状态时为 `nil`。

### 11.3 PartiallyGenerated

`PartiallyGenerated.swift` — 用于结构化输出流式的泛型快照累加器。持有 `snapshot`、`previousSnapshot`、`changedKeys`、`isComplete`。尚未接入 Agent 循环——设计用于未来的结构化 JSON 输出模式。

---

## 文件索引

| 文件                                  | 用途                                                         |
| ------------------------------------- | ------------------------------------------------------------ |
| `LanguageModelSession.swift`          | 编排器协议 + ToolEngine + 3 个桩子系统协议                   |
| `LanguageModelSessionImpl.swift`      | Actor 实现 — Agent 循环、工具执行、流式/非流式两条路径       |
| `StreamingGenerationChannel.swift`    | 公开 actor — 带快照语义的 continuation 桥接                  |
| `GenerationChannel.swift`             | 6 方法流式抽象协议                                           |
| `SessionEvent.swift`                  | 与提供商无关的流式事件枚举                                   |
| `Transcript.swift`                    | 可编解码对话历史（7 种条目类型）                             |
| `LanguageModel.swift`                 | LanguageModel 协议 + LanguageModelCapabilities               |
| `LanguageModelExecutor.swift`         | 执行器协议 + GenerationOptions + SessionToolDefinition       |
| `AgentPermission.swift`               | 运行时权限枚举（13 种）+ SessionPermissionEngine 协议        |
| `AgentRuntimeError.swift`             | 统一错误类型（19 种，5 个领域，6 个对齐 Apple 的 info structs） |
| `RuntimeAgentTool.swift`              | Tool 协议，带双关联类型（Arguments, Output）                 |
| `Prompt.swift`                        | Prompt/PromptRepresentable/PromptBuilder + 多模态附件类型    |
| `Instructions.swift`                  | Instructions 结构体 + InstructionsBuilder 结果构建器         |
| `TranscriptErrorHandlingPolicy.swift` | 生成过程中的错误处理策略（工具错误、上下文溢出）             |
| `Usage.swift`                         | Token 用量（与 CC NonNullableUsage 对齐）                    |
| `Response.swift`                      | Response 结构体 + ResponseStream 类型别名                    |
| `SubsystemStubs.swift`                | NoOp 桩 + DefaultToolEngine actor                            |
| `AgentPermissionBridge.swift`         | 旧版 PermissionEngine 的 SessionPermissionEngine 适配器      |
| `SQLiteMemoryStore.swift`             | 基于 SQLite3 actor 的存储，含 schema 迁移                    |
| **Provider 文件**                     |                                                              |
| `AnthropicProvider.swift`             | Anthropic Messages API 提供者                                |
| `DeepSeekProvider.swift`              | DeepSeek 双 API 提供者                                       |
| `OpenAIProvider.swift`                | OpenAI Chat Completions 提供者                               |
| `AnthropicSSEParser.swift`            | Anthropic SSE 流解析器                                       |
| `DeepSeekSSEParser.swift`             | DeepSeek 双模式 SSE 解析器                                   |
| `OpenAISSEParser.swift`               | OpenAI Chat Completions SSE 解析器                           |
| `AnthropicTranscriptTranslator.swift` | Transcript → Anthropic 线路格式                              |
| `DeepSeekTranscriptTranslator.swift`  | Transcript → DeepSeek 线路格式（两种模式）                   |
| `OpenAITranscriptTranslator.swift`    | Transcript → OpenAI 线路格式                                 |
| `AnthropicContentAccumulator.swift`   | 按索引的工具输入 JSON 累加器                                 |
| **工具批次文件**                      |                                                              |
| `Batch1ToolRegistry.swift`            | 15 个只读工具                                                |
| `Batch23ToolRegistry.swift`           | 9 个文件/命令工具                                            |
| `Batch45ToolRegistry.swift`           | 36 个任务/Agent/MCP 工具                                     |
| **集成文件**                          |                                                              |
| `ThreadViewModel.swift`               | App：会话创建、流处理、持久化                                |
| `AppViewModel.swift`                  | App：API Key、Provider 配置、会话工厂                        |
| `ChatCommand.swift`                   | CLI：会话创建、ANSI 渲染                                     |
