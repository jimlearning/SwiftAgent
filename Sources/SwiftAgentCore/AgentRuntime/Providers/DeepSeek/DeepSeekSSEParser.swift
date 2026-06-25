import Foundation

/// Parses DeepSeek SSE (Server-Sent Events) for both compatibility modes
/// and emits SessionEvent values through a GenerationChannel.
///
/// Two parse modes:
/// - AnthropicCompat: Same event types as AnthropicSSEParser (content_block_delta,
///   content_block_start/stop, message_delta, message_stop, error).
/// - OpenAICompat: Chat Completions SSE chunks with content/reasoning_content deltas,
///   multi-chunk tool call accumulation, and finish_reason handling.
///
/// Snapshot semantics REQUIRED: accumulate text/thinking internally,
/// send FULL accumulated string each time (PITFALLS.md Pitfall 2).
actor DeepSeekSSEParser {

    // MARK: - Public Entry Point

    /// Parse SSE lines and emit SessionEvent values through the channel.
    /// Dispatches to the appropriate internal parser based on compatibility.
    func parse(
        lines: AsyncStream<String>,
        channel: GenerationChannel,
        compatibility: APICompatibility
    ) async throws {
        switch compatibility {
        case .anthropicCompatible:
            try await parseAnthropicCompat(lines: lines, channel: channel)
        case .openAICompatible:
            try await parseOpenAICompat(lines: lines, channel: channel)
        }
    }

    // MARK: - AnthropicCompat SSE Parsing

    /// Parse Anthropic-compatible SSE lines (same event types as AnthropicSSEParser).
    private func parseAnthropicCompat(
        lines: AsyncStream<String>,
        channel: GenerationChannel
    ) async throws {
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""
        var accumulator = AnthropicContentAccumulator()

        for await line in lines {
            if Task.isCancelled { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = json["index"] as? Int,
                      let block = json["content_block"] as? [String: Any] else { continue }
                let blockType = block["type"] as? String

                switch blockType {
                case "tool_use", "server_tool_use":
                    if let name = block["name"] as? String, let id = block["id"] as? String {
                        accumulator.recordToolCall(index: index, id: id, name: name)
                    }
                default:
                    break
                }

            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any] else { continue }
                let deltaType = delta["type"] as? String

                switch deltaType {
                case "text_delta":
                    if let text = delta["text"] as? String {
                        accumulatedText += text
                        await channel.send(textDelta: accumulatedText)
                    }
                case "thinking_delta":
                    if let thinking = delta["thinking"] as? String {
                        accumulatedThinking += thinking
                        await channel.send(thinkingDelta: accumulatedThinking)
                    }
                case "input_json_delta":
                    if let partialJSON = delta["partial_json"] as? String,
                       let index = json["index"] as? Int {
                        accumulator.accumulateToolInput(index: index, delta: partialJSON)
                    }
                default:
                    break
                }

            case "content_block_stop":
                guard let index = json["index"] as? Int else { continue }
                if let (id, name, parsedInput) = accumulator.finalizeToolCall(index: index) {
                    let inputData = try? JSONSerialization.data(withJSONObject: parsedInput)
                    await channel.send(toolCallRequest: id, name: name, input: inputData ?? Data())
                }

            case "message_delta":
                let stopReason = (json["delta"] as? [String: Any])?["stop_reason"] as? String
                let usage = (json["usage"] as? [String: Any]).map { AnthropicContentAccumulator.parseUsage($0) }
                await channel.complete(stopReason: stopReason, usage: usage)

            case "message_stop":
                break

            case "error":
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                await channel.fail(with: .serverError(statusCode: 0, body: msg))
                return

            default:
                break
            }
        }
    }

    // MARK: - OpenAICompat SSE Parsing

    /// Parse OpenAI-compatible Chat Completions SSE chunks.
    ///
    /// Handles:
    /// - content deltas -> textDelta snapshots
    /// - reasoning_content deltas -> thinkingDelta snapshots (R1 models)
    /// - multi-chunk tool call accumulation -> toolCallRequested events
    /// - finish_reason -> turnCompleted
    /// - [DONE] sentinel
    private func parseOpenAICompat(
        lines: AsyncStream<String>,
        channel: GenerationChannel
    ) async throws {
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""
        var toolAccumulator = OpenAIToolCallAccumulator()
        var usage: Usage?

        for await line in lines {
            if Task.isCancelled { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else { continue }

            let delta = firstChoice["delta"] as? [String: Any]
            let finishReason = firstChoice["finish_reason"] as? String

            // Text content delta
            if let content = delta?["content"] as? String, !content.isEmpty {
                accumulatedText += content
                await channel.send(textDelta: accumulatedText)
            }

            // Reasoning content delta (R1 model)
            if let reasoning = delta?["reasoning_content"] as? String, !reasoning.isEmpty {
                accumulatedThinking += reasoning
                await channel.send(thinkingDelta: accumulatedThinking)
            }

            // Tool call deltas (multi-chunk accumulation)
            if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    guard let index = tc["index"] as? Int else { continue }
                    let id = tc["id"] as? String
                    let function = tc["function"] as? [String: Any]
                    let name = function?["name"] as? String
                    let arguments = function?["arguments"] as? String
                    toolAccumulator.accumulate(index: index, id: id, name: name, arguments: arguments)
                }
            }

            // Usage (may appear in final chunk with stream_options.include_usage)
            if let usageDict = json["usage"] as? [String: Any] {
                usage = parseOpenAIUsage(usageDict)
            }

            // Finish reason — emit pending tool calls, then turn completed
            if let reason = finishReason {
                // Emit any accumulated tool calls
                let finalized = toolAccumulator.allFinalized()
                for (callID, callName, callInput) in finalized {
                    await channel.send(toolCallRequest: callID, name: callName, input: callInput)
                }

                let stopReason: String
                switch reason {
                case "stop":
                    stopReason = "end_turn"
                case "tool_calls":
                    stopReason = "tool_use"
                case "length":
                    stopReason = "max_tokens"
                default:
                    stopReason = reason
                }

                await channel.complete(stopReason: stopReason, usage: usage)
                return
            }
        }
    }

    // MARK: - OpenAI Usage Parsing

    /// Parse usage from an OpenAI Chat Completions usage dict.
    private func parseOpenAIUsage(_ dict: [String: Any]) -> Usage {
        Usage(
            inputTokens: dict["prompt_tokens"] as? Int ?? 0,
            outputTokens: dict["completion_tokens"] as? Int ?? 0
        )
    }
}

