# AgentGraph Integration Test 调试复盘

> 调试周期：2026-06-26 15:23–17:30 UTC+8（首轮）+ 2026-06-27（第二轮，根因定位 + 跨端点修复）
> 涉及文件：DeepSeekProvider, DeepSeekSSEParser, AnthropicSSEParser, DeepSeekTranscriptTranslator, AnthropicTranscriptTranslator, LanguageModelSessionImpl, AgentGraphIntegrationTests

---

## 背景

`AgentGraphIntegrationTests` 测试 GitDiffAnalyzer → CommitMessageCrafter 两节点 AgentGraph 工作流，使用 DeepSeek V4 Pro 支持 anthropic-compatible 和 openai-compatible 两种端点。

测试全程发现三个独立 bug，修复后完整工作流在两种端点均通过。

---

## Bug 1: AsyncStream + unstructured Task 静默吞错误

### 现象

流在早期（2-5 秒内）悄然截断，无错误信息，仅数据不完整。约 90% 运行失败，10% 成功。

### 根因

`DeepSeekProvider.streamAndParse()` 使用 `AsyncStream<String>` + 内部 `Task` 来桥接 `URLSession.AsyncBytes`：

```swift
let lineStream = AsyncStream<String> { continuation in
    Task {  // ← 无主 Task，actor 隔离丢失
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                continuation.yield(line)
            }
            continuation.finish()
        } catch {
            continuation.finish()  // ← 所有错误被静默吞掉
        }
    }
}
let parser = DeepSeekSSEParser()
try await parser.parse(lines: lineStream, channel: channel, compatibility: compatibility)
```

`catch` 块仅调用 `continuation.finish()`——不抛、不调用 `channel.fail()`。网络抖动、服务器 hiccup、连接断开等错误被静默吞掉，上层 parser 收到截断流后表现为 incomplete response。

为何间歇性：网络/服务器时序非确定。若完整响应在错误前到达，测试通过；若错误发生在中途，流截断。

### 修复

移除 AsyncStream 桥接层，将 `DeepSeekSSEParser` 从 `actor` 改为 `struct`（它本身无状态，所有积累用局部变量），parse 方法接受泛型 `AsyncSequence<String>`，直接传入 `bytes.lines`：

```swift
struct DeepSeekSSEParser {
    func parse<S: AsyncSequence>(lines: S, ...) async throws where S.Element == String
}

// 调用方
let parser = DeepSeekSSEParser()
try await parser.parse(lines: bytes.lines, channel: channel, ...)
```

网络错误现在通过 `try/catch` 自然传播到外层错误处理器，后者调用 `channel.fail(with:)`。

### 教训

- **`Task { }` 内不要静默吞错误**。无主 Task 的 `catch` 块对上层完全透明。
- **AsyncStream 是桥接层，不是数据源**。已有原生 `AsyncSequence` 时直接迭代即可。
- **actor 隔离不是免费午餐**。无状态 parser 用 struct + `Sendable`，不需要 actor。
- **间歇性失败 = 静默错误吸收**。任何不稳定表现优先排查是否被 catch 吞掉。

---

## Bug 2: `signature_delta` SSE 事件未捕获

### 现象

DeepSeek V4 Pro 在 anthropic-compatible 端点返回 thinking block 时，`content_block_start` 事件的 `signature` 字段为空字符串 `""`，但真正的签名通过后续的 `signature_delta` SSE 事件下发。未捕获 `signature_delta` 导致：
- `thinkingSignature` 保持 `nil`
- re-prompt 请求中的 thinking block 带空签名 → HTTP 400

### 根因

`AnthropicSSEParser` 只解析了 `content_block_start` 中的 `signature` 字段，未实现 `signature_delta` 事件处理器。DeepSeek 的行为是：content_block_start 给空签名，signature_delta 给真实签名（UUID 格式）。

### 修复

在 `AnthropicSSEParser` 中新增 `signature_delta` case：

```swift
case "signature_delta":
    if let sig = delta["signature"] as? String {
        thinkingSignature = sig
        await channel.update(thinkingSignature: sig)
    }
```

### 教训

- **不假设 SSE 事件顺序和内容**。DeepSeek 的 thinking 签名分两阶段下发，与 Anthropic 的 API 行为不同。
- **空字符串不等于未提供**。`if let sig = block["signature"] as? String` 会通过空字符串，需要额外检查 `!sig.isEmpty`。

---

## Bug 3: Tool Call 拆分导致 assistant 消息结构错误

### 现象

Bug 1 和 Bug 2 修复后，测试在第一次模型响应后的 re-prompt 时确定性返回 HTTP 400：

```
anthropic-compat: "The `content[].thinking` in the thinking mode must be passed back to the API."
openai-compat:    "The `reasoning_content` in the thinking mode must be passed back to the API."
```

无论用 anthropic-compatible 还是 openai-compatible 端点，错误信息不同但都指向 thinking mode 验证失败。

