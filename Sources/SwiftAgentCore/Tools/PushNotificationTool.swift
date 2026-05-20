import Foundation

/// Push notification tool. Feature-gated behind KAIROS || KAIROS_PUSH_NOTIFICATION.
/// CC: tools/PushNotificationTool/ — feature('KAIROS') || feature('KAIROS_PUSH_NOTIFICATION').
public struct PushNotificationTool: Tool {
    public init() {}
    public let name = "PushNotification"
    public var searchHint: String? { "send push notifications to users" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Send push notifications to the user." }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "message": JSONSchemaProperty(type: "string", description: "Notification message body"),
            "title": JSONSchemaProperty(type: "string", description: "Notification title"),
        ], required: ["message"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "PushNotification tool requires ant-internal build.", isError: true)
    }
}
