import Foundation

/// Translates SessionToolDefinition values into DeepSeek wire format
/// for both Anthropic-compatible and OpenAI-compatible endpoints.
/// Pure-functional: no mutable state, no side effects.
struct DeepSeekToolTranslator: Sendable {

    /// Convert SessionToolDefinition array to Anthropic-format tool dicts
    /// (identical to AnthropicToolTranslator pattern).
    static func translateAnthropicCompat(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var dict: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]
            if let data = try? JSONEncoder().encode(tool.inputSchema),
               let schemaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict["input_schema"] = schemaDict
            } else {
                dict["input_schema"] = ["type": "object"]
            }
            return dict
        }
    }

    /// Convert SessionToolDefinition array to OpenAI function-calling format.
    ///
    /// Output format: [{type: "function", function: {name, description, parameters: <JSONSchema>}}]
    /// parameters maps JSONSchema fields directly — no $schema, no items at top level.
    static func translateOpenAICompat(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var parameters: [String: Any] = ["type": "object"]
            if let data = try? JSONEncoder().encode(tool.inputSchema),
               let schemaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Copy relevant schema fields to parameters
                parameters["type"] = schemaDict["type"] as? String ?? "object"
                if let props = schemaDict["properties"] {
                    parameters["properties"] = props
                }
                if let required = schemaDict["required"] {
                    parameters["required"] = required
                }
                if let additional = schemaDict["additionalProperties"] {
                    parameters["additionalProperties"] = additional
                }
                if let desc = schemaDict["description"] {
                    parameters["description"] = desc
                }
            }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters,
                ],
            ]
        }
    }
}
