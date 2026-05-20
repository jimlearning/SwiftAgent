import Foundation

/// Verifies plan execution results. Gated by CLAUDE_CODE_VERIFY_PLAN env var.
/// CC: tools/VerifyPlanExecutionTool/ — process.env.CLAUDE_CODE_VERIFY_PLAN === 'true'.
public struct VerifyPlanExecutionTool: Tool {
    public init() {}
    public let name = "VerifyPlanExecution"
    public var searchHint: String? { "verify that a plan was executed correctly" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Verify that the execution matches the plan and report discrepancies." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["CLAUDE_CODE_VERIFY_PLAN"] == "true"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "plan_id": JSONSchemaProperty(type: "string", description: "ID of the plan to verify"),
        ], required: ["plan_id"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "VerifyPlanExecution tool is disabled by default. Set CLAUDE_CODE_VERIFY_PLAN=true to enable.", isError: true)
    }
}
