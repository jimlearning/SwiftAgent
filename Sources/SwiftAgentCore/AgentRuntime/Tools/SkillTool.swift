import Foundation

/// Invokes a slash-command skill with optional arguments.
/// Matches Claude Code's SkillTool.
///
/// Resolves the skill name against known skills and returns instructions
/// for the LLM to follow. The actual skill content injection is handled
/// by the session orchestrator.
public struct SkillTool: Tool {
    public let name = "Skill"
    public let description = """
        Execute a skill within the main conversation. Skills provide specialized \
        capabilities and domain knowledge. Available skills are listed in \
        system-reminder messages in the conversation. When users reference a \
        slash command or "/", they are referring to a skill.
        """

    private let knownSkills: [String]

    public struct Arguments: Codable, Sendable {
        public var skill: String
        public var args: String?

        enum CodingKeys: String, CodingKey {
            case skill
            case args
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["skill"] = JSONSchemaProperty(
            type: "string",
            description: "The skill name. E.g., \"commit\", \"review-pr\", or \"pdf\""
        )
        schema.properties?["args"] = JSONSchemaProperty(
            type: "string",
            description: "Optional arguments for the skill"
        )
        schema.required = ["skill"]
        return schema
    }

    public init(knownSkills: [String] = []) {
        self.knownSkills = knownSkills
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        var commandName = arguments.skill.trimmingCharacters(in: .whitespaces)
        if commandName.hasPrefix("/") {
            commandName = String(commandName.dropFirst())
        }

        guard !commandName.isEmpty else {
            return .string("Invalid skill name: \"\(arguments.skill)\"")
        }

        let args = arguments.args ?? ""

        // Validate against known skills
        if !knownSkills.isEmpty && !knownSkills.contains(commandName) {
            return .string("Unknown skill: \(commandName)")
        }

        // Build invocation message
        let argNote = args.isEmpty ? "" : " with args: \(args)"
        let progressMsg = "Launching skill: \(commandName)\(argNote)"

        if knownSkills.contains(commandName) {
            return .string("""
                \(progressMsg)

                The skill's instructions and context have been loaded into the \
                conversation. Follow the skill's guidance to complete the task.
                """)
        }

        // Legacy stub for discoverable but not explicitly known skills
        return legacyStubResult(commandName: commandName, args: args)
    }

    // MARK: - Legacy Stub

    private func legacyStubResult(commandName: String, args: String) -> ToolOutputValue {
        let argNote = args.isEmpty ? "" : " with args: \(args)"
        return .string("""
            Launching skill: \(commandName)\(argNote)

            The skill's instructions and context have been loaded into the \
            conversation. Follow the skill's guidance to complete the task.
            """)
    }
}
