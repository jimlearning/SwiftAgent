import Foundation

/// Invokes a slash-command skill with optional arguments.
/// Matches Claude Code's SkillTool.
public struct SkillTool: Tool {
    public let name = "Skill"
    public var searchHint: String? { "invoke a slash-command skill" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Execute a skill within the main conversation. Skills provide specialized capabilities and domain knowledge. Available skills are listed in system-reminder messages in the conversation. When users reference a slash command or \"/\", they are referring to a skill." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["skill"] = JSONSchemaProperty(type: "string", description: "The skill name. E.g., \"commit\", \"review-pr\", or \"pdf\"")
        schema.properties?["args"] = JSONSchemaProperty(type: "string", description: "Optional arguments for the skill")
        schema.required = ["skill"]
        return schema
    }()

    private let knownSkills: [String]

    public init(knownSkills: [String] = []) {
        self.knownSkills = knownSkills
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let skillVal = input["skill"], case .string(let skill) = skillVal else {
            return ToolResult(content: "Error: skill name is required", isError: true)
        }

        var commandName = skill.trimmingCharacters(in: .whitespaces)
        if commandName.hasPrefix("/") {
            commandName = String(commandName.dropFirst())
        }

        guard !commandName.isEmpty else {
            return ToolResult(content: "Invalid skill name: \"\(skill)\"", isError: true)
        }

        let args: String
        if let a = input["args"], case .string(let s) = a { args = s } else { args = "" }

        if !knownSkills.isEmpty && !knownSkills.contains(commandName) {
            return ToolResult(content: "Unknown skill: \(commandName)", isError: true)
        }

        let argNote = args.isEmpty ? "" : " with args: \(args)"

        return ToolResult(content: """
            Launching skill: \(commandName)\(argNote)

            The skill's instructions and context have been loaded into the conversation. Follow the skill's guidance to complete the task.
            """)
    }
}
