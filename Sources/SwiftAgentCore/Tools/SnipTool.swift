import Foundation

/// Conversation history snipping tool. Feature-gated behind HISTORY_SNIP.
/// CC: tools/SnipTool/ — feature('HISTORY_SNIP').
public struct SnipTool: Tool {
    public init() {}
    public let name = "Snip"
    public var searchHint: String? { "snip conversation history to manage context" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Remove or archive portions of conversation history." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "range": JSONSchemaProperty(type: "string", description: "Range of messages to snip"),
        ], required: ["range"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "Snip tool requires ant-internal build.", isError: true)
    }
}
