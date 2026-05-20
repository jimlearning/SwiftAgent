import Foundation

/// Exits plan mode and presents the plan for approval.
/// Matches Claude Code's ExitPlanModeV2Tool.
public struct ExitPlanModeV2Tool: Tool {
    public let name = "ExitPlanMode"
    public var searchHint: String? { "present plan for approval and start coding (plan mode only)" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Present your plan for approval and exit plan mode to start coding" }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["plan"] = JSONSchemaProperty(type: "string", description: "The plan to present for user approval")
        schema.required = ["plan"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let planVal = input["plan"], case .string(let plan) = planVal else {
            return ToolResult(content: "Error: plan is required", isError: true)
        }

        return ToolResult(content: """
            ## Implementation Plan

            \(plan)

            Exiting plan mode. Ready to implement the plan.
            """)
    }
}
