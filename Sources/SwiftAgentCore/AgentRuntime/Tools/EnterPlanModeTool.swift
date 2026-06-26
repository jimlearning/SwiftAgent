import Foundation

/// Switches the session into plan mode (read-only exploration).
/// Matches Claude Code's EnterPlanModeTool.
public struct EnterPlanModeTool: Tool {
    public let name = "EnterPlanMode"
    public let description = "Switch to plan mode to design an approach before coding."

    /// Closure that activates plan mode at the session level.
    /// Captured at init, invoked during call().
    private let setPlanModeActive: @Sendable (Bool) -> Void

    public struct Arguments: Codable, Sendable {
        public var description: String?

        enum CodingKeys: String, CodingKey {
            case description
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "Brief description of the plan")
        return schema
    }

    public init(setPlanModeActive: @escaping @Sendable (Bool) -> Void) {
        self.setPlanModeActive = setPlanModeActive
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let planDesc = arguments.description ?? "No description provided"

        // Activate plan mode state via captured closure
        setPlanModeActive(true)

        return .string("""
            Entering plan mode: \(planDesc)

            Plan mode helps you explore the codebase and design an approach
            before implementing. During plan mode:
            - Read-only tools are auto-approved
            - Write/edit/bash tools require explicit confirmation
            - Use ExitPlanMode to present your plan and start coding
            """)
    }
}