// MARK: - OpenAI Tool Call Accumulator

/// Accumulates tool call state across multiple SSE chunks in the OpenAI-compatible path.
///
/// Per-index accumulation: each chunk may carry function.name, function.arguments
/// fragments, or the tool call ID. When finish_reason is received, all completed
/// tool calls are finalized and emitted.
private struct OpenAIToolCallAccumulator {
    private var perIndex: [Int: (id: String, name: String, arguments: String)] = [:]

    mutating func accumulate(index: Int, id: String?, name: String?, arguments: String?) {
        var entry = perIndex[index] ?? ("", "", "")
        if let id { entry.0 = id }
        if let name { entry.1 = name }
        entry.2 += (arguments ?? "")
        perIndex[index] = entry
    }

    func allFinalized() -> [(id: String, name: String, input: Data)] {
        perIndex.keys.sorted().compactMap { finalize(index: $0) }
    }

    private func finalize(index: Int) -> (id: String, name: String, input: Data)? {
        guard let entry = perIndex[index], !entry.0.isEmpty, !entry.1.isEmpty else { return nil }
        let parsed = AnthropicContentAccumulator.safeParseJSON(entry.2)
        let input: [String: Any]
        if let dict = parsed as? [String: Any] {
            input = dict
        } else {
            input = [:]
        }
        let data = (try? JSONSerialization.data(withJSONObject: input)) ?? Data()
        return (entry.0, entry.1, data)
    }
}
