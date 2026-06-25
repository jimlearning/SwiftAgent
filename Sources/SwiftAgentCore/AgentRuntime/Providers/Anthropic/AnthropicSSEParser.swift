import Foundation

/// Parses Anthropic SSE (Server-Sent Events) from the Messages API streaming endpoint
/// and emits SessionEvent values through a GenerationChannel.
///
/// Extracted from LLMStreamParser + LLMClient.streamRequest(), adapted for
/// snapshot-semantic SessionEvent output through GenerationChannel.
///
/// Key design: maintains internal accumulators for text and thinking so that
/// every emission carries the COMPLETE accumulated value (snapshot semantics,
/// not raw deltas — PITFALLS.md Pitfall 2).
struct AnthropicSSEParser: Sendable {

    // MARK: - Parsing

    /// Consume an async stream of SSE lines, parse events, and emit through the channel.
    ///
    /// - Parameters:
    ///   - lines: An AsyncStream of SSE data lines.
    ///   - channel: The GenerationChannel to emit SessionEvent values through.
    func parse(
        lines: AsyncStream<String>,
        channel: GenerationChannel
    ) async throws {
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""
        var accumulator = AnthropicContentAccumulator()
        var receivedMessageDelta = false
        var lastEventTime = ContinuousClock.now

        for await line in lines {
            if Task.isCancelled { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            // Handle [DONE] sentinel
            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            lastEventTime = ContinuousClock.now

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
                receivedMessageDelta = true
                await channel.complete(stopReason: stopReason, usage: usage)

            case "message_stop":
                break // Stream ends naturally

            case "error":
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                await channel.fail(with: .serverError(statusCode: 0, body: msg))
                return

            default:
                break // Unknown types silently ignored (defense in depth)
            }
        }
    }
}
