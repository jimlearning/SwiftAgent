import Foundation

/// Translates Transcript entries into OpenAI Chat Completions API message format.
/// Pure-functional: no mutable state, no side effects. Independently testable.
///
/// Unlike AnthropicTranscriptTranslator (role-flushing with multi-block messages),
/// OpenAI uses flat message array where each non-instruction entry maps to
/// exactly one message in the output array.
struct OpenAITranscriptTranslator: Sendable {

    /// Translate a Transcript into OpenAI Chat Completions messages[] array.
    ///
    /// - Parameters:
    ///   - transcript: The conversation history to translate.
    ///   - systemPrompt: An external system prompt string (e.g. from AgentProfile).
    /// - Returns: An array of message dicts, each with "role" and "content" keys.
    static func translate(
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
                // Already handled above — system message is prepended
                break

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
                // OpenAI Chat Completions uses `role: "tool"` + `tool_call_id`.
                // The `isError` flag has no direct equivalent in OpenAI's format —
                // error outputs are regular tool results with role:"tool".
                _ = isError
                messages.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "content": output,
                ])

            case .thinking(let text):
                // For non-o4 models: thinking content is included as assistant content
                // with a "[Thinking]" prefix. OpenAI rejects thinking content in message
                // history for non-reasoning models. The modelID is not available to the
                // translator, so we always use the text prefix approach.
                messages.append(["role": "assistant", "content": "[Thinking] \(text)"])

            case .system(let text):
                // System reminders are injected as user-role messages.
                // OpenAI uses `role: "user"` as the catch-all for non-standard messages.
                messages.append(["role": "user", "content": "[System] \(text)"])
            }
        }

        return messages
    }
}
