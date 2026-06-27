import Foundation

/// Translates Transcript entries into OpenAI Responses API wire format.
///
/// Responses API is the recommended API for new projects (2026+). Unlike Chat
/// Completions (messages → one assistant message), Responses API models the
/// full agent execution cycle as typed output items:
///
/// ```swift
/// input: [
///   {type: "message", role: "developer", content: [...]},
///   {type: "message", role: "user",      content: [...]},
///   {type: "reasoning",  ...},
///   {type: "function_call", ...},
///   {type: "tool_call_output", ...},
///   {type: "message", role: "assistant", content: [...]},
/// ]
/// ```
///
/// Each item type maps to a natural agent primitive:
/// - `.instruction` / `.system` → developer message
/// - `.prompt` → user message
/// - `.response` → assistant message
/// - `.toolCall` → function_call item
/// - `.toolOutput` → tool_call_output item
/// - `.thinking` → reasoning item
///
/// The old `DeepSeekTranscriptTranslator`, `AnthropicTranscriptTranslator`,
/// and `OpenAITranscriptTranslator` remain for backward compatibility with
/// Chat Completions / Anthropic Messages API endpoints.
struct ResponsesTranscriptTranslator: Sendable {

    /// Translate a Transcript into Responses API input items.
    ///
    /// - Parameters:
    ///   - transcript: The conversation history to translate.
    ///   - systemPrompt: Optional external system prompt prepended to input.
    /// - Returns: Array of Responses API input item dictionaries.
    static func translate(
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
