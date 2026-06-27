import Foundation

/// Parses OpenAI Responses API SSE events and emits GenerationChannel calls.
///
/// Unlike Chat Completions (single `data:` lines with chunk JSON), the Responses
/// API uses structured event pairs:
///
/// ```
/// event: response.output_text.delta
/// data: {"type": "...", "delta": "...", ...}
/// ```
///
/// Events handled:
/// - `response.output_text.delta` → textDelta snapshot
/// - `response.reasoning.delta` → thinkingDelta snapshot
/// - `response.function_call_arguments.delta` → tool input accumulation
/// - `response.output_item.done` (function_call) → toolCallRequested
/// - `response.completed` → turnCompleted with usage
/// - `response.failed` → error
struct ResponsesSSEParser: Sendable {

    /// Parse a stream of SSE lines into GenerationChannel events.
    /// All mutable state is local to this method.
    func parse<S: AsyncSequence>(
        lines: S,
        channel: GenerationChannel
    ) async throws where S.Element == String {
        var currentEvent: String = ""
        var accumulatedToolInputs: [String: String] = [:]
        var accumulatedText: String = ""
        var accumulatedThinking: String = ""

        for try await line in lines {
            if Task.isCancelled { break }

            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            switch currentEvent {
            case "response.output_text.delta":
                if let delta = json["delta"] as? String {
                    accumulatedText += delta
                    await channel.send(textDelta: accumulatedText)
                }

            case "response.reasoning.delta":
                if let delta = json["delta"] as? String {
                    accumulatedThinking += delta
                    await channel.send(thinkingDelta: accumulatedThinking)
                }

            case "response.function_call_arguments.delta":
                if let itemID = json["item_id"] as? String,
                   let delta = json["delta"] as? String {
                    accumulatedToolInputs[itemID, default: ""] += delta
                }

            case "response.output_item.done":
                guard let item = json["item"] as? [String: Any],
                      let itemType = item["type"] as? String else { continue }

                if itemType == "function_call",
                   let id = item["id"] as? String,
                   let name = item["name"] as? String {
                    var inputStr = accumulatedToolInputs[id] ?? ""
                    if inputStr.isEmpty, let args = item["arguments"] as? String {
                        inputStr = args
                    }
                    let parsedInput = (try? JSONSerialization.jsonObject(with: Data(inputStr.utf8)))
                        .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) } ?? Data(inputStr.utf8)
                    accumulatedToolInputs.removeValue(forKey: id)
                    await channel.send(toolCallRequest: id, name: name, input: parsedInput)
                }

            case "response.completed":
                if let resp = json["response"] as? [String: Any] {
                    let status = resp["status"] as? String
                    let usage = (resp["usage"] as? [String: Any]).map { parseUsage($0) }
                    let stopReason: String?
                    switch status {
                    case "completed": stopReason = "end_turn"
                    case "incomplete": stopReason = "max_tokens"
                    default: stopReason = status
                    }
                    await channel.complete(stopReason: stopReason, usage: usage)
                } else {
                    await channel.complete(stopReason: nil, usage: nil)
                }
                return  // Stream ends after completion

            case "response.failed":
                let errMsg = (json["response"] as? [String: Any])?["error"] as? [String: Any]
                let msg = errMsg?["message"] as? String ?? "Responses API error"
                await channel.fail(with: .serverError(statusCode: 0, body: msg))
                return

            default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func parseUsage(_ dict: [String: Any]) -> Usage {
        Usage(
            inputTokens: dict["input_tokens"] as? Int
                ?? (dict["prompt_tokens"] as? Int)
                ?? 0,
            outputTokens: dict["output_tokens"] as? Int
                ?? (dict["completion_tokens"] as? Int)
                ?? 0
        )
    }
}
