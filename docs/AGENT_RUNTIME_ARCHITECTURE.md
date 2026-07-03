# AgentRuntime 架构

AgentRuntime 是中心化的 AI agent 执行层，参照 Apple 的 [FoundationModels](https://developer.apple.com/documentation/FoundationModels) 框架设计。它用一套与 provider 无关、由协议驱动的架构取代了传统的 `LLMClient` + `QueryEngine` 技术栈，其中 `LanguageModelSessionImpl` 编排着完整的 agent 循环。

---

## 1. 概览

```
┌─────────────────────────────────────────────────────────┐
│                  集成层                                  │
│  ThreadViewModel (App)    │    ChatCommand (CLI)         │
├─────────────────────────────────────────────────────────┤
│                  Session 层                              │
│  LanguageModelSessionImpl ─── actor，掌管核心循环        │
│  ├─ Transcript（对话历史）                               │
│  ├─ ResponseStream = AsyncThrowingStream<SessionEvent>   │
│  └─ 8 个子系统引用                                       │
├────────────────────┬──────────┬─────────────────────────┤
│    Provider 层     │ 工具     │ 子系统                   │
│  AnthropicProvider │ 64 工具  │ SQLiteMemoryStore (actor)│
│  DeepSeekProvider  │ 3 批次   │ AgentPermissionBridge    │
│  OpenAIProvider    │          │ MCPBootstrapper (actor)  │
├────────────────────┴──────────┴─────────────────────────┤
│  核心类型: Transcript, SessionEvent, Usage, Response     │
│  AgentPermission (13 种), AgentRuntimeError (19 种)      │
└─────────────────────────────────────────────────────────┘
```

**设计原则：**

- **Provider 无关** — App/CLI 代码永远不接触 API 特定类型。所有通信通过 `SessionEvent` 和 `Transcript` 流转。
- **快照语义** — `textDelta` 和 `thinkingDelta` 携带累积总量，而非增量 delta。消费者执行替换，而非追加。
- **Actor 隔离** — `LanguageModelSessionImpl`、`StreamingGenerationChannel`、`SQLiteMemoryStore` 和 `DefaultToolEngine` 均为 actor。Provider 结构体为 `Sendable` 值类型。
- **FoundationModels 对齐 (2026-06-27)** — P0/P1/P2 对齐已完成：`LanguageModelExecutorConfiguration`、`LanguageModelExecutorGenerationRequest`、`ContextOptions`、`GenerationOptions`（SamplingMode、ToolCallingMode）、`LanguageModelCapabilities`（Capability 枚举、`contains(_:)`）、`SessionToolDefinition.parameters`、更丰富的 `AgentRuntimeError` info 结构体、`Prompt`/`Instructions`/`PromptAttachment` 类型、`TranscriptErrorHandlingPolicy`、`Tool` 协议的 `Output` 关联类型。详见 §2。

---

## 2. 核心协议与类型系统

### 2.1 LanguageModel + LanguageModelExecutor

```
LanguageModel (Sendable)              LanguageModelExecutor (Sendable)
├─ capabilities: LanguageModelCapabilities   ├─ model: any LanguageModel
├─ displayName: String                       ├─ prewarm(transcript:) → no-op 默认
├─ executorConfiguration: LanguageModel      └─ respond(to: LanguageModelExecutor
│    ExecutorConfiguration                       GenerationRequest,
└─ makeExecutor() -> any LanguageModelExecutor   streamingInto:) async throws
```

**`LanguageModel`**（`Providers/LanguageModel.swift`）是一个工厂协议。它持有配置信息（API key、base URL、model ID），但不包含运行时状态。`makeExecutor()` 创建每个 model 的推断后端。`executorConfiguration` 暴露配置信息（与 Apple 的 `LanguageModel.Executor.Configuration` 对齐）。由于存在类型限制（session 存储 `any LanguageModel`），使用 `makeExecutor()` 工厂方法而非 `associatedtype Executor`。

**`LanguageModelExecutor`**（`Providers/LanguageModelExecutor.swift`）是执行推断的内部协议。接收一个打包好的 `LanguageModelExecutorGenerationRequest`（与 Apple 对齐），而非扁平参数：

```swift
public struct LanguageModelExecutorGenerationRequest: Sendable {
    var id: UUID
    var transcript: Transcript
    var enabledTools: [SessionToolDefinition]
    var schema: JSONSchema?
    var generationOptions: GenerationOptions
    var contextOptions: ContextOptions
    var metadata: [String: String]
}
```

`prewarm(transcript:)` 允许预加载模型资源（默认为 no-op，与 Apple 对齐）。每个 provider 结构体同时遵循**两个**协议 — `makeExecutor()` 返回 `self`。

**`LanguageModelCapabilities`**（`Providers/LanguageModel.swift`）使用展平布尔值 + `Capability` 枚举配合 `contains(_:)` 方法实现与 Apple 对齐的能力检查：`supportsToolUse`、`supportsGuidedGeneration`、`supportsReasoning`、`supportsStreaming`、`supportsVision`、`contextWindow`、`maximumResponseTokens`、`providerDisplayName`。

**`GenerationOptions`**（`Providers/LanguageModelExecutor.swift`）与 Apple 对齐，包含 `SamplingMode`（`.greedy`、`.temperature`）、`ToolCallingMode`（`.auto`、`.required`、`.none`）、`temperature`、`maximumResponseTokens`、`reasoningBudget`、`stream`。

**`ContextOptions`**（`Providers/LanguageModelExecutor.swift`）独立的提示行为结构体：`includeSchemaInPrompt`、`reasoningLevel`（`ReasoningLevel.low/.medium/.high`）。与 Apple 对齐。

**`SessionToolDefinition`**（`Providers/LanguageModelExecutor.swift`）是归一化的工具形态：`name`、`description`、`parameters: JSONSchema`（与 Apple 的 `Transcript.ToolDefinition.parameters` 对齐）、`deferLoading`。

### 2.2 GenerationChannel

`Providers/GenerationChannel.swift:8` — executor 与 runtime 之间的流式抽象。六个方法，全部 `async`：

| 方法 | 用途 |
|--------|---------|
| `send(textDelta:)` | 累积文本快照 |
| `send(thinkingDelta:)` | 累积思考快照 |
| `send(toolCallRequest:id:name:input:)` | 模型请求工具执行 |
| `send(toolCallCompleted:id:output:)` | 工具执行完成 |
| `complete(stopReason:usage:)` | 本轮正常结束 |
| `fail(with:)` | 流式传输中出错 |

两种具体实现：
- **`StreamingGenerationChannel`**（`StreamingGenerationChannel.swift:15`）— 公开 actor，桥接到 `AsyncThrowingStream` continuation。供流式 `streamResponse(to:)` 路径使用。
- **`CollectingChannel`**（`LanguageModelSessionImpl.swift:8`）— 私有 actor，本地记录事件。供非流式 `respond(to:)` 路径用于事后检查。

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

八个子系统属性，两个入口点。`isResponding` 防止并发轮次（抛出 `.rateLimited`）。

### 2.4 SessionEvent

`SessionEvent.swift:18` — provider 无关的流式事件枚举。executor 与 session 之间的所有通信通过这 6 种 case 流转：

```swift
public enum SessionEvent: Sendable {
    case textDelta(String)              // 累积文本（非 token delta）
    case thinkingDelta(String)          // 累积思考（非 token delta）
    case toolCallRequested(id: String, name: String, input: Data)
    case toolCallCompleted(id: String, output: ToolOutputValue, isError: Bool)
    case turnCompleted(usage: Usage?, stopReason: String?)
    case error(AgentRuntimeError)
}
```

关键设计：`textDelta` 和 `thinkingDelta` 携带**替换**值（完整快照），而非增量 delta。这避免了消费者拼接部分字符串导致的重复渲染 bug。

### 2.5 Transcript

`Transcript.swift:5` — 可编码的对话历史，包含 7 种条目类型：

```swift
public enum Entry: Sendable, Codable {
    case instruction(String)                          // 系统提示
    case prompt(String)                               // 用户消息
    case response(String)                             // 模型文本回复
    case thinking(String)                             // 模型推理
    case toolCall(id: String, name: String, input: Data)
    case toolOutput(id: String, output: String, isError: Bool)
    case system(String)                               // 系统通知
}
```

transcript 在每轮对话中累积，并通过 `memoryStore.store(key:"latest", namespace:"sessions", value: transcript)` 持久化到记忆中。

### 2.6 Usage、Response、ResponseStream

- **`Usage`**（`Usage.swift:5`）— 与 Claude Code 的 `NonNullUsage` 对齐的丰富 token 计数：`inputTokens`、`outputTokens`、`cacheCreationInputTokens`、`cacheReadInputTokens`、`serverToolUse`、`cacheCreation`、`inferenceGeo`、`iterations`、`speed`、`costUSD`、`contextWindow`、`maxOutputTokens`。
- **`Response`**（`Response.swift:8`）— 非流式 `respond(to:)` 的结果：`transcript`、`usage`、`stopReason`。
- **`ResponseStream`**（`Response.swift:29`）— `AsyncThrowingStream<SessionEvent, Error>`。消费者通过 `for try await event in stream` 进行迭代。

### 2.7 FoundationModels 对齐类型（P1/P2）

新增类型以匹配 Apple FoundationModels API 表面（iOS 26+/27+）：

**`Prompt`**（`Providers/Prompt.swift`）— 类型化提示抽象，取代 session API 中的原始 `String`：

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

`String` 遵循 `PromptRepresentable` 以实现无缝过渡。`@PromptBuilder` 是一个 result builder，用于可组合的提示构造。`PromptAttachment` 包装多模态内容（`.image`、`.file`、`.url`），`ImageAttachmentContent` 携带图像元数据（format、detail level）。

**`Instructions`**（`Providers/Instructions.swift`）— 类型化系统指令：

```swift
public struct Instructions: Sendable {
    public let content: String
    public init(_ content: String)
    public init(@InstructionsBuilder _ builder: () -> Instructions)
}
```

`@InstructionsBuilder` 使指令可以从字符串和 `Instructions` 值中组合构建。

**`TranscriptErrorHandlingPolicy`**（`Providers/TranscriptErrorHandlingPolicy.swift`）— 生成过程的错误处理策略：

```swift
public struct TranscriptErrorHandlingPolicy: Sendable {
    public var toolErrorStrategy: ToolErrorStrategy     // .retry, .skip, .abort, .reportToModel
    public var contextOverflowStrategy: ContextOverflowStrategy  // .truncateOldest, .compress, .abort
    public var maxToolErrorRetries: Int
}
```

这些类型已定义可用，但尚未接入 `LanguageModelSessionImpl`（session API 在过渡期间仍接受原始 `String` 以保持向后兼容）。

---

## 3. Agent 循环

### 3.1 LanguageModelSessionImpl

`LanguageModelSessionImpl.swift:55` — 实现 `LanguageModelSession` 的具体 actor。通过 8 个子系统引用创建：

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

如果提供了系统提示，会以 `.instruction(prompt)` 的形式追加到一个新的 transcript 中。

### 3.2 重入防护

`LanguageModelSessionImpl.swift:101` — `assertNotResponding()` 在开始新一轮之前检查 `isResponding`。如果当前有正在进行的轮次，抛出 `.rateLimited`。`isResponding` 在轮次开始时设为 `true`，并在 `defer` 块中设为 `false`。

### 3.3 流式路径

```
用户输入 "run ls"
    │
    ▼
streamResponse(to: "run ls")
    │
    ├─ transcript.entries.append(.prompt("run ls"))
    ├─ 创建 StreamingGenerationChannel + setContinuation
    ├─ executor.respond(to: transcript, tools, options, streamingInto: channel)
    │       │
    │       ├─ SSE 字节 → SSE 解析器 → channel.send(textDelta:)
    │       ├─                              channel.send(thinkingDelta:)
    │       ├─                              channel.send(toolCallRequest:)
    │       └─                              channel.complete(stopReason:usage:)
    │
    ├─ Guard 1: channel.receivedCompletion? → NO → fail stream（响应被截断）
    ├─ Guard 2: 无思考、无文本、无工具？ → YES → fail stream（空响应）
    │
    ├─ 读取 channel.accumulatedThinking → transcript.entries.append(.thinking)
    ├─ 读取 channel.accumulatedText → transcript.entries.append(.response)
    │
    ├─ recordedToolCalls?
    │   │ YES
    │   ├─ 对每个调用：
    │   │   ├─ executeTool(name:input:) → 权限检查 → toolEngine.execute
    │   │   ├─ transcript.entries.append(.toolCall)
    │   │   ├─ transcript.entries.append(.toolOutput)
    │   │   └─ continuation.yield(.toolCallCompleted)
    │   └─ 循环返回：用更新后的 transcript 重新提示 executor
    │
    └─ NO → memoryStore.store(transcript) → continuation.finish()
```

关键顺序保证：**thinking → text → toolCall → toolOutput** 在 transcript 中严格维护。这是 thinking-mode API（DeepSeek、Anthropic）的要求，它们会验证 block 顺序。

响应验证（处理内容前的两个守护条件）：
- **Guard 1 — 完成检查**：如果 `channel.receivedCompletion` 为 `false`，说明 SSE 流从未传递 `message_delta` 事件。响应被截断或格式错误 — 以 `.invalidResponse` 使流失败。
- **Guard 2 — 内容检查**：如果模型返回 `end_turn` 但没有产生文本、思考和工具调用，说明 API 返回了空响应。这种情形被视为 `.invalidResponse`，而非对用户无任何展示的静默"成功"。

### 3.4 非流式路径

`LanguageModelSessionImpl.swift:160` — `respond(to:)` 遵循相同的模式，但换用 `CollectingChannel`。事件在本地收集，在 executor 完成后进行检查。工具调用触发重新提示（最多 50 次迭代）。返回 `Response(transcript, usage, stopReason)`。

### 3.5 工具执行

`LanguageModelSessionImpl.swift:113` — `executeTool(name:input:)`：
1. 通信类工具（`SendUserMessage`、`TaskOutput`）绕过权限检查。
2. 其他所有工具：通过 `permissionForTool(_:)` 将工具名称映射到 `AgentPermission`，调用 `permissionEngine.check(permission)`，然后 `toolEngine.execute(name:input:)`。
3. 失败时：将 `.toolOutput(id:output:isError:true)` 追加到 transcript — 模型可以对错误做出响应。

### 3.6 Channel 对比

| | CollectingChannel | StreamingGenerationChannel |
|---|---|---|
| 可见性 | 私有 actor | 公开 actor |
| 存储 | `events: [SessionEvent]` 数组 | `AsyncThrowingStream` continuation |
| 工具跟踪 | events 数组包含 toolCallRequested | `recordedToolCalls` 数组 |
| 使用方式 | `respond(to:)` 非流式 | `streamResponse(to:)` 流式 |
| 完成后守卫 | `isFinished` 标记 | `isFinished` 标记 |

---

## 4. Provider 系统

### 4.1 共享架构

三个 provider 都遵循相同的模式：

```
┌──────────────────────────────────────────┐
│  Provider 结构体（LanguageModel +        │
│  LanguageModelExecutor + Sendable）      │
│                                          │
│  respond(to:tools:options:streamingInto:)│
│    ├─ Transcript 翻译器 → 协议字典       │
│    ├─ Tool 翻译器 → 协议字典             │
│    ├─ URLRequest 组装                    │
│    ├─ URLSession.bytes(for:) → SSE 行    │
│    └─ SSE 解析器 → GenerationChannel     │
└──────────────────────────────────────────┘
```

### 4.2 AnthropicProvider

`Providers/Anthropic/AnthropicProvider.swift:8` — 目标端点为 `/v1/messages`。

- **Transcript 翻译**：`AnthropicTranscriptTranslator` — 将 Transcript 条目映射为 `{role, content: [{type, text/tool_use/tool_result/thinking}]}` 数组，并进行 role-flushing。
- **工具翻译**：`AnthropicToolTranslator` — 将 `SessionToolDefinition` 映射为 `{name, description, input_schema}`。
- **SSE 解析**：`AnthropicSSEParser` — 处理 `content_block_start/delta/stop`、`message_delta`、`message_stop`、`error`。
- **内容累积**：`AnthropicContentAccumulator` — 按索引进行 `input_json_delta` 拼接，配合 `safeParseJSON`（处理双重 stringified JSON）。
- **模型能力**：Sonnet 4.6、Opus 4.7、Haiku 4.5，上下文窗口 200K，最大输出 32K/32K/8K。

### 4.3 DeepSeekProvider

`Providers/DeepSeek/DeepSeekProvider.swift:15` — 通过 `APICompatibility` 枚举实现双 API 兼容：

| 模式 | 端點 | Transcript 翻译器 | SSE 解析器 |
|------|----------|----------------------|------------|
| `.anthropicCompatible` | `/anthropic/v1/messages` | `translateAnthropicCompat()` | `DeepSeekSSEParser`（→`AnthropicSSEParser`） |
| `.openAICompatible` | `/v1/chat/completions` | `translateChatCompletions()` | `ChatCompletionsSSEParser` |

两个翻译器都委托给规范化实现，并做 DeepSeek 特定的后处理：
- `translateAnthropicCompat` → `AnthropicTranscriptTranslator.translate`，然后从 thinking blocks 中移除 `cache_control` key 和空的 `signature`。
- `translateChatCompletions` → `OpenAITranscriptTranslator.translateChatCompletions`。
- `DeepSeekToolTranslator` 遵循相同的委托模式，分别委托给 `AnthropicToolTranslator` 和 `OpenAIToolTranslator`。

与 Anthropic 的关键差异：
- 移除 `anthropic-beta` header 和 `cache_control` 标记（DeepSeek 拒绝这些）。
- Thinking blocks 在 Anthropic 模式下保留为 `{"type": "thinking", "thinking": text}`，在 Chat Completions 模式下为 `reasoning_content`（DeepSeek 对重新提示验证的要求）。
- `translateResponses` 保留以供将来 DeepSeek 添加 Responses API 支持时使用。
- 模型：`deepseek-v4-pro`（128K 上下文，32K 输出）、`deepseek-v4-flash`（128K 上下文，8K 输出）、`deepseek-chat`、`deepseek-reasoner`。

### 4.4 OpenAIProvider

`Providers/OpenAI/OpenAIProvider.swift:8` — 目标端点为 `/v1/responses`（OpenAI Responses API，2025+）。

- **Transcript 翻译**：`OpenAITranscriptTranslator.translateResponses` — Responses API 类型化条目（message、reasoning、function_call、tool_call_output）。
- **工具翻译**：`OpenAIToolTranslator.translateResponses` — `{"type": "function", "function": {name, description, parameters}}`。
- **SSE 解析**：`ResponsesSSEParser` — 基于事件的 SSE（`response.output_text.delta`、`response.function_call_arguments.delta`、`response.completed`）。
- **o4 推理**：将 `reasoningBudget` 映射为 `reasoning_effort`（"low"/"medium"/"high"），推理模型省略 temperature。
- **Chat Completions 支持**：`OpenAITranscriptTranslator` 和 `OpenAIToolTranslator` 也暴露 `translateChatCompletions`，供使用旧格式的 provider 使用（如 DeepSeek `openAICompatible`）。

---

## 5. 流式基础设施

### 5.1 StreamingGenerationChannel

`StreamingGenerationChannel.swift:15` — 将 executor 输出桥接到消费者的公开 actor。关键设计：

- **快照语义**：`send(textDelta:)` 和 `send(thinkingDelta:)` 使用替换模式 — 每次调用覆盖 `accumulatedText`/`accumulatedThinking` 并 yielding 完整值。executor 提供累积总量，而非增量 delta。
- **完成后守护**：在 `complete()` 或 `fail()` 之后，`isFinished = true` — 所有后续发送静默丢弃。防止轮次完成后的悬空事件。
- **完成检测**：`receivedCompletion: Bool` 仅由 `complete()` 设为 `true`。如果流被截断、通过 `fail()` 报错或未产生事件，则保持 `false`。Agent 循环检查这个标志以区分有效完成和格式错误的响应。
- **工具跟踪**：`recordedToolCalls: [(id, name, input)]` — agent 循环在 executor 完成后检查此数据以决定是执行工具还是结束。
- **Continuation 生命周期**：`setContinuation()` 存储流 continuation。`fail(with:)` 调用 `continuation.finish(throwing:)`；正常完成由 agent 循环调用 `continuation.finish()`。

线程安全：`recordedToolCalls` 和 `accumulatedText`/`accumulatedThinking` 为 `public private(set)` — 在 actor 内部受写保护，读取可通过 `await` 访问。

### 5.2 SSE 解析器

每个 provider 有自己的 SSE 解析器，但所有解析器共享相同的输出接口（它们写入 `GenerationChannel`）：

- **`AnthropicSSEParser`** — 解析 Anthropic SSE 事件：`content_block_start`（注册工具调用）、`content_block_delta`（text/thinking/input_json）、`content_block_stop`（完成工具调用）、`message_delta`（usage/stop_reason → `channel.complete()`）、`error` → `channel.fail()`。循环结束后，如果没有收到 `message_delta`，流已被截断，解析器调用 `channel.fail()` — 防止 agent 循环将空响应视为有效完成。
- **`DeepSeekSSEParser`** — 仅用于 Anthropic-compat 模式；完全委托给 `AnthropicSSEParser`。Chat Completions 路径直接使用 `ChatCompletionsSSEParser`。
- **`ResponsesSSEParser`** — 解析 OpenAI Responses API 基于事件的 SSE：`response.output_text.delta`、`response.reasoning.delta`、`response.function_call_arguments.delta`、`response.output_item.done`、`response.completed`。
- **`ChatCompletionsSSEParser`** — 解析 Chat Completions SSE：`choices[0].delta.content` → text、`choices[0].delta.reasoning_content` → thinking、`choices[0].delta.tool_calls` → tool call、`choices[0].finish_reason` → complete。供 DeepSeek `openAICompatible` 模式使用。

### 5.3 Transcript 翻译器

将 `Transcript` 转换为 provider 特定协议格式的纯函数：

| 翻译器 | 输入 | 输出 | 格式 |
|------------|-------|--------|--------|
| `AnthropicTranscriptTranslator.translate` | Transcript | `(messages, system)` | Anthropic Messages API |
| `DeepSeekTranscriptTranslator.translateAnthropicCompat` | Transcript | `(messages, system)` | Anthropic Messages（委托 + 移除 cache_control） |
| `DeepSeekTranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions（委托给 `OpenAITranscriptTranslator`） |
| `DeepSeekTranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API（委托给 `OpenAITranscriptTranslator`） |
| `OpenAITranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions messages[] 含 role-flushing |
| `OpenAITranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API 类型化输入条目 |

所有翻译器都包含 role-flushing 逻辑：连续相同 role 的条目合并为一条消息；role 变更（user↔assistant）或工具边界触发 flush。DeepSeek 翻译器委托给规范化的 Anthropic/OpenAI 翻译器，并做格式特定的后处理。

---

## 6. 工具系统

### 6.1 Tool 协议（Apple 对齐）

`Tools/RuntimeAgentTool.swift` — `Tool` 协议，带双重关联类型，与 Apple FoundationModels 对齐：

```swift
public protocol Tool<Arguments, Output>: Sendable {
    associatedtype Arguments: Codable & Sendable
    associatedtype Output: PromptRepresentable
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    func call(arguments: Arguments) async throws -> Output
    func _callFromData(_ input: Data) async throws -> ToolOutputValue
}
```

对齐前的关键变更：
- **`Output` 关联类型** — 工具可以返回遵循 `PromptRepresentable` 的类型化输出。默认为 `ToolOutputValue`。
- **`call(arguments:)` 返回 `Output`** — 与 Apple 的 `func call(arguments:) async throws -> Output` 对齐。
- **`_callFromData` 返回 `ToolOutputValue`** — 类型擦除路径对于 `ToolEngine.execute(name:input:)` 保持稳定。
- **60+ 工具** 声明 `typealias Output = ToolOutputValue`。
- **`@concurrent`** 注解标记供将来 Swift 6 采用。

`ToolOutputValue` 遵循 `PromptRepresentable` 以实现 Apple 对齐。已弃用的 `RuntimeAgentTool` typealias 保留用于向后兼容。

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

以 `(any Tool, ToolMetadata)` 对的形式注册在 `DefaultToolEngine` 中。

### 6.3 批次注册表

工具被划分为 3 个批次以支持并行加载：

| 批次 | 数量 | 类别 | 文件 |
|-------|-------|------------|------|
| Batch 1 | ~15 | 只读：FileRead、Grep、Glob、WebSearch、WebFetch、ListSkills 等 | `Batch1ToolRegistry.swift` |
| Batch 23 | ~9 | 文件修改 + 命令：FileWrite、FileEdit、Bash、NotebookEdit、LSP | `Batch23ToolRegistry.swift` |
| Batch 45 | ~36 | 任务/agent/工作流/MCP/cron/通知：AgentTool、TaskCreate、MCPTool、SkillTool 等 | `Batch45ToolRegistry.swift` |

每个注册表暴露 `static func tools(...) -> [(any Tool, ToolMetadata)]`，参数通过依赖注入（工作目录、MCP 客户端等）。

### 6.4 DefaultToolEngine

`SubsystemStubs.swift:8` — 基于 actor 的工具注册表，遵循 `ToolEngine`：

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

`Tools/ToolOutputValue.swift:9` — 工具结果的两种 case 枚举：

```swift
public enum ToolOutputValue: Sendable {
    case string(String)
    case blocks([OutputBlock])
}
```

`OutputBlock` 有 `type`（`text`、`code`、`diff`、`image`、`error`）和 `content: String`。`stringValue` 计算属性提供文本回退。

---

## 7. 权限

### 7.1 AgentPermission

`Providers/AgentPermission.swift:10` — 13 种 case，涵盖文件系统、网络、设备和执行领域：

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

`toolName` 计算属性将每个 case 映射到规范工具名（如 `.runCommands → "Bash"`、`.readFiles → "Read"`），用于与传统 `PermissionEngine` 集成。

### 7.2 SessionPermissionEngine

`Providers/AgentPermission.swift:103` — 单方法协议：

```swift
public protocol SessionPermissionEngine: Sendable {
    func check(_ permission: AgentPermission) async throws -> Bool
}
```

### 7.3 AgentPermissionBridge

`Providers/Permission/AgentPermissionBridge.swift:12` — 将传统 `PermissionEngine` 适配为 `SessionPermissionEngine`。将每个 `AgentPermission` case 映射为基于工具名称的权限检查，通过包装的 engine 将关联的 paths/domains 编码到输入字典中。

---

## 8. 记忆

### 8.1 SessionMemoryStore 协议

`Providers/SessionMemoryStore.swift:40` — 通用 key-namespace 存储：

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

`Providers/Memory/SQLiteMemoryStore.swift:13` — 基于 actor 的实现，使用直接 SQLite3 C API（无第三方依赖）。

- **WAL journal 模式**以获得并发读取性能。
- **4 个 schema migrations**：`schema_version` 表、`memory_entries` 表（key、namespace、value JSON BLOB、updated_at）、namespace 和 updated_at 上的索引。
- **仅使用参数化查询** — 无字符串拼接。
- **通过 actor 进行序列化访问** — 所有 CRUD 调用均为 `async`。
- 值存储为 JSON BLOBs — `Codable` 类型通过 `JSONEncoder`/`JSONDecoder` 编码/解码。

---

## 9. 错误分类

`AgentRuntimeError.swift:5` — 19 种 case，涵盖 5 个领域，全部遵循 `LocalizedError`。仿照 Apple `LanguageModelError` 模式，使用专用 info 结构体提供丰富的错误上下文。

### 9.1 错误信息结构体（Apple 对齐）

六个专用结构体，仿照 Apple 的 `LanguageModelError` 嵌套 info 类型建模：

| 结构体 | 属性 | Apple 来源 |
|--------|-----------|--------------|
| `ContextSizeExceeded` | `maxTokens: Int`、`requestedTokens: Int` | `LanguageModelError.ContextSizeExceeded` |
| `RateLimited` | `retryAfter: TimeInterval?` | `LanguageModelError.RateLimited` |
| `Refusal` | `reason: String` | `LanguageModelError.Refusal` |
| `Timeout` | `duration: TimeInterval?` | `LanguageModelError.Timeout` |
| `GuardrailViolation` | `guardrail: String`、`reason: String` | `LanguageModelError.GuardrailViolation` |
| `UnsupportedCapability` | `capability: String` | `LanguageModelError.UnsupportedCapability` |

### 9.2 按领域分类的错误 Cases

| 领域 | Cases |
|--------|-------|
| **Model** | `rateLimited(RateLimited)`、`unauthorized(reason:)`、`serverError(statusCode:body:)`、`timeout(Timeout)`、`contextSizeExceeded(ContextSizeExceeded)`、`invalidResponse(reason:)`、`refusal(Refusal)`、`guardrailViolation(GuardrailViolation)`、`unsupportedCapability(UnsupportedCapability)` |
| **Memory** | `storageFull(availableBytes:)`、`keyNotFound(key:namespace:)`、`migrationFailed(fromVersion:toVersion:reason:)` |
| **Permission** | `permissionDenied(permission:reason:)`、`sandboxViolation(resource:)` |
| **Tool** | `toolNotFound(name:)`、`toolExecutionFailed(name:reason:)`、`toolValidationFailed(name:field:reason:)` |
| **Graph** | `cycleDetected(nodes:)`、`nodeFailed(nodeID:reason:)` |

每个 case 提供人类可读的 `errorDescription` 供 UI 展示。Model 类 case（rateLimited、timeout、contextSizeExceeded、refusal、guardrailViolation、unsupportedCapability）携带结构化信息用于编程式处理 — 重试延迟、token 计数、拒绝原因等。

---

## 10. 集成层

### 10.1 App：ThreadViewModel

`ViewModels/ThreadViewModel.swift:40` — 对话线程的 `@MainActor` view model。

**Session 创建**：`AppViewModel.makeSession()` 创建 `LanguageModelSessionImpl`，包含：
- `DeepSeekProvider`（Anthropic-compat 模式，`deepseek-v4-pro`）
- `SQLiteMemoryStore`，位于 `~/.swift-agent/projects/<path>/`
- `AgentPermissionBridge` 包装的传统 `PermissionEngine`
- `DefaultToolEngine` 加载 Batch1 + Batch23 工具

**流处理**（`send()` at L257 → `startAgentRun()` at L293）：
1. 追加用户消息，创建 assistant 占位符，设置 `state = .executing`
2. 调用 `session.streamResponse(to: trimmed)` → 返回 `AsyncThrowingStream`
3. `for try await event in stream` 分发到 `handleSessionEvent()`：
   - `.textDelta` / `.thinkingDelta` → 追加到 assistant 消息 blocks
   - `.toolCallRequested` / `.toolCallCompleted` → 添加 `ToolUseBlock` / `ToolResultBlock`
   - `.turnCompleted(usage:)` → 记录 token 用量
   - `.error` → 设置 `state = .failed`，取消流
4. 流耗尽 → `handleStreamComplete()` → 完成消息，持久化到 JSONL，处理排队消息

**持久化**：消息拆分为 thinking 和非 thinking blocks，每个以独立的 JSONL 条目写入，带链式 `parentUuid`（Claude Code 格式）。文件 I/O 在 `Task.detached` 中运行。

### 10.2 App：AppViewModel

`ViewModels/AppViewModel.swift` — 管理 API key 解析、provider 配置和 session 工厂（`makeSession()`）。当前模型选择通过 `currentModel` 发布（默认：`deepseek-v4-pro`）。权限模式（`default`/`acceptEdits`/`bypassPermissions`/`plan`）驱动 `AgentPermissionBridge` 配置。

### 10.3 CLI：ChatCommand

`ChatCommand.swift` — 行内创建 `LanguageModelSessionImpl`，使用相同的 4 个依赖项。迭代 `streamResponse(to:)` 并通过 `SessionEventRenderer` 将 `SessionEvent` 值渲染为 ANSI 终端输出。

---

## 11. 子系统 Stub 和未来预留位

### 11.1 No-Op 实现

`SubsystemStubs.swift:53` 为尚未实现的协议提供三个 stub：

- **`NoOpSessionContextManager`** — 遵循 `SessionContextManager`（空协议）。未来：上下文窗口跟踪和自动压缩。
- **`NoOpProfileManager`** — 遵循 `ProfileManager`（空协议）。未来：agent 身份、个性和行为 profile。
- **`NoOpSessionHookSystem`** — 遵循 `SessionHookSystem`（空协议）。未来：生命周期 hooks（pre-prompt、post-response、pre-tool）。

### 11.2 AgentGraph

`Graph/AgentGraph.swift:10` — 仅为协议的类型占位符，用于多 agent 编排：

```swift
public protocol AgentGraph: Sendable {
    var nodes: [any AgentNode] { get }
    func validate() throws
}
```

预留供将来 WWDC27 AgentKit `WorkflowGraph` 集成使用。`LanguageModelSessionImpl.graphEngine` 为可选 — 当无多 agent graph 活动时为 `nil`。

### 11.3 PartiallyGenerated

`PartiallyGenerated.swift` — 结构化输出流式传输的通用快照累积器。持有 `snapshot`、`previousSnapshot`、`changedKeys`、`isComplete`。尚未接入 agent 循环 — 为将来的结构化 JSON 输出模式设计。

---

## 文件索引

| 文件 | 用途 |
|------|---------|
| `LanguageModelSession.swift` | 编排器协议 + ToolEngine + 3 个 stub 子系统协议 |
| `LanguageModelSessionImpl.swift` | Actor 实现 — agent 循环、工具执行、流式/非流式双路径 |
| `StreamingGenerationChannel.swift` | 公开 actor — 带快照语义的 continuation 桥接 |
| `GenerationChannel.swift` | 6 方法流式抽象协议 |
| `SessionEvent.swift` | Provider 无关的流式事件枚举 |
| `Transcript.swift` | 可编码对话历史（7 种条目类型） |
| `LanguageModel.swift` | LanguageModel 协议 + LanguageModelCapabilities |
| `LanguageModelExecutor.swift` | Executor 协议 + GenerationOptions + SessionToolDefinition |
| `AgentPermission.swift` | 运行时权限枚举（13 种）+ SessionPermissionEngine 协议 |
| `AgentRuntimeError.swift` | 统一错误类型（19 种 case，5 个领域，6 个 Apple 对齐的 info 结构体） |
| `RuntimeAgentTool.swift` | 双重关联类型的 Tool 协议（Arguments、Output） |
| `Prompt.swift` | Prompt/PromptRepresentable/PromptBuilder + 多模态附件类型 |
| `Instructions.swift` | Instructions 结构体 + InstructionsBuilder result builder |
| `TranscriptErrorHandlingPolicy.swift` | 生成过程的错误处理策略（工具错误、上下文溢出） |
| `Usage.swift` | Token 用量（CC 对齐的 NonNullableUsage） |
| `Response.swift` | Response 结构体 + ResponseStream typealias |
| `SubsystemStubs.swift` | NoOp stubs + DefaultToolEngine actor |
| `AgentPermissionBridge.swift` | 传统 PermissionEngine 的 SessionPermissionEngine 适配器 |
| `SQLiteMemoryStore.swift` | 基于 SQLite3 actor 的记忆存储，含 schema migration |
| **Provider 文件** | |
| `AnthropicProvider.swift` | Anthropic Messages API provider |
| `DeepSeekProvider.swift` | DeepSeek 双 API provider |
| `OpenAIProvider.swift` | OpenAI Chat Completions provider |
| `AnthropicSSEParser.swift` | Anthropic SSE 流解析器 |
| `DeepSeekSSEParser.swift` | DeepSeek 双模式 SSE 解析器 |
| `OpenAISSEParser.swift` | OpenAI Chat Completions SSE 解析器 |
| `AnthropicTranscriptTranslator.swift` | Transcript → Anthropic 协议格式 |
| `DeepSeekTranscriptTranslator.swift` | Transcript → DeepSeek 协议格式（双模式） |
| `OpenAITranscriptTranslator.swift` | Transcript → OpenAI 协议格式 |
| `AnthropicContentAccumulator.swift` | 按索引的工具输入 JSON 累积器 |
| **工具批次文件** | |
| `Batch1ToolRegistry.swift` | 15 个只读工具 |
| `Batch23ToolRegistry.swift` | 9 个文件/命令工具 |
| `Batch45ToolRegistry.swift` | 36 个任务/agent/mcp 工具 |
| **集成文件** | |
| `ThreadViewModel.swift` | App：session 创建、流处理、持久化 |
| `AppViewModel.swift` | App：API key、provider 配置、session 工厂 |
| `ChatCommand.swift` | CLI：session 创建、ANSI 渲染 |
