import Foundation

/// Removes a teammate agent from the session.
/// Mirrors Claude Code's TeamDeleteTool.
public struct TeamDeleteTool: Tool {
    public init() {}
    public let name = "TeamDelete"
    public var searchHint: String? { "disband a swarm team and clean up" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Removes a teammate agent and cleans up its resources."
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "teammateID": JSONSchemaProperty(type: "string", description: "The ID of the teammate to remove."),
            "reason": JSONSchemaProperty(type: "string", description: "Optional reason for removal (logged)."),
        ], required: ["teammateID"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let id = input["teammateID"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? ""
        return ToolResult(content: "Teammate '\(id)' removed successfully.")
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let id) = input["teammateID"] { return "Removing teammate \(id)" }
        return "Removing teammate"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "Removing teammate agent"
    }
}
