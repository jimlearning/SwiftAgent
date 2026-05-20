import Foundation

/// Monitor tool for streaming events. Feature-gated behind MONITOR_TOOL.
/// CC: tools/MonitorTool/ — feature('MONITOR_TOOL').
public struct MonitorTool: Tool {
    public init() {}
    public let name = "Monitor"
    public var searchHint: String? { "stream events from a background monitor" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Monitor and stream events from external sources." }
    public let isReadOnly = true
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Monitor action"),
        ], required: ["action"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "Monitor tool requires ant-internal build.", isError: true)
    }
}
