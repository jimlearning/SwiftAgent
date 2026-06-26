import Foundation

/// Web browser automation tool. Feature-gated behind WEB_BROWSER_TOOL.
/// CC: tools/WebBrowserTool/ — feature('WEB_BROWSER_TOOL').
public struct WebBrowserTool: Tool {
    public let name = "WebBrowser"
    public let description = "Browse and interact with web pages using a headless browser."

    public struct Arguments: Codable, Sendable {
        public var url: String
        public var action: String?

        enum CodingKeys: String, CodingKey {
            case url
            case action
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "url": JSONSchemaProperty(type: "string", description: "URL to navigate to"),
            "action": JSONSchemaProperty(type: "string", description: "Browser action: navigate, click, type, screenshot, extract"),
        ], required: ["url"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("WebBrowser tool requires ant-internal build.")
    }
}
