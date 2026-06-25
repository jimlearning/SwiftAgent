import Foundation

/// Translates RuntimeToolDefinition values into OpenAI function-calling format.
/// Pure-functional: no mutable state, no side effects.
///
/// OpenAI function-calling format: each tool is a dict with keys
/// `type: "function"` and `function: { name, description, parameters }`.
/// Uses Codable round-trip through JSONEncoder for nested schema support.
struct OpenAIToolTranslator: Sendable {

    /// Convert an array of RuntimeToolDefinition to OpenAI function-calling format.
    ///
    /// Each output dict has: `type`, `function.name`, `function.description`,
    /// `function.parameters`, and `function.strict`.
    ///
    /// - Parameter tools: The tool definitions to translate.
    /// - Returns: An array of dicts in OpenAI function-calling format.
    static func translate(_ tools: [RuntimeToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var function: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]

            // Map JSONSchema to OpenAI parameters format via Codable round-trip.
            // This handles nested schemas, enum values, array items, etc.
            if let data = try? JSONEncoder().encode(tool.inputSchema),
               let schemaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                var params: [String: Any] = [:]
                for (key, value) in schemaDict {
                    // Flatten to OpenAI-compatible parameter keys.
                    // JSONSchema uses snake_case internally but Codable+CodingKeys
                    // maps to camelCase, so we need the actual encoded keys.
                    params[key] = value
                }

                // Ensure required fields exist
                if params["type"] == nil {
                    params["type"] = "object"
                }

                function["parameters"] = params
            } else {
                function["parameters"] = ["type": "object"]
            }

            // OpenAI strict mode for models that support it
            function["strict"] = true

            return [
                "type": "function",
                "function": function,
            ]
        }
    }
}