### 首轮错误推断（已推翻）

首轮调试中推断为 DeepSeek V4 Pro 服务端追踪 thinking mode 状态，在 session 级别要求所有 re-prompt 携带 thinking blocks。基于此推断尝试了 8 种绕过方案全部失败，最终使用 `deepseek-chat`（非 reasoning model）作为 workaround。

### 真实根因

**Tool_use blocks 被拆分到多个 assistant 消息**，违反 Anthropic Messages API 格式规范。

`LanguageModelSessionImpl.respond(to:)` 的事件循环逐一处理 `toolCallRequested` 事件——每收到一个 tool call 立即执行并 append 其 output 到 transcript。当模型一次返回多个 tool calls 时，transcript 被组织为：

```
transcript.entries = [
  .thinking("..."),                          // assistant message 1
  .response("..."),
  .toolCall(id: "call_00", name: "Bash"),    // still assistant message 1
  .toolOutput(id: "call_00", ...),           // → flush → user message 1
  .toolCall(id: "call_01", name: "Read"),    // → flush → assistant message 2 (WRONG!)
  .toolOutput(id: "call_01", ...),           // → flush → user message 2 (WRONG!)
  .toolCall(id: "call_02", name: "Grep"),    // → flush → assistant message 3 (WRONG!)
  .toolOutput(id: "call_02", ...),           // → flush → user message 3 (WRONG!)
]
```

translator 将此翻译为：
```json
[
  {"role": "assistant", "content": [{"type": "thinking"}, {"type": "text"}, {"type": "tool_use", "id": "call_00"}]},
  {"role": "user",      "content": [{"type": "tool_result", "tool_use_id": "call_00"}]},
  {"role": "assistant", "content": [{"type": "tool_use", "id": "call_01"}]},         // ← 不应有第二个 assistant
  {"role": "user",      "content": [{"type": "tool_result", "tool_use_id": "call_01"}]},  // ← 不应有第二个 user
  {"role": "assistant", "content": [{"type": "tool_use", "id": "call_02"}]},         // ← 不应有第三个 assistant
  {"role": "user",      "content": [{"type": "tool_result", "tool_use_id": "call_02"}]},  // ← 不应有第三个 user
]
```

Anthropic Messages API 要求模型一次响应的所有 tool_use 在一个 assistant 消息中、所有 tool_result 在一个 user 消息中。拆分后 DeepSeek 的兼容端点在内部验证时检测到 thinking block 与 tool_use block 分离，触发 thinking mode 验证错误（误导性错误信息）。

为何 `deepseek-chat` 可绕过此问题：`deepseek-chat` 不返回 thinking blocks，服务器跳过 thinking mode 验证，即便 tool_use 结构错误也能通过。**绕过不是修复**。

### 修复

**两轮 batching**：在 `LanguageModelSessionImpl.respond(to:)` 中将 tool call 处理改为两轮：

1. **第一轮**：遍历所有 events，识别所有 toolCallRequested 事件但不执行
2. **第二轮**：追加 thinking + response text + 所有 toolCall → 然后逐一执行 tool 并追加所有 toolOutput

```swift
// 第一轮：收集所有 tool calls
var pendingToolCalls: [(id: String, name: String, input: Data)] = []
for event in events {
    switch event {
    case .toolCallRequested(let id, let name, let input):
        pendingToolCalls.append((id, name, input))
    // ...
    }
}

// 第二轮：flush thinking + text + ALL tool_calls + ALL tool_outputs
if hasToolCalls {
    transcript.entries.append(.thinking(thinkingText, signature: thinkingSig))
    transcript.entries.append(.response(responseText))
    for call in pendingToolCalls {
        transcript.entries.append(.toolCall(id: call.id, name: call.name, input: call.input))
    }
    for call in pendingToolCalls {
        // 执行 + append toolOutput
    }
}
```

对应修改两个 Translator，使 consecutive tool_use 和 consecutive tool_output 不触发 flush：

| Translator | case | 原代码 | 改为 |
|------------|------|--------|------|
| `DeepSeekTranscriptTranslator` | `.toolOutput` | `flush()` | `if currentRole != "user" { flush() }` |
| `AnthropicTranscriptTranslator` | `.toolCall` | `flush()` | `if currentRole != "assistant" { flush() }` |
| `AnthropicTranscriptTranslator` | `.toolOutput` | `flush()` | `if currentRole != "user" { flush() }` |

### OpenAI 兼容端点的额外修复

OpenAI Chat Completions 格式（`/v1/chat/completions`）与 Anthropic Messages API 格式不同，translator 需要额外的修复：

**问题 1：thinking 条目被丢弃。** `DeepSeekTranscriptTranslator.translateOpenAICompat()` 原本用 `break` 忽略 `.thinking` 条目。但 DeepSeek V4 Pro 在 thinking mode 下要求 re-prompt 中包含 `reasoning_content` 字段。缺失时返回：

