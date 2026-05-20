import Foundation

/// Subscribe to PR updates tool. Feature-gated behind KAIROS_GITHUB_WEBHOOKS.
/// CC: tools/SubscribePRTool/ — feature('KAIROS_GITHUB_WEBHOOKS').
public struct SubscribePRTool: Tool {
    public init() {}
    public let name = "SubscribePR"
    public var searchHint: String? { "subscribe to pull request updates" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Subscribe to GitHub pull request webhook notifications." }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "repo": JSONSchemaProperty(type: "string", description: "GitHub repository (owner/repo)"),
            "pr_number": JSONSchemaProperty(type: "number", description: "Pull request number"),
        ], required: ["repo", "pr_number"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "SubscribePR tool requires ant-internal build.", isError: true)
    }
}
