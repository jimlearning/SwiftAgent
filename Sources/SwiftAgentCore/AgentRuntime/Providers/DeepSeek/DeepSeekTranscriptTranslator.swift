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

    // MARK: - Responses API

    /// Translate Transcript into Responses API input items.
    /// Delegates to OpenAITranscriptTranslator — the Responses format is
    /// provider-agnostic.
    static func translateResponses(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        OpenAITranscriptTranslator.translateResponses(transcript, systemPrompt: systemPrompt)
    }

    // MARK: - Chat Completions (Legacy)

    /// Translate Transcript into Chat Completions message array for
    /// DeepSeek's OpenAI-compatible endpoint (/v1/chat/completions).
    ///
    /// Like OpenAITranscriptTranslator.translateChatCompletions, but with
    /// DeepSeek-specific enhancements:
    /// - Batches consecutive tool_calls into one assistant message
    /// - Preserves reasoning_content for thinking-mode models (deepseek-v4-pro)
    ///
    /// - Returns: Array of ChatMessage dictionaries
    static func translateChatCompletions(
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
                // Merge with last assistant message if it has reasoning_content
                // (from a preceding .thinking entry), otherwise create a new one.
                if var lastMsg = messages.last,
                   lastMsg["role"] as? String == "assistant",
                   lastMsg["reasoning_content"] != nil {
                    lastMsg["content"] = text
                    messages[messages.count - 1] = lastMsg
                } else {
                    messages.append(["role": "assistant", "content": text])
                }

            case .toolCall(let id, let name, let input):
                let argsStr = (try? JSONSerialization.jsonObject(with: input))
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let toolCallDict: [String: Any] = [
                    "id": id,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": argsStr,
                    ],
                ]
                // Merge consecutive tool_calls into the same assistant message.
                // Also merges with an assistant message that has reasoning_content
                // (from a preceding .thinking entry) but no tool_calls yet.
                if messages.last?["role"] as? String == "assistant" {
                    var lastMsg = messages.removeLast()
                    if var existingCalls = lastMsg["tool_calls"] as? [[String: Any]] {
                        existingCalls.append(toolCallDict)
                        lastMsg["tool_calls"] = existingCalls
                    } else {
                        lastMsg["tool_calls"] = [toolCallDict]
                    }
                    messages.append(lastMsg)
                } else {
                    messages.append([
                        "role": "assistant",
                        "tool_calls": [toolCallDict],
                    ])
                }

            case .toolOutput(let id, let output, _):
                messages.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "content": output,
                ])

            case .thinking(let text, _):
                // Add reasoning_content for models that require it in re-prompt
                // (e.g. deepseek-v4-pro in thinking mode). Merge with an existing
                // assistant message if possible, otherwise create a new one.
                if messages.last?["role"] as? String == "assistant" {
                    var lastMsg = messages.removeLast()
                    lastMsg["reasoning_content"] = text
                    messages.append(lastMsg)
                } else {
                    messages.append(["role": "assistant", "reasoning_content": text])
                }

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
