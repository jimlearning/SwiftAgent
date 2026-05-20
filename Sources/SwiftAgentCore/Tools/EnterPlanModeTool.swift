import Foundation

/// Switches the session into plan mode (read-only exploration).
/// Matches Claude Code's EnterPlanModeTool.
public struct EnterPlanModeTool: Tool {
    public let name = "EnterPlanMode"
    public var searchHint: String? { "switch to plan mode to design an approach before coding" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Switch to plan mode to design an approach before coding" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "Brief description of the plan")
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let planDesc: String
        if let d = input["description"], case .string(let s) = d { planDesc = s }
        else { planDesc = "No description provided" }

        return ToolResult(content: """
            Entering plan mode: \(planDesc)

            Plan mode helps you explore the codebase and design an approach
            before implementing. During plan mode:
            - Read-only tools are auto-approved
            - Write/edit/bash tools require explicit confirmation
            - Use ExitPlanMode to present your plan and start coding
            """)
    }
}
