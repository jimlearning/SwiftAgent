import Foundation

/// Background PR suggestion tool. Ant-internal only.
/// CC: tools/SuggestBackgroundPRTool/ — process.env.USER_TYPE === 'ant'.
public struct SuggestBackgroundPRTool: Tool {
    public init() {}
    public let name = "SuggestBackgroundPR"
    public var searchHint: String? { "suggest PR changes in the background" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Suggest pull request changes asynchronously in the background." }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "repo": JSONSchemaProperty(type: "string", description: "GitHub repository (owner/repo)"),
            "branch": JSONSchemaProperty(type: "string", description: "Source branch name"),
        ], required: ["repo"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "SuggestBackgroundPR tool requires ant-internal build.", isError: true)
    }
}
