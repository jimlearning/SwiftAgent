import Foundation

/// Web browser automation tool. Feature-gated behind WEB_BROWSER_TOOL.
/// CC: tools/WebBrowserTool/ — feature('WEB_BROWSER_TOOL').
public struct WebBrowserTool: Tool {
    public init() {}
    public let name = "WebBrowser"
    public var searchHint: String? { "browse web pages in a headless browser" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Browse and interact with web pages using a headless browser." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "url": JSONSchemaProperty(type: "string", description: "URL to navigate to"),
            "action": JSONSchemaProperty(type: "string", description: "Browser action: navigate, click, type, screenshot, extract"),
        ], required: ["url"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "WebBrowser tool requires ant-internal build.", isError: true)
    }
}
