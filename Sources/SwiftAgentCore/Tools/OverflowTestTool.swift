import Foundation

/// Overflow test tool for testing context overflow handling. Feature-gated.
/// CC: tools/OverflowTestTool/ — feature('OVERFLOW_TEST_TOOL').
public struct OverflowTestTool: Tool {
    public init() {}
    public let name = "OverflowTest"
    public var searchHint: String? { "generate large outputs for testing" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Generate large output for testing context overflow handling." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "size_kb": JSONSchemaProperty(type: "number", description: "Size of output in KB"),
        ], required: ["size_kb"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "OverflowTest tool requires ant-internal build.", isError: true)
    }
}
