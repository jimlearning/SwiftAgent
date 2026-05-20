import Foundation

/// Terminal capture tool. Feature-gated behind TERMINAL_PANEL.
/// CC: tools/TerminalCaptureTool/ — feature('TERMINAL_PANEL').
public struct TerminalCaptureTool: Tool {
    public init() {}
    public let name = "TerminalCapture"
    public var searchHint: String? { "capture terminal output" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Capture terminal output from the current session." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Capture action: screenshot or text"),
        ], required: ["action"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "TerminalCapture tool requires ant-internal build.", isError: true)
    }
}
