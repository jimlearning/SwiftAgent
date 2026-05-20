import Foundation

/// List UDS peers tool. Feature-gated behind UDS_INBOX.
/// CC: tools/ListPeersTool/ — feature('UDS_INBOX').
public struct ListPeersTool: Tool {
    public init() {}
    public let name = "ListPeers"
    public var searchHint: String? { "list connected peers via UDS inbox" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "List peers connected via Unix Domain Socket inbox." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "ListPeers tool requires ant-internal build.", isError: true)
    }
}
