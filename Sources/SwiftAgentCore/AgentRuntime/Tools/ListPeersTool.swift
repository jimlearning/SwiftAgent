import Foundation

/// List UDS peers tool. Feature-gated behind UDS_INBOX.
/// CC: tools/ListPeersTool/ — feature('UDS_INBOX').
public struct ListPeersTool: Tool {
    public let name = "ListPeers"
    public let description = "List peers connected via Unix Domain Socket inbox."

    public struct Arguments: Codable, Sendable {}

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("ListPeers tool requires ant-internal build.")
    }
}
