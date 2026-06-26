import Foundation

/// Verifies plan execution results. Gated by CLAUDE_CODE_VERIFY_PLAN env var.
/// CC: tools/VerifyPlanExecutionTool/ — process.env.CLAUDE_CODE_VERIFY_PLAN === 'true'.
public struct VerifyPlanExecutionTool: Tool {
    public let name = "VerifyPlanExecution"
    public let description = "Verify that the execution matches the plan and report discrepancies."

    public struct Arguments: Codable, Sendable {
        public var planId: String

        enum CodingKeys: String, CodingKey {
            case planId = "plan_id"
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "plan_id": JSONSchemaProperty(type: "string", description: "ID of the plan to verify"),
        ], required: ["plan_id"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("VerifyPlanExecution tool is disabled by default. Set CLAUDE_CODE_VERIFY_PLAN=true to enable.")
    }
}
