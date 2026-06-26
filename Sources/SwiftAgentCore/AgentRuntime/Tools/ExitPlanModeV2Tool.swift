import Foundation

/// Exits plan mode and presents the plan for approval.
/// Matches Claude Code's ExitPlanModeV2Tool.
public struct ExitPlanModeV2Tool: Tool {
    public let name = "ExitPlanMode"
    public let description = "Present your plan for approval and exit plan mode to start coding."

    /// Closure that deactivates plan mode at the session level.
    /// Captured at init, invoked during call().
    private let setPlanModeActive: @Sendable (Bool) -> Void

    public struct Arguments: Codable, Sendable {
        public var plan: String

        enum CodingKeys: String, CodingKey {
            case plan
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["plan"] = JSONSchemaProperty(type: "string", description: "The plan to present for user approval")
        schema.required = ["plan"]
        return schema
    }

    public init(setPlanModeActive: @escaping @Sendable (Bool) -> Void) {
        self.setPlanModeActive = setPlanModeActive
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        // Deactivate plan mode state via captured closure
        setPlanModeActive(false)

        return .string("""
            ## Implementation Plan

            \(arguments.plan)

            Exiting plan mode. Ready to implement the plan.
            """)
    }
}
