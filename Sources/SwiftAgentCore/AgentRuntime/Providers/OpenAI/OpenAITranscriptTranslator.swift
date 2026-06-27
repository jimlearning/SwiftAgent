import Foundation

/// Translates Transcript entries into OpenAI wire formats.
///
/// Provides two translation paths:
/// - `translateResponses()`: Responses API format (recommended for new projects, 2026+).
///   Outputs typed items in an `input` array: message, reasoning, function_call, tool_call_output.
/// - `translateChatCompletions()`: Legacy Chat Completions format (messages[] array).
///   Kept for backward compatibility with older endpoints.
///
/// Pure-functional: no mutable state, no side effects. Independently testable.
struct OpenAITranscriptTranslator: Sendable {

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

    // MARK: - Chat Completions (Legacy)

    /// Translate Transcript into Chat Completions messages[] array.
    ///
    /// Legacy format: flat message array where one entry maps to one message.
    /// Prefer `translateResponses()` for new projects.
    ///
    /// - Returns: Array of message dicts, each with "role" and "content" keys.
    static func translateChatCompletions(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Collect all instruction entries to build a single system message at the start.
        var systemParts: [String] = []
        for entry in transcript.entries {
            if case .instruction(let text) = entry {
                systemParts.append(text)
            }
        }

        // Build system message: external systemPrompt prepended to transcript instructions
        var effectiveSystem: String?
        if let external = systemPrompt {
            var parts = [external]
            parts.append(contentsOf: systemParts)
            effectiveSystem = parts.joined(separator: "\n\n")
        } else if !systemParts.isEmpty {
            effectiveSystem = systemParts.joined(separator: "\n\n")
        }

        if let system = effectiveSystem, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }

        // Translate each entry to a single message (flat array, one entry → one message)
        for entry in transcript.entries {
            switch entry {
            case .instruction:
                break // Already handled above

            case .prompt(let text):
                messages.append(["role": "user", "content": text])

            case .response(let text):
                messages.append(["role": "assistant", "content": text])

            case .toolCall(let id, let name, let input):
                let args = String(data: input, encoding: .utf8) ?? "{}"
                messages.append([
                    "role": "assistant",
                    "tool_calls": [[
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": args,
                        ],
                    ]],
                ])

            case .toolOutput(let id, let output, let isError):
                _ = isError
                messages.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "content": output,
                ])

            case .thinking(let text, _):
                messages.append(["role": "assistant", "content": "[Thinking] \(text)"])

            case .system(let text):
                messages.append(["role": "user", "content": "[System] \(text)"])
            }
        }

        return messages
    }

    // MARK: - Deprecated (renamed to translateChatCompletions)

    @available(*, deprecated, renamed: "translateChatCompletions")
    static func translate(_ transcript: Transcript, systemPrompt: String?) -> [[String: Any]] {
        translateChatCompletions(transcript, systemPrompt: systemPrompt)
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
