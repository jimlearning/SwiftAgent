import Foundation

/// Parses OpenAI Chat Completions SSE (Server-Sent Events) and emits SessionEvent
/// values through a GenerationChannel.
///
/// Handles:
/// - Content deltas → textDelta snapshots (accumulated, not incremental)
/// - Reasoning_content deltas → thinkingDelta snapshots (o4 models)
/// - Multi-chunk tool call accumulation → toolCallRequested events (PITFALLS.md Pitfall 4)
/// - finish_reason → turnCompleted with stop reason mapping
/// - Usage extraction from stream_options.include_usage chunks
/// - [DONE] sentinel handling
///
/// Snapshot semantics REQUIRED: accumulatedText and accumulatedThinking are
/// full strings sent each emission, preventing the double-render bug.
///
/// This is the post-migration provider. Only SessionEvent and provider-internal
/// types may appear in this file or anywhere in the Providers/OpenAI/ directory.
actor OpenAISSEParser {

    // MARK: - Tool Call Accumulation

    /// Per-index accumulator for streaming tool call fragments.
    /// OpenAI streams tool calls across multiple chunks: first chunk has
    /// `function.name` and `id`, subsequent chunks carry `function.arguments`
    /// fragments. We accumulate per-index and emit when finish_reason is received.
    private struct ToolCallAccumulator {
        var id: String?
        var name: String?
        var argumentsBuffer: String = ""
    }

    private var toolCallAccumulators: [Int: ToolCallAccumulator] = [:]

    // MARK: - Public Entry Point

    /// Consume an async stream of SSE lines, parse events, and emit through the channel.
    ///
    /// - Parameters:
    ///   - lines: An AsyncStream of SSE data lines (from URLSession.AsyncBytes.lines).
    ///   - channel: The GenerationChannel to emit SessionEvent values through.
    func parse(
        lines: AsyncStream<String>,
        channel: GenerationChannel
    ) async throws {
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""
        var usage: Usage?

        for await line in lines {
            if Task.isCancelled { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            // Handle [DONE] sentinel
            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Malformed JSON — silently skip (defense in depth, T-03-12)
                continue
            }

            let choices = json["choices"] as? [[String: Any]]
            let firstChoice = choices?.first

            let delta = firstChoice?["delta"] as? [String: Any]
            let finishReason = firstChoice?["finish_reason"] as? String

            // --- Content delta ---
            if let content = delta?["content"] as? String, !content.isEmpty {
                accumulatedText += content
                await channel.send(textDelta: accumulatedText)
            }

            // --- Reasoning content delta (o4 models) ---
            if let reasoning = delta?["reasoning_content"] as? String, !reasoning.isEmpty {
                accumulatedThinking += reasoning
                await channel.send(thinkingDelta: accumulatedThinking)
            }

            // --- Tool call deltas (multi-chunk accumulation) ---
            if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    guard let index = tc["index"] as? Int else { continue }

                    var acc = toolCallAccumulators[index] ?? ToolCallAccumulator()

                    if let id = tc["id"] as? String {
                        acc.id = id
                    }

                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String {
                            acc.name = name
                        }
                        if let arguments = function["arguments"] as? String {
                            acc.argumentsBuffer += arguments
                        }
                    }

                    toolCallAccumulators[index] = acc
                }
            }

            // --- Usage (may appear in final chunk with stream_options.include_usage) ---
            if let usageDict = json["usage"] as? [String: Any] {
                usage = parseUsage(usageDict)
            }

            // --- Finish reason ---
            if let reason = finishReason {
                // Emit pending tool calls before completing the turn
                let finalized = finalizeAllToolCalls()
                for (callID, callName, callInput) in finalized {
                    await channel.send(toolCallRequest: callID, name: callName, input: callInput)
                }

                let stopReason = mapStopReason(reason)
                await channel.complete(stopReason: stopReason, usage: usage)
                return
            }
        }
    }

    // MARK: - Tool Call Finalization

    /// Finalize all accumulated tool calls. Each complete call (with id and name)
    /// is JSON-validated; malformed arguments still emitted as best-effort.
    private func finalizeAllToolCalls() -> [(id: String, name: String, input: Data)] {
        let indices = toolCallAccumulators.keys.sorted()
        var results: [(id: String, name: String, input: Data)] = []

        for index in indices {
            guard let acc = toolCallAccumulators[index],
                  let id = acc.id,
                  let name = acc.name else {
                continue
            }

            let argsData = acc.argumentsBuffer.data(using: .utf8) ?? Data()

            // Validate arguments JSON (T-03-13: malformed inputs at finish_reason still emitted)
            if let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
               let encoded = try? JSONSerialization.data(withJSONObject: parsed) {
                results.append((id, name, encoded))
            } else {
                // Emit raw arguments string as best-effort
                results.append((id, name, argsData))
            }
        }

        return results
    }

    // MARK: - Usage Parsing

    /// Parse usage from an OpenAI Chat Completions usage dict.
    private func parseUsage(_ dict: [String: Any]) -> Usage {
        Usage(
            inputTokens: dict["prompt_tokens"] as? Int ?? 0,
            outputTokens: dict["completion_tokens"] as? Int ?? 0
        )
    }

    // MARK: - Stop Reason Mapping

    /// Map OpenAI finish_reason strings to AgentRuntime stop reasons.
    private func mapStopReason(_ reason: String) -> String {
        switch reason {
        case "stop": return "end_turn"
        case "tool_calls": return "tool_use"
        case "length": return "max_tokens"
        default: return reason
        }
    }
}
