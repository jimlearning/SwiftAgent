import Foundation

/// Context inspection tool. Feature-gated behind CONTEXT_COLLAPSE.
/// CC: tools/CtxInspectTool/ — feature('CONTEXT_COLLAPSE').
public struct CtxInspectTool: Tool {
    public init() {}
    public let name = "CtxInspect"
    public var searchHint: String? { "inspect context collapse state" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Inspect the context collapse and compaction state." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "CtxInspect tool requires ant-internal build.", isError: true)
    }
}
