import Foundation

/// Send user file tool. Feature-gated behind KAIROS.
/// CC: tools/SendUserFileTool/ — feature('KAIROS').
public struct SendUserFileTool: Tool {
    public let name = "SendUserFile"
    public let description = "Send files to the user through the KAIROS messaging system."

    public struct Arguments: Codable, Sendable {
        public var filePath: String
        public var message: String?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case message
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "Path to the file to send"),
            "message": JSONSchemaProperty(type: "string", description: "Optional message to include with the file"),
        ], required: ["file_path"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("SendUserFile tool requires ant-internal build.")
    }
}
