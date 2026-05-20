import Foundation

/// Triggers a remote action in a non-interactive session.
/// Mirrors Claude Code's RemoteTriggerTool.
public struct RemoteTriggerTool: Tool {
    public init() {}
    public let name = "RemoteTrigger"
    public var searchHint: String? { "manage scheduled remote agent triggers" }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Triggers a remote action via the session bridge for CI/CD automation."
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Action: list, get, create, update, or run", enum: ["list", "get", "create", "update", "run"]),
            "trigger_id": JSONSchemaProperty(type: "string", description: "Required for get, update, and run"),
            "body": JSONSchemaProperty(type: "object", description: "JSON body for create and update"),
        ], required: ["action"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let action = input["action"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? "list"
        let triggerID = input["trigger_id"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? ""
        return ToolResult(content: "Remote trigger action '\(action)' for trigger_id: \(triggerID)")
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let t) = input["trigger"] { return "Triggering \(t)" }
        return "Remote trigger"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "Triggering remote action"
    }

    public func isDestructive(_ input: [String: JSONValue]) -> Bool { true }
}