```
"The `reasoning_content` in the thinking mode must be passed back to the API."
```

**修复**：将 `.thinking` 转为 `reasoning_content` 字段合并到 assistant 消息中，且 `.response` 和 `.toolCall` 都尝试与包含 `reasoning_content` 的 assistant 消息合并，而非创建新消息。

**问题 2：tool_call 拆分到独立 assistant 消息。** 原代码对每个 `.toolCall` 执行 `messages.append(...)`，即使 tool_call 来自同一模型响应也被拆到不同消息。OpenAI 格式允许一个 assistant 消息携带多个 `tool_calls`。

**修复**：检测最后一个消息是否为 `assistant` 角色，若是则追加到其 `tool_calls` 数组而非创建新消息。同时处理 `reasoning_content` 和 `tool_calls` 在同一消息共存的情况：

```swift
// .thinking → assistant msg with reasoning_content
messages.append(["role": "assistant", "reasoning_content": text])

// .toolCall → merge into the same assistant msg
if messages.last?["role"] as? String == "assistant" {
    var lastMsg = messages.removeLast()
    if var existingCalls = lastMsg["tool_calls"] {
        existingCalls.append(toolCallDict)
        lastMsg["tool_calls"] = existingCalls
    } else {
        lastMsg["tool_calls"] = [toolCallDict]
    }
    messages.append(lastMsg)
}
```

最终 re-prompt 体中，thinking + text + 多个 tool_calls 在一条 assistant 消息内：
```json
{"role": "assistant", "reasoning_content": "...", "content": "...", "tool_calls": [{...}, {...}, {...}]}
```

### 教训

- **错误信息可能是误导性的**。"thinking mode" 错误的真实原因是 tool_use 结构错误，不是 thinking 内容问题。
- **绕过不是修复**。`deepseek-chat` 能工作是因为缺少 thinking 验证路径，不是因为它正确。
- **试错 8 次不如果断看底层**。debug session 实现了高效的并行实验，一次实验是 30-50 秒的编译+执行。但更好的策略是先理解 Anthropic Messages API 对 `tool_use` block 的消息结构要求，而非在 provider/translator 之间反复改。
- **Claude Code 能工作的原因是它发 single-turn per-request**。Claude Code 的 agent loop 中，每次模型请求都携带完整对话历史，不会将一次模型返回的多个 tool_use 拆分到多轮请求。这验证了"Claude Code 能跑 = 我们的代码有问题，不是 server 的问题"。

---

## 调试方法论总结

### 有效的做法

1. **请求体日志**：打印实际发送到 API 的 JSON body，直接验证假设
2. **模型替换**：`deepseek-chat` 作为问题的分离器
3. **请求计数 + 标记**：标记每个请求的结构特征，快速定位问题
4. **系统化试错表**：记录每次尝试，避免重复无效路径
5. **curl 验证**：curl 请求 + 精确的 re-prompt body 可以独立验证 API 行为
6. **对比 Claude Code 行为**：Claude Code 能工作证明了 API 本身没有障碍

### 无效或低效的做法

1. **在 translators 和 parsers 之间反复切换修复点**，没有先确认真实错误位置
2. **多个改动同时做**：同时改 translator 和 provider 导致无法确定哪个改动有效
3. **过早假设根因**：将误导性错误信息当作原因，而非症状
4. **没先看 API 规范**：Anthropic Messages API 的 tool_use block 结构规范是已知的知识

---

## 代码最终状态

| 文件 | 关键变更 |
|------|----------|
| `DeepSeekSSEParser.swift` | actor → struct；parse 方法泛型化 `AsyncSequence<String>` |
| `DeepSeekProvider.swift` | 移除 AsyncStream + Task 桥接 |
| `DeepSeekTranscriptTranslator.swift` | anthropic path: `.toolOutput` 不硬 flush；openai path: `.thinking` 转为 `reasoning_content`，`.toolCall` 合并到同一 assistant 消息，`.response` 合并到含 `reasoning_content` 的 assistant 消息 |
| `AnthropicTranscriptTranslator.swift` | `.toolCall` 不硬 flush；`.toolOutput` 不硬 flush |
| `AnthropicSSEParser.swift` | 新增 `signature_delta` 事件处理器 |
| `LanguageModelSessionImpl.swift` | `respond(to:)` 两轮 batching：先收集所有 tool calls 再执行 |
| `AgentGraphIntegrationTests.swift` | 使用 `deepseek-v4-pro`，支持两种端点（默认 anthropic-compatible） |

最终验证：两节点工作流（GitDiffAnalyzer → CommitMessageCrafter）使用 deepseek-v4-pro 经 **anthropic-compatible 和 openai-compatible 两种端点**完整运行，生成 diff analysis → 执行 git 命令 → 生成 Conventional Commits 消息 → 写入结果文件。
