import Foundation

/// Parses OpenAI Chat Completions SSE (Server-Sent Events) and emits
/// GenerationChannel events.
///
/// Handles:
/// - `content` deltas → textDelta snapshots (accumulated)
/// - `reasoning_content` deltas → thinkingDelta snapshots (DeepSeek R1, o4)
/// - Multi-chunk tool call accumulation → toolCallRequest (at finish_reason)
/// - `finish_reason` → complete with stop reason
/// - `usage` from stream_options.include_usage chunks
/// - `[DONE]` sentinel
///
/// Snapshot semantics: accumulated text/thinking sent on each emission.
struct ChatCompletionsSSEParser: Sendable {

    /// Per-index accumulator for streaming tool call fragments.
    private struct ToolCallAccumulator {
        var id: String?
        var name: String?
        var argumentsBuffer: String = ""
    }

    func parse<S: AsyncSequence>(
        lines: S,
        channel: GenerationChannel
    ) async throws where S.Element == String {
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""
        var toolCallAccumulators: [Int: ToolCallAccumulator] = [:]
        var usage: Usage?

        for try await line in lines {
            if Task.isCancelled { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            guard let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else {
                // May be a usage-only chunk without choices
                if let usageDict = json["usage"] as? [String: Any] {
                    usage = parseUsage(usageDict)
                }
                continue
            }

            let delta = firstChoice["delta"] as? [String: Any]
            let finishReason = firstChoice["finish_reason"] as? String

            // Content delta
            if let content = delta?["content"] as? String, !content.isEmpty {
                accumulatedText += content
                await channel.send(textDelta: accumulatedText)
            }

            // Reasoning content delta (DeepSeek R1, o4)
            if let reasoning = delta?["reasoning_content"] as? String, !reasoning.isEmpty {
                accumulatedThinking += reasoning
                await channel.send(thinkingDelta: accumulatedThinking)
            }

            // Tool call deltas (multi-chunk accumulation)
            if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    guard let index = tc["index"] as? Int else { continue }
                    var acc = toolCallAccumulators[index] ?? ToolCallAccumulator()
                    if let id = tc["id"] as? String { acc.id = id }
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String { acc.name = name }
                        if let arguments = function["arguments"] as? String {
                            acc.argumentsBuffer += arguments
                        }
                    }
                    toolCallAccumulators[index] = acc
                }
            }

            // Usage (final chunk with stream_options.include_usage)
            if let usageDict = json["usage"] as? [String: Any] {
                usage = parseUsage(usageDict)
            }

            // Finish reason — emit pending tool calls, then complete
            if let reason = finishReason {
                for index in toolCallAccumulators.keys.sorted() {
                    guard let acc = toolCallAccumulators[index],
                          let id = acc.id,
                          let name = acc.name else { continue }
                    let parsed = safeParseJSON(acc.argumentsBuffer)
                    let input: [String: Any]
                    if let dict = parsed as? [String: Any] {
                        input = dict
                    } else {
                        input = [:]
                    }
                    let data = (try? JSONSerialization.data(withJSONObject: input)) ?? Data()
                    await channel.send(toolCallRequest: id, name: name, input: data)
                }
                toolCallAccumulators = [:]

                let stopReason = mapStopReason(reason)
                await channel.complete(stopReason: stopReason, usage: usage)
                return
            }
        }
    }

    // MARK: - Helpers

    private func parseUsage(_ dict: [String: Any]) -> Usage {
        Usage(
            inputTokens: dict["prompt_tokens"] as? Int ?? 0,
            outputTokens: dict["completion_tokens"] as? Int ?? 0
        )
    }

    private func mapStopReason(_ reason: String) -> String {
        switch reason {
        case "stop": return "end_turn"
        case "tool_calls": return "tool_use"
        case "length": return "max_tokens"
        default: return reason
        }
    }

    /// Best-effort JSON parsing that handles double-stringified JSON.
    private func safeParseJSON(_ input: String) -> Any? {
        guard let data = input.data(using: .utf8) else { return nil }
        if let parsed = try? JSONSerialization.jsonObject(with: data) { return parsed }
        // Try unescaping double-stringified JSON
        if let unescaped = input.unescapedJSON,
           let unescapedData = unescaped.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: unescapedData) {
            return parsed
        }
        return nil
    }
}

private extension String {
    /// Attempt to unescape a JSON string that has been double-encoded.
    var unescapedJSON: String? {
        guard let data = "\"\(self)\"".data(using: .utf8),
              let unescaped = try? JSONSerialization.jsonObject(with: data) as? String else {
            return nil
        }
        return unescaped
    }
}
