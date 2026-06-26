import Foundation

/// Sends a message to the user.
/// Matches Claude Code's BriefTool / SendUserMessage.
public struct BriefTool: Tool {
    public let name = "SendUserMessage"
    public let description = "Send a message to the user. Your primary visible output channel — use this for replies the user must see. Text outside this tool is in the detail view and may not be read."

    public struct Arguments: Codable, Sendable {
        public var message: String
        public var attachments: [String]?

        enum CodingKeys: String, CodingKey {
            case message
            case attachments
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["message"] = JSONSchemaProperty(type: "string", description: "The message for the user. Supports markdown formatting.")
        schema.properties?["attachments"] = JSONSchemaProperty(type: "array", description: "Optional file paths (absolute or relative to cwd) to attach. Use for photos, screenshots, diffs, logs, or any file the user should see alongside your message.")
        schema.required = ["message"]
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let attachmentCount = arguments.attachments?.count ?? 0
        let attachmentSuffix = attachmentCount > 0 ? " (\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s") included)" : ""
        return .string("Message delivered to user.\(attachmentSuffix)")
    }
}
