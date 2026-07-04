import Foundation

/// Translates Transcript entries into Anthropic Messages API wire format.
/// Pure-functional: no mutable state, no side effects. Independently testable.
///
/// Implements the role-flushing pattern from LLMClient.Message.apiFormatted:
/// iterate entries, build content blocks for current role, flush when role
/// changes or entry type demands a new message boundary.
struct AnthropicTranscriptTranslator: Sendable {

    /// Translate a Transcript into Anthropic messages[] array and optional system prompt.
    ///
    /// - Parameters:
    ///   - transcript: The conversation history to translate.
    ///   - systemPrompt: An external system prompt string (e.g. from AgentProfile).
    /// - Returns: A tuple of `(messages: [[String: Any]], system: Any?)` where
    ///   `system` may be a plain String or an array of system content blocks.
    static func translate(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> (messages: [[String: Any]], system: Any?) {
        var messages: [[String: Any]] = []
        var currentRole: String?
        var currentBlocks: [[String: Any]] = []
        var systemParts: [String] = []

        func flush() {
            guard let role = currentRole, !currentBlocks.isEmpty else { return }
            messages.append(["role": role, "content": currentBlocks])
            currentBlocks = []
            currentRole = nil
        }

        for entry in transcript.entries {
            switch entry {
            case .instruction(let text):
                // Instructions go to the system parameter, not messages array.
                systemParts.append(text)

            case .prompt(let text):
                if currentRole != "user" { flush() }
                currentRole = "user"
                currentBlocks.append(["type": "text", "text": text])

            case .response(let text):
                if currentRole != "assistant" { flush() }
                currentRole = "assistant"
                currentBlocks.append(["type": "text", "text": text])

            case .toolCall(let id, let name, let input):
                // Keep tool_use in the SAME assistant message as preceding
                // thinking/text blocks (Anthropic Messages API requirement).
                if currentRole != "assistant" { flush() }
                currentRole = "assistant"
                let parsedInput = (try? JSONSerialization.jsonObject(with: input) as? [String: Any]) ?? [:]
                currentBlocks.append([
                    "type": "tool_use",
                    "id": id,
                    "name": name,
                    "input": parsedInput,
                ])

            case .toolOutput(let id, let output, let isError):
                // Consecutive tool_results go in the SAME user message.
                if currentRole != "user" { flush() }
                currentRole = "user"
                currentBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": output,
                    "is_error": isError,
                ])

            case .thinking(let text, let signature):
                if currentRole != "assistant" { flush() }
                currentRole = "assistant"
                var block: [String: Any] = ["type": "thinking", "thinking": text]
                block["signature"] = signature ?? ""
                currentBlocks.append(block)

            case .system(let text):
                flush()  // system reminders are always their own message
                currentRole = "user"
                currentBlocks.append(["type": "text", "text": "[System] \(text)"])
            }
        }

        flush()

        // Build system parameter
        let system: Any?
        if let external = systemPrompt {
            // Prepend external system prompt and append transcript instructions
            var allParts = [external]
            allParts.append(contentsOf: systemParts)
            system = allParts.joined(separator: "\n\n")
        } else if !systemParts.isEmpty {
            system = systemParts.joined(separator: "\n\n")
        } else {
            system = nil
        }

        return (messages, system)
    }
}
