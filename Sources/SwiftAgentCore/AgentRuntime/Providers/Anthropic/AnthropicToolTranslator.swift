import Foundation

/// Translates SessionToolDefinition values into Anthropic-format tool JSON.
/// Pure-functional: no mutable state, no side effects.
///
/// Uses Codable round-trip through JSONEncoder for nested schema support,
/// matching the existing ToolDefinition.apiFormatted pattern.
struct AnthropicToolTranslator: Sendable {

    /// Convert an array of SessionToolDefinition to Anthropic-format tool dicts.
    ///
    /// Each output dict has keys: `name`, `description`, `input_schema`.
    /// The `input_schema` maps JSONSchema fields recursively via Codable round-trip.
    static func translate(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var dict: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]
            // Use Codable round-trip to handle nested schemas (same pattern as
            // ToolDefinition.apiFormatted in LLMClient.swift)
            if let data = try? JSONEncoder().encode(tool.parameters),
               let schemaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict["input_schema"] = schemaDict
            } else {
                dict["input_schema"] = ["type": "object"]
            }
            return dict
        }
    }
}
