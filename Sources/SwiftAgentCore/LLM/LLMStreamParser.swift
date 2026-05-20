import Foundation

/// Parses SSE (Server-Sent Events) data from Anthropic's streaming Messages API.
/// Includes recursive JSON parsing for API double-stringified JSON behavior
/// and tool input normalization during parsing.
public struct LLMStreamParser: Sendable {
    public init() {}

    /// Parse a usage dictionary from the API, including cache token fields.
    /// Matches CC's usage parsing which captures cache_creation_input_tokens
    /// and cache_read_input_tokens in addition to input/output tokens.
    private func parseUsage(_ dict: [String: Any]) -> Usage {
        Usage(
            inputTokens: dict["input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: dict["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadInputTokens: dict["cache_read_input_tokens"] as? Int ?? 0,
            cacheDeletedInputTokens: dict["cache_deleted_input_tokens"] as? Int ?? 0,
            outputTokens: dict["output_tokens"] as? Int ?? 0,
            serverToolUse: (dict["server_tool_use"] as? [String: Any]).map { s in
                Usage.ServerToolUse(
                    webSearchRequests: s["web_search_requests"] as? Int ?? 0,
                    webFetchRequests: s["web_fetch_requests"] as? Int ?? 0
                )
            },
            serviceTier: dict["service_tier"] as? String,
            cacheCreation: (dict["cache_creation"] as? [String: Any]).map { c in
                Usage.CacheCreation(
                    ephemeral1hInputTokens: c["ephemeral_1h_input_tokens"] as? Int ?? 0,
                    ephemeral5mInputTokens: c["ephemeral_5m_input_tokens"] as? Int ?? 0
                )
            },
            inferenceGeo: dict["inference_geo"] as? String,
            iterations: (dict["iterations"] as? [[String: Any]]).map { arr in
                arr.map { Usage.UsageIteration(
                    inputTokens: $0["input_tokens"] as? Int ?? 0,
                    outputTokens: $0["output_tokens"] as? Int ?? 0
                )}
            },
            speed: dict["speed"] as? String,
            costUSD: dict["cost_usd"] as? Double,
            contextWindow: dict["context_window"] as? Int,
            maxOutputTokens: dict["max_output_tokens"] as? Int
        )
    }

    public func parse(data: Data) -> StreamEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .error("Failed to parse SSE data")
        }

        switch type {
        case "message_start":
            guard let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let id = message["id"] as? String else { return .error("Malformed message_start") }
            let usage = (message["usage"] as? [String: Any]).map(parseUsage)
            return .messageStart(message: StreamMessageStart(model: model, messageID: id, usage: usage))

        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any] else { return .error("Malformed content_block_start") }

            if block["type"] as? String == "tool_use",
               let name = block["name"] as? String,
               let id = block["id"] as? String {
                return .contentBlockStart(index: index, block: .toolUse(name: name, id: id))
            }
            if block["type"] as? String == "server_tool_use",
               let name = block["name"] as? String,
               let id = block["id"] as? String {
                return .contentBlockStart(index: index, block: .serverToolUse(name: name, id: id))
            }
            if block["type"] as? String == "thinking" {
                return .contentBlockStart(index: index, block: .thinking)
            }
            return .contentBlockStart(index: index, block: .text)

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return nil }

            if let text = delta["text"] as? String {
                return .textDelta(text: text)
            }
            if let thinking = delta["thinking"] as? String {
                return .thinkingDelta(text: thinking)
            }
            if let signature = delta["signature"] as? String {
                return .signatureDelta(text: signature)
            }
            if let partialJSON = delta["partial_json"] as? String {
                return .inputJSONDelta(delta: partialJSON)
            }
            return nil

        case "content_block_stop":
            guard let index = json["index"] as? Int else { return nil }
            return .contentBlockStop(index: index)

        case "message_delta":
            let stopReason = json["delta"] as? [String: Any]
            let usage = (json["usage"] as? [String: Any]).map(parseUsage)
            return .messageDelta(stopReason: stopReason?["stop_reason"] as? String, usage: usage)

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            return .error(msg)

        default:
            return nil
        }
    }
}

// MARK: - Recursive JSON Parsing

/// Recursively parse a JSON string, handling the API's double-stringified JSON behavior.
/// CC's safeParseJSON handles cases where the API wraps tool input JSON in extra
/// string layers (e.g., `"\"{}\""` → `{}`).
///
/// Returns a fully parsed value, recursing through nested JSON strings.
public func safeParseJSON(_ input: String) -> Any? {
    guard let data = input.data(using: .utf8) else { return nil }

    // Try to parse as JSON
    guard let result = try? JSONSerialization.jsonObject(with: data) else {
        // Not valid JSON — return the original string
        return input
    }

    // If the result is itself a JSON string, recurse (handles double-stringified JSON)
    if let str = result as? String, str != input {
        return safeParseJSON(str)
    }

    return result
}

