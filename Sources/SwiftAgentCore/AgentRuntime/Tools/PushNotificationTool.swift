import Foundation

/// Push notification tool. Feature-gated behind KAIROS || KAIROS_PUSH_NOTIFICATION.
/// CC: tools/PushNotificationTool/ — feature('KAIROS') || feature('KAIROS_PUSH_NOTIFICATION').
public struct PushNotificationTool: Tool {
    public let name = "PushNotification"
    public let description = "Send push notifications to the user."

    public struct Arguments: Codable, Sendable {
        public var message: String
        public var title: String?

        enum CodingKeys: String, CodingKey {
            case message
            case title
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "message": JSONSchemaProperty(type: "string", description: "Notification message body"),
            "title": JSONSchemaProperty(type: "string", description: "Notification title"),
        ], required: ["message"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("PushNotification tool requires ant-internal build.")
    }
}
