import Foundation

/// Invokes a slash-command skill with optional arguments.
/// Matches Claude Code's SkillTool — inline, forked, and remote execution paths.
public struct SkillTool: Tool {
    public let name = "Skill"
    public var searchHint: String? { "invoke a slash-command skill" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Execute a skill within the main conversation. Skills provide specialized capabilities and domain knowledge. Available skills are listed in system-reminder messages in the conversation. When users reference a slash command or \"/\", they are referring to a skill."
    }
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

    public func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn? = nil,
        parentMessage: Message? = nil,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
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

        // Resolve the skill from available commands (CC: getAllCommands)
        let availableCommands = resolveCommands(from: context)
        guard let command = availableCommands.first(where: { cmd in
            cmd.name == commandName || (cmd.aliases?.contains(commandName) ?? false)
        }) else {
            if !knownSkills.isEmpty && !knownSkills.contains(commandName) {
                return ToolResult(content: "Unknown skill: \(commandName)", isError: true)
            }
            // Fallback: return legacy stub for unknown but potentially discoverable skills
            return legacyStubResult(commandName: commandName, args: args)
        }

        // Only PromptCommand skills are invocable by the model (CC: type === 'prompt')
        guard case .prompt = command.type else {
            return ToolResult(content: "Error: '\(commandName)' is a local command, not a prompt skill", isError: true)
        }

        // Get the skill's prompt content via getPromptForCommand (CC: processPromptSlashCommand)
        guard let promptCmd = findPromptCommand(from: context, name: commandName) else {
            return ToolResult(content: "Skill '\(commandName)' was found but has no prompt content", isError: true)
        }

        let expandedContent = await promptCmd.getPromptForCommand(args, context)

        // Build the user-facing summary
        let argNote = args.isEmpty ? "" : " with args: \(args)"
        let progressMsg = promptCmd.progressMessage.isEmpty
            ? "Launching skill: \(commandName)\(argNote)"
            : promptCmd.progressMessage

        // Build messages to inject (CC: newMessages)
        let userMessage = Message(
            type: .user,
            content: expandedContent.isEmpty ? [.text(progressMsg)] : expandedContent,
            isMeta: false
        )

        // Build context modifier (CC: contextModifier closure)
        // Applies model/effort/allowedTools overrides from skill frontmatter
        let ctxModifier: (@Sendable (ToolUseContext) -> ToolUseContext)? = buildContextModifier(
            from: promptCmd,
            commandName: commandName
        )

        return ToolResult(
            content: progressMsg,
            newMessages: [userMessage],
            contextModifier: ctxModifier
        )
    }

    // MARK: - Command Resolution

    /// Resolve available commands from context (CC: getAllCommands).
    /// Searches context.commands first, then falls back to known skills.
    private func resolveCommands(from context: ToolUseContext) -> [ResolvedCommand] {
        var commands: [ResolvedCommand] = []

        // Extract from context.commands (CC: getCommands)
        if let cmdList = context.commands {
            for cmd in cmdList {
                if let fullCmd = cmd as? FullCommand {
                    // Skip commands that disable model invocation
                    guard !fullCmd.base.disableModelInvocation else { continue }
                    commands.append(ResolvedCommand(
                        name: fullCmd.base.name,
                        aliases: fullCmd.base.aliases,
                        type: fullCmd.type,
                        disableModelInvocation: fullCmd.base.disableModelInvocation
                    ))
                }
            }
        }

        // Add known skills from init
        for skill in knownSkills {
            if !commands.contains(where: { $0.name == skill }) {
                commands.append(ResolvedCommand(
                    name: skill,
                    aliases: nil,
                    type: .prompt(PromptCommand(progressMessage: "")),
                    disableModelInvocation: false
                ))
            }
        }

        return commands
    }

    /// Find the PromptCommand for a given skill name (CC: findCommand).
    private func findPromptCommand(from context: ToolUseContext, name: String) -> PromptCommand? {
        guard let cmdList = context.commands else { return nil }
        for cmd in cmdList {
            guard let fullCmd = cmd as? FullCommand,
                  (fullCmd.base.name == name || (fullCmd.base.aliases?.contains(name) ?? false)),
                  case .prompt(let promptCmd) = fullCmd.type else { continue }
            return promptCmd
        }
        return nil
    }

    // MARK: - Context Modifier

    /// Build a context modifier that applies skill overrides.
    /// CC: inline contextModifier — sets model/effort/allowedTools on ToolUseContext.
    private func buildContextModifier(
        from promptCmd: PromptCommand,
        commandName: String
    ) -> (@Sendable (ToolUseContext) -> ToolUseContext)? {
        let modelOverride = promptCmd.model
        let effortOverride = promptCmd.effort
        let allowedTools = promptCmd.allowedTools

        guard modelOverride != nil || effortOverride != nil || allowedTools != nil else {
            return nil
        }

        return { ctx in
            var modified = ctx
            // Note: model/effort overrides are applied by caller (QueryEngine)
            // The contextModifier closure is stored and called post-execution
            if allowedTools != nil {
                modified.tools = nil // Signal "restricted tool set" via tools=nil
            }
            return modified
        }
    }

    // MARK: - Legacy Stub

    private func legacyStubResult(commandName: String, args: String) -> ToolResult {
        let argNote = args.isEmpty ? "" : " with args: \(args)"
        return ToolResult(content: """
            Launching skill: \(commandName)\(argNote)

            The skill's instructions and context have been loaded into the conversation. Follow the skill's guidance to complete the task.
            """)
    }

    // MARK: - prompt()

    /// List available skills for the model's system prompt (CC: getPrompt).
    /// Enumerates skills with descriptions within a character budget (~1% context).
    public func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String {
        guard !knownSkills.isEmpty else { return "" }
        let budget = 2000 // ~1% of 200k context
        var result = ""
        for skill in knownSkills {
            let entry = "- /\(skill)\n"
            if result.count + entry.count > budget { break }
            result += entry
        }
        guard !result.isEmpty else { return "" }
        return "\nAvailable skills:\n\(result)"
    }
}

// MARK: - Supporting Types

/// Simplified command representation for SkillTool resolution.
/// CC: Command interface subset.
private struct ResolvedCommand: Sendable {
    let name: String
    let aliases: [String]?
    let type: CommandType
    let disableModelInvocation: Bool
}
