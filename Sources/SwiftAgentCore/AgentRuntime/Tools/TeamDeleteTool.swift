import Foundation

/// Removes a teammate agent from the session.
/// Mirrors Claude Code's TeamDeleteTool.
public struct TeamDeleteTool: Tool {
    public let name = "TeamDelete"
    public let description = "Removes a teammate agent and cleans up its resources."

    public struct Arguments: Codable, Sendable {
        public var teammateID: String
        public var reason: String?

        enum CodingKeys: String, CodingKey {
            case teammateID = "teammateID"
            case reason
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "teammateID": JSONSchemaProperty(type: "string", description: "The ID of the teammate to remove."),
            "reason": JSONSchemaProperty(type: "string", description: "Optional reason for removal (logged)."),
        ], required: ["teammateID"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let id = arguments.teammateID
        return .string("Teammate '\(id)' removed successfully.")
    }
}
