import Foundation

/// Translates SessionToolDefinition values into OpenAI wire formats for both
/// Responses API and Chat Completions.
/// Pure-functional: no mutable state, no side effects.
///
/// Responses API tool format (same struct, explicit naming):
/// → [{type: "function", function: {name, description, parameters}}]
///
/// Chat Completions tool format (identical structure, legacy naming):
/// → [{type: "function", function: {name, description, parameters}}]
struct OpenAIToolTranslator: Sendable {

    /// Convert SessionToolDefinition to Responses API tool format.
    /// Responses API uses the same function-calling struct as Chat Completions,
    /// but named explicitly for forward compatibility (additional tool types like
    /// `computer_use`, `web_search`, `file_search` are Responses API-only).
    static func translateResponses(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        tools.map(buildFunctionTool)
    }

    /// Convert SessionToolDefinition to Chat Completions function-calling format (legacy).
    static func translateChatCompletions(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
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

    // MARK: - Deprecated

    @available(*, deprecated, renamed: "translateChatCompletions")
    static func translate(_ tools: [SessionToolDefinition], enableStrictMode: Bool = false) -> [[String: Any]] {
        translateChatCompletions(tools)
    }
}
