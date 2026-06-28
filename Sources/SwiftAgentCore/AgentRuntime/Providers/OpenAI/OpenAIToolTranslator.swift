import Foundation

/// Translates SessionToolDefinition values into OpenAI Responses API tool format.
/// Pure-functional: no mutable state, no side effects.
///
/// Output: [{type: "function", function: {name, description, parameters}}]
struct OpenAIToolTranslator: Sendable {

    /// Convert SessionToolDefinition to Chat Completions tool format.
    /// The tool shape is identical to Responses API (both use `type: "function"`).
    static func translateChatCompletions(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map(buildFunctionTool)
    }

    /// Convert SessionToolDefinition to Responses API tool format.
    static func translateResponses(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map(buildFunctionTool)
    }

    /// Build a single function tool dictionary from a tool definition.
    private static func buildFunctionTool(_ tool: SessionToolDefinition) -> [String: Any] {
        var function: [String: Any] = [
            "name": tool.name,
            "description": tool.description,
        ]

        if let data = try? JSONEncoder().encode(tool.parameters),
           let schemaDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var params: [String: Any] = [:]
            for (key, value) in schemaDict {
                params[key] = value
            }
            if params["type"] == nil {
                params["type"] = "object"
            }
            function["parameters"] = params
        } else {
            function["parameters"] = ["type": "object"]
        }

        return [
            "type": "function",
            "function": function,
        ]
    }

}
