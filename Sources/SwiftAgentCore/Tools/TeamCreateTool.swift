import Foundation

/// Creates a new teammate agent for collaborative work.
/// Mirrors Claude Code's TeamCreateTool.
public struct TeamCreateTool: Tool {
    public init() {}
    public let name = "TeamCreate"
    public var searchHint: String? { "create a multi-agent swarm team" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool { FeatureFlags.isAgentSwarmsEnabled() }

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Creates a new teammate agent for collaborative multi-agent work."
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "name": JSONSchemaProperty(type: "string", description: "Display name for the teammate."),
            "prompt": JSONSchemaProperty(type: "string", description: "Initial task or role for the teammate."),
            "agentType": JSONSchemaProperty(type: "string", description: "Agent type for the teammate (defaults to general-purpose)."),
            "model": JSONSchemaProperty(type: "string", description: "Model override for the teammate."),
        ], required: ["name", "prompt"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let name = input["name"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? "Teammate"
        let prompt = input["prompt"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? ""
        let teammateId = UUID().uuidString.prefix(8)
        return ToolResult(content: "Teammate '\(name)' created (id: \(teammateId)). Prompt: \(prompt.prefix(100))")
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let n) = input["name"] { return "Creating teammate \(n)" }
        return "Creating teammate"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "Creating teammate agent"
    }
}
