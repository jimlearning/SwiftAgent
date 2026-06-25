import Foundation

/// Accumulates content block state during SSE streaming, handling per-index
/// tool input JSON accumulation and double-stringified JSON unwrapping.
///
/// Extracted verbatim from LLMStreamParser.ContentBlockAccumulator (PITFALLS.md Pitfall 7:
/// "Preserve battle-tested internals"). The accumulator handles:
/// - Double-stringified JSON via safeParseJSON (recursive unwrapping)
/// - Mid-stream truncation (partial JSON that never completes — no crash)
/// - Per-index input_json_delta accumulation
///
/// Adapted OUTPUT: instead of producing `[ContentBlock]`, provides
/// `recordToolCall` + `finalizeToolCall` methods consumed by AnthropicSSEParser.
struct AnthropicContentAccumulator: Sendable {

    private var partialJSON: [Int: [String]] = [:]
    private var toolNames: [Int: String] = [:]
    private var toolIDs: [Int: String] = [:]

    init() {}

    // MARK: - Tool Call Registration

    /// Register a tool use block at the given content block index.
    mutating func recordToolCall(index: Int, id: String, name: String) {
        toolIDs[index] = id
        toolNames[index] = name
        partialJSON[index] = []
    }

    /// Accumulate a partial_json delta for the tool at the given index.
    mutating func accumulateToolInput(index: Int, delta: String) {
        partialJSON[index, default: []].append(delta)
    }

    /// Finalize a tool call at the given index. Returns (id, name, parsedInput) or nil
    /// if the tool was never registered or the input couldn't be parsed.
    func finalizeToolCall(index: Int) -> (id: String, name: String, input: [String: Any])? {
        guard let id = toolIDs[index], let name = toolNames[index] else { return nil }

        let combined = partialJSON[index]?.joined() ?? ""
        // If we have no accumulated JSON, return a best-effort empty input
        // rather than nil — the tool was registered but may have no parameters.
        let parsed = Self.safeParseJSON(combined)
        let input: [String: Any]
        if let dict = parsed as? [String: Any] {
            input = dict
        } else if let str = parsed as? String, !str.isEmpty {
            input = ["value": str]
        } else {
            input = [:]
        }

        return (id, name, input)
    }

    // MARK: - Static Utilities

    /// Recursively parse a JSON string, handling the API's double-stringified JSON behavior.
    /// Extracted verbatim from LLMStreamParser.safeParseJSON.
    ///
    /// CC's safeParseJSON handles cases where the API wraps tool input JSON in extra
    /// string layers (e.g., `"\"{}\""` → `{}`).
    public static func safeParseJSON(_ input: String) -> Any? {
        guard let data = input.data(using: .utf8) else { return nil }

        // Try to parse as JSON. Use .fragmentsAllowed so top-level strings
        // (the double-stringified case) are parseable. The original
        // LLMStreamParser.safeParseJSON omits this option, causing
        // double-stringified JSON to always fall through un-unwrapped.
        guard let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            // Not valid JSON — return the original string
            return input
        }

        // If the result is itself a JSON string, recurse (handles double-stringified JSON)
        if let str = result as? String, str != input {
            return safeParseJSON(str)
        }

        return result
    }

    /// Parse a usage dictionary from the API, including cache token fields.
    /// Extracted verbatim from LLMStreamParser.parseUsage.
    public static func parseUsage(_ dict: [String: Any]) -> Usage {
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
}