/// Parse accumulated tool input JSON chunks into a [String: JSONValue] dictionary.
/// Handles the API's streaming partial_json accumulation and recursive parsing.
///
/// CC accumulates partial_json chunks for each tool_use block by index,
/// then calls safeParseJSON after content_block_stop to get the final input.
public func accumulateToolInput(from deltas: [String]) -> [String: JSONValue] {
    let combined = deltas.joined()
    guard !combined.isEmpty else { return [:] }

    // Parse through safeParseJSON to handle double-stringified JSON
    let parsed = safeParseJSON(combined)

    switch parsed {
    case let dict as [String: Any]:
        return convertToJSONValue(dict)
    case let str as String:
        // Single string value — wrap in a default key
        return ["value": .string(str)]
    default:
        return [:]
    }
}

/// Convert a [String: Any] dictionary to [String: JSONValue].
private func convertToJSONValue(_ dict: [String: Any]) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    for (key, value) in dict {
        result[key] = JSONValue.fromAny(value)
    }
    return result
}

/// Accumulate content blocks from stream events into a proper ContentBlock array.
/// Handles the SDK's behavior where tool_use input is streamed via partial_json
/// and needs to be accumulated and parsed at content_block_stop.
///
/// Matches CC's content block state tracking with index-based accumulation.
public struct ContentBlockAccumulator: Sendable {
    private var partialJSON: [Int: [String]] = [:]
    private var toolNames: [Int: String] = [:]
    private var toolIDs: [Int: String] = [:]
    private var textBlocks: [Int: String] = [:]
    private var thinkingBlocks: [Int: (text: String, signature: String?)] = [:]
    private var blockOrder: [Int] = []
    private var blockTypes: [Int: ContentBlockType] = [:]

    private enum ContentBlockType {
        case text
        case thinking
        case toolUse
        case serverToolUse
    }

    public init() {}

    /// Feed a stream event into the accumulator.
    public mutating func feed(_ event: StreamEvent) {
        switch event {
        case .contentBlockStart(let index, let block):
            blockOrder.append(index)
            switch block {
            case .text:
                blockTypes[index] = .text
                textBlocks[index] = ""
            case .thinking:
                blockTypes[index] = .thinking
                thinkingBlocks[index] = ("", nil)
            case .toolUse(let name, let id):
                blockTypes[index] = .toolUse
                toolNames[index] = name
                toolIDs[index] = id
                partialJSON[index] = []
            case .serverToolUse(let name, let id):
                blockTypes[index] = .serverToolUse
                toolNames[index] = name
                toolIDs[index] = id
                partialJSON[index] = []
            case .redactedThinking:
                blockTypes[index] = .thinking
                thinkingBlocks[index] = ("[redacted]", nil)
            }

        case .textDelta(let text):
            // Find the current text block (last text block without an index match
            // will be the one being streamed)
            for idx in blockOrder.reversed() where blockTypes[idx] == .text {
                textBlocks[idx, default: ""] += text
                break
            }

        case .thinkingDelta(let text):
            for idx in blockOrder.reversed() where blockTypes[idx] == .thinking {
                var current = thinkingBlocks[idx] ?? ("", nil)
                current.text += text
                thinkingBlocks[idx] = current
                break
            }

        case .signatureDelta(let sig):
            for idx in blockOrder.reversed() where blockTypes[idx] == .thinking {
                var current = thinkingBlocks[idx] ?? ("", nil)
                current.signature = (current.signature ?? "") + sig
                thinkingBlocks[idx] = current
                break
            }

        case .inputJSONDelta(let delta):
            for idx in blockOrder.reversed() where blockTypes[idx] == .toolUse || blockTypes[idx] == .serverToolUse {
                partialJSON[idx, default: []].append(delta)
                break
            }

        default:
            break
        }
    }

    /// Build the accumulated content blocks after stream completion.
    public func build() -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        for idx in blockOrder {
            switch blockTypes[idx] {
            case .text:
                let text = textBlocks[idx] ?? ""
                if !text.isEmpty {
                    blocks.append(.text(text))
                }
            case .thinking:
                if let (text, signature) = thinkingBlocks[idx] {
                    blocks.append(.thinking(text, signature: signature))
                }
            case .toolUse:
                if let name = toolNames[idx], let id = toolIDs[idx] {
                    let input = accumulateToolInput(from: partialJSON[idx] ?? [])
                    blocks.append(.toolUse(id: id, name: name, input: .object(input)))
                }
            case .serverToolUse:
                if let name = toolNames[idx], let id = toolIDs[idx] {
                    let input = accumulateToolInput(from: partialJSON[idx] ?? [])
                    blocks.append(.serverToolUse(id: id, name: name, input: .object(input)))
                }
            case .none:
                break
            }
        }
        return blocks
    }

    /// Retrieve a completed tool block at the given index, for streaming tool execution.
    /// Called from the streaming loop when content_block_stop fires, so tools can
    /// start executing while the model continues streaming. Matches CC's pattern
    /// of capturing tool_use blocks at content_block_stop and immediately queuing execution.
    public func completedToolBlock(at index: Int) -> (id: String, name: String, input: JSONValue)? {
        guard let type = blockTypes[index],
              (type == .toolUse || type == .serverToolUse),
              let name = toolNames[index],
              let id = toolIDs[index] else {
            return nil
        }
        let input = accumulateToolInput(from: partialJSON[index] ?? [])
        return (id: id, name: name, input: .object(input))
    }
}

