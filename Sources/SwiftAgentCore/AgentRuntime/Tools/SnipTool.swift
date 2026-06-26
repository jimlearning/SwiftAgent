import Foundation

/// Conversation history snipping tool. Feature-gated behind HISTORY_SNIP.
/// CC: tools/SnipTool/ — feature('HISTORY_SNIP').
public struct SnipTool: Tool {
    public let name = "Snip"
    public let description = "Remove or archive portions of conversation history."

    public struct Arguments: Codable, Sendable {
        public var range: String

        enum CodingKeys: String, CodingKey {
            case range
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "range": JSONSchemaProperty(type: "string", description: "Range of messages to snip"),
        ], required: ["range"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("Snip tool requires ant-internal build.")
    }
}
