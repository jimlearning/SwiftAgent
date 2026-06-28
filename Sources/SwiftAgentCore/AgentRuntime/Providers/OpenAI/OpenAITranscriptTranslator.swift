import Foundation

/// Translates Transcript entries into OpenAI wire format for both
/// Chat Completions and Responses API.
///
/// Pure-functional: no mutable state, no side effects. Independently testable.
struct OpenAITranscriptTranslator: Sendable {

    // MARK: - Chat Completions API

    /// Translate Transcript into Chat Completions `messages[]` format.
    ///
    /// Uses role-flushing to batch consecutive assistant entries (response,
    /// thinking, toolCall) into a single assistant message.
    ///
    /// Mapping:
    ///  .instruction       → system role
    ///  .prompt            → user role
    ///  .response          → assistant content (accumulated with tool_calls)
    ///  .toolCall          → assistant tool_calls (accumulated with content)
    ///  .toolOutput        → tool role with tool_call_id
    ///  .thinking          → assistant reasoning_content (DeepSeek requirement)
    ///  .system            → user with [System] prefix
    ///
    /// - Returns: Array of Chat Completions message dicts.
    static func translateChatCompletions(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var systemParts: [String] = []
        var currentContent: String?
        var currentReasoning: String?
        var currentToolCalls: [[String: Any]] = []

        func flushAssistant() {
            guard currentContent != nil || currentReasoning != nil || !currentToolCalls.isEmpty else { return }
            var msg: [String: Any] = ["role": "assistant"]
            if currentToolCalls.isEmpty {
                msg["content"] = currentContent ?? ""
            } else {
                msg["content"] = currentContent
                msg["tool_calls"] = currentToolCalls
            }
            if let reasoning = currentReasoning {
                msg["reasoning_content"] = reasoning
            }
            messages.append(msg)
            currentContent = nil
            currentReasoning = nil
            currentToolCalls = []
        }

        for entry in transcript.entries {
            switch entry {
            case .instruction(let text):
                systemParts.append(text)

            case .prompt(let text):
                flushAssistant()
                messages.append(["role": "user", "content": text])

            case .response(let text):
                flushAssistant()
                currentContent = text

            case .toolCall(let id, let name, let input):
                if currentContent == nil && currentReasoning == nil {
                    flushAssistant()
                }
                let argsStr = (try? JSONSerialization.jsonObject(with: input))
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                currentToolCalls.append([
                    "id": id,
                    "type": "function",
                    "function": ["name": name, "arguments": argsStr],
                ])

            case .toolOutput(let id, let output, let isError):
                flushAssistant()
                var msg: [String: Any] = [
                    "role": "tool",
                    "tool_call_id": id,
                    "content": output,
                ]
                if isError { msg["is_error"] = true }
                messages.append(msg)

            case .thinking(let text, _):
                // DeepSeek reasoning models require `reasoning_content` to be
                // passed back verbatim on re-prompt. Flush only if preceding
                // role is not already assistant, so thinking batches with the
                // same assistant turn.
                if currentContent != nil || !currentToolCalls.isEmpty {
                    // Already accumulating an assistant message — add reasoning alongside.
                    currentReasoning = text
                } else {
                    flushAssistant()
                    currentReasoning = text
                }

            case .system(let text):
                flushAssistant()
                messages.append(["role": "user", "content": "[System] \(text)"])
            }
        }
        flushAssistant()

        // Prepend external system prompt + instruction parts as system message
        var systemPartsAll = systemParts
        if let prompt = systemPrompt, !prompt.isEmpty {
            systemPartsAll.insert(prompt, at: 0)
        }
        if !systemPartsAll.isEmpty {
            messages.insert([
                "role": "system",
                "content": systemPartsAll.joined(separator: "\n\n"),
            ], at: 0)
        }

        return messages
    }

    // MARK: - Responses API (Recommended)

    /// Translate Transcript into Responses API input items.
    ///
    /// Responses API models the full agent cycle as typed items:
    ///   reasoning → function_call → tool_call_output → message
    ///
    /// Mapping:
    ///   .instruction/.system → developer message
    ///   .prompt              → user message
    ///   .response            → assistant message (output_text)
    ///   .toolCall            → function_call item
    ///   .toolOutput          → tool_call_output item
    ///   .thinking            → reasoning item
    ///
    /// - Returns: Array of Responses API input item dictionaries.
    static func translateResponses(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        var items: [[String: Any]] = []

        // Prepend external system prompt as a developer message.
        if let prompt = systemPrompt, !prompt.isEmpty {
            items.append(developerMessage(prompt))
        }

        for entry in transcript.entries {
            switch entry {
            case .instruction(let text):
                items.append(developerMessage(text))

            case .prompt(let text):
                items.append(userMessage(text))

            case .response(let text):
                items.append(assistantMessage(text))

            case .toolCall(let id, let name, let input):
                let parsedInput = (try? JSONSerialization.jsonObject(with: input))
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                items.append([
                    "type": "function_call",
                    "call_id": id,
                    "name": name,
                    "arguments": parsedInput,
                ])

            case .toolOutput(let id, let output, let isError):
                items.append([
                    "type": "tool_call_output",
                    "tool_call_id": id,
                    "output": output,
                    "is_error": isError,
                ])

            case .thinking(let text, let signature):
                var reasoning: [String: Any] = ["type": "reasoning", "reasoning": ["text": text]]
                if let sig = signature, !sig.isEmpty {
                    reasoning["signature"] = sig
                }
                items.append(reasoning)

            case .system(let text):
                items.append(developerMessage("[System] \(text)"))
            }
        }

        return items
    }

    // MARK: - Helpers

    private static func developerMessage(_ text: String) -> [String: Any] {
        [
            "type": "message",
            "role": "developer",
            "content": [["type": "input_text", "text": text]],
        ]
    }

    private static func userMessage(_ text: String) -> [String: Any] {
        [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": text]],
        ]
    }

    private static func assistantMessage(_ text: String) -> [String: Any] {
        [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": text]],
        ]
    }
}
