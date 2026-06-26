import Foundation

/// Triggers a remote action in a non-interactive session.
/// Mirrors Claude Code's RemoteTriggerTool.
public struct RemoteTriggerTool: Tool {
    public let name = "RemoteTrigger"
    public let description = "Triggers a remote action via the session bridge for CI/CD automation."

    public struct Arguments: Codable, Sendable {
        public var action: String
        public var triggerId: String?
        public var body: [String: JSONValue]?

        enum CodingKeys: String, CodingKey {
            case action
            case triggerId = "trigger_id"
            case body
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Action: list, get, create, update, or run", enum: ["list", "get", "create", "update", "run"]),
            "trigger_id": JSONSchemaProperty(type: "string", description: "Required for get, update, and run"),
            "body": JSONSchemaProperty(type: "object", description: "JSON body for create and update"),
        ], required: ["action"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let triggerID = arguments.triggerId ?? ""
        return .string("Remote trigger action '\(arguments.action)' for trigger_id: \(triggerID)")
    }
}
