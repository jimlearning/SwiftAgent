# Transcript

反映与 session 交互的线性历史记录条目。

```
struct Transcript
```

- **Framework**: FoundationModels
- **Availability**: iOS 26.0+, iPadOS 26.0+, macOS 26.0+, macOS Catalyst 26.0+, visionOS 26.0+, watchOS 27.0+
- **Kind**: Structure
- **Module**: Foundation Models

## Overview

使用 `Transcript` 来可视化之前的 instructions、prompts 和 model responses。如果你使用 tool
calling，`Transcript` 包含 tool calls 及其结果的历史记录。

```swift
struct HistoryView: View {
    let session: LanguageModelSession

    var body: some View {
        ScrollView {
            ForEach(session.transcript) { entry in
                switch entry {
                case let .instructions(instructions):
                    MyInstructionsView(instructions)
                case let .prompt(prompt):
                    MyPromptView(prompt)
                case let .reasoning(reasoning):
                    MyReasoningView(reasoning)
                case let .toolCalls(toolCalls):
                    MyToolCallsView(toolCalls)
                case let .toolOutput(toolOutput):
                    MyToolOutputView(toolOutput)
                case let .response(response):
                    MyResponseView(response)
                }
            }
        }
    }
}
```

当你创建一个新的 `LanguageModelSession` 时，它不包含之前 session 的状态。
你可以使用从 session 的 `transcript` 获取的条目列表来初始化一个新 session：

```swift
// 使用前一个 session 的第一个和最后一个条目创建一个新 session。
func newContextualSession(with originalSession: LanguageModelSession) -> LanguageModelSession {
    let allEntries = originalSession.transcript

    // 从原始 session 中收集要保留的条目。
    let entries = [allEntries.first, allEntries.last].compactMap { $0 }
    let transcript = Transcript(entries: entries)

    // 使用结果创建一个新 session 并预加载 session 资源。
    var session = LanguageModelSession(transcript: transcript)
    session.prewarm()
    return session
}
```

## Topics

### Creating a transcript

- `init(entries:)` — 创建一个 transcript。
- `Transcript.Entry` — transcript 中的一个条目。
- `Transcript.Segment` — transcript 条目中可能包含的 segment 类型。
- `Transcript.Attachment` — 附加内容的类型。

### Constructing content

- `Transcript.TextSegment` — 包含文本的 segment。
- `Transcript.StructuredSegment` — 包含结构化内容的 segment。
- `Transcript.ResponseFormat` — 指定模型必须使其输出符合的 response format。
- `Transcript.ToolDefinition` — 工具的定义。
- `Transcript.AttachmentSegment` — 包含附加文件或图像的 segment。
- `Transcript.ImageAttachment` — transcript 条目中的图像 attachment。
- `Transcript.Instructions` — 你提供给模型的 instructions，用于定义其行为。
- `Transcript.Prompt` — 用户给模型的 prompt。
- `Transcript.Reasoning` — 模型的 reasoning 条目。
- `Transcript.Response` — 模型的 response。
- `Transcript.ToolCall` — 模型生成的 tool call，包含工具名称和传递给它的参数。
- `Transcript.ToolCalls` — 模型生成的 tool calls 集合。
- `Transcript.ToolOutput` — 返回给模型的 tool output。
- `Transcript.CustomSegment` —

### Accessing the transcript history

- `history` — transcript 条目，不包括开头的 instructions 条目（如果存在）。

### Getting the structured transcript

- `structuredTranscript` — 此 transcript 的结构化表示，其中 tool calls、outputs 和 responses 被收集到类型化数组中。

---

Source: <https://developer.apple.com/documentation/foundationmodels/transcript>
Copyright &copy; 2026 Apple Inc. All rights reserved.
