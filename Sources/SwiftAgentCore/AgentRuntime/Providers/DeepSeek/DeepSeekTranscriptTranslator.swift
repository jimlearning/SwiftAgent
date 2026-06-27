import Foundation

/// Translates Transcript entries into DeepSeek wire format for both
/// Anthropic-compatible and OpenAI-compatible endpoints.
/// Pure-functional: no mutable state, no side effects. Independently testable.
struct DeepSeekTranscriptTranslator: Sendable {

    // MARK: - Anthropic-Compatible Translation

    /// Translate Transcript into Anthropic Messages API format for DeepSeek's
    /// Anthropic-compatible endpoint (/anthropic/v1/messages).
    ///
    /// Same pattern as AnthropicTranscriptTranslator EXCEPT:
    /// - Strips ALL cache_control keys from content blocks (DeepSeek doesn't support prompt caching)
    /// - Preserves .thinking as proper thinking content blocks (required by thinking mode)
    ///
    /// - Returns: (messages, optional system prompt)
    static func translateAnthropicCompat(
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
                // tool_use must be in the SAME assistant message as preceding
                // thinking/text blocks (Anthropic Messages API requirement).
                // Do NOT flush() — that would create a separate assistant message.
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
                if currentRole != "user" { flush() }
                currentRole = "user"
                currentBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": output,
                    "is_error": isError,
                ])

            case .thinking(let text, let signature):
                // Include thinking blocks for round-trip. DeepSeek reasoning models
                // return thinking blocks with signature:"" — omit the signature key
                // entirely when empty to avoid server-side validation issues.
                if currentRole != "assistant" { flush() }
                currentRole = "assistant"
                var block: [String: Any] = ["type": "thinking", "thinking": text]
                if let sig = signature, !sig.isEmpty {
                    block["signature"] = sig
                }
                currentBlocks.append(block)

            case .system(let text):
                flush()
                currentRole = "user"
                currentBlocks.append(["type": "text", "text": "[System] \(text)"])
            }
        }

        flush()

        // Build system parameter
        let system: Any?
        if let external = systemPrompt {
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

    // MARK: - OpenAI-Compatible Translation

    /// Translate Transcript into OpenAI Chat Completions message array for
    /// DeepSeek's OpenAI-compatible endpoint (/v1/chat/completions).
    ///
    /// Mapping:
    /// - .instruction(String) -> {role: "system", content: String}
    /// - .prompt(String) -> {role: "user", content: String}
    /// - .response(String) -> {role: "assistant", content: String}
    /// - .toolCall(id, name, input) -> {role: "assistant", tool_calls: [{id, type: "function", function: {name, arguments}}]}
    /// - .toolOutput(id, output, isError) -> {role: "tool", tool_call_id: id, content: output}
    /// - .thinking(String) -> {role: "assistant", content: "[Thinking] \(text)"}
    /// - .system(String) -> {role: "user", content: "[System] \(text)"}
    ///
    /// - Returns: Array of ChatMessage dictionaries
    static func translateOpenAICompat(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Build system message from systemPrompt + transcript instructions
        var systemParts: [String] = []
        if let external = systemPrompt {
            systemParts.append(external)
        }
        for entry in transcript.entries {
            if case .instruction(let text) = entry {
                systemParts.append(text)
            }
        }
        if !systemParts.isEmpty {
            messages.append([
                "role": "system",
                "content": systemParts.joined(separator: "\n\n"),
            ])
        }

        // Map remaining entries to ChatMessage dicts
        for entry in transcript.entries {
            switch entry {
            case .instruction:
                break // Already handled in system message above

            case .prompt(let text):
                messages.append(["role": "user", "content": text])

            case .response(let text):
                messages.append(["role": "assistant", "content": text])

            case .toolCall(let id, let name, let input):
                let argsStr = (try? JSONSerialization.jsonObject(with: input))
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                messages.append([
                    "role": "assistant",
                    "tool_calls": [[
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": argsStr,
                        ],
                    ]],
                ])

            case .toolOutput(let id, let output, _):
                messages.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "content": output,
                ])

            case .thinking:
                // Drop thinking entries from re-prompt history. Reasoning models
                // return reasoning_content in streaming, but re-prompt messages
                // carry only standard Chat Completions fields (role/content/tool_calls).
                // Including reasoning_content or thinking-as-text triggers server-side
                // thinking-mode validation on some models (e.g. deepseek-v4-pro).
                // This matches Claude Code's convention of clean re-prompts.
                break

            case .system(let text):
                messages.append([
                    "role": "user",
                    "content": "[System] \(text)",
                ])
            }
        }

        return messages
    }
}
