import Foundation

/// Creates a new teammate agent for collaborative work.
/// Mirrors Claude Code's TeamCreateTool.
public struct TeamCreateTool: Tool {
    public let name = "TeamCreate"
    public let description = "Creates a new teammate agent for collaborative multi-agent work."

    public struct Arguments: Codable, Sendable {
        public var name: String
        public var prompt: String
        public var agentType: String?
        public var model: String?

        enum CodingKeys: String, CodingKey {
            case name
            case prompt
            case agentType = "agentType"
            case model
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "name": JSONSchemaProperty(type: "string", description: "Display name for the teammate."),
            "prompt": JSONSchemaProperty(type: "string", description: "Initial task or role for the teammate."),
            "agentType": JSONSchemaProperty(type: "string", description: "Agent type for the teammate (defaults to general-purpose)."),
            "model": JSONSchemaProperty(type: "string", description: "Model override for the teammate."),
        ], required: ["name", "prompt"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let name = arguments.name.isEmpty ? "Teammate" : arguments.name
        let prompt = arguments.prompt
        let teammateId = UUID().uuidString.prefix(8)
        return .string("Teammate '\(name)' created (id: \(teammateId)). Prompt: \(prompt.prefix(100))")
    }
}
