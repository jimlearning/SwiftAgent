import Foundation

// MARK: - Command Availability

/// Declares which auth/provider environments a command is available in.
/// Matches CC's CommandAvailability: 'claude-ai' | 'console'.
public enum CommandAvailability: String, Codable, Sendable {
    case claudeAI = "claude-ai"
    case console
}

// MARK: - Command Base

/// Common fields shared by all command types.
/// Matches CC's CommandBase (22 fields).
public struct CommandBase: Sendable {
    public let availability: [CommandAvailability]?
    public let description: String
    public let hasUserSpecifiedDescription: Bool
    /// Defaults to true. Only false when conditional enablement (feature flags, env checks).
    public let isEnabled: @Sendable () -> Bool
    /// If true, hidden from typeahead/help. Defaults to false.
    public let isHidden: Bool
    public let name: String
    public let aliases: [String]?
    public let isMcp: Bool
    /// Hint text for command arguments (displayed in gray after command).
    public let argumentHint: String?
    /// From the "Skill" spec — detailed usage scenarios.
    public let whenToUse: String?
    /// Version of the command/skill.
    public let version: String?
    /// Whether to disable this command from being invoked by models.
    public let disableModelInvocation: Bool
    /// Whether users can invoke this skill by typing /skill-name.
    public let userInvocable: Bool?
    /// Where the command was loaded from.
    public let loadedFrom: CommandSource?
    /// Distinguishes workflow-backed commands (badged in autocomplete).
    public let kind: CommandKind?
    /// If true, command executes immediately without waiting for a stop point.
    public let immediate: Bool
    /// If true, args are redacted from the conversation history.
    public let isSensitive: Bool
    /// Override for the displayed name (defaults to `name`). Matches CC's userFacingName().
    public let userFacingName: @Sendable () -> String?

    public init(
        availability: [CommandAvailability]? = nil,
        description: String,
        hasUserSpecifiedDescription: Bool = false,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        isHidden: Bool = false,
        name: String,
        aliases: [String]? = nil,
        isMcp: Bool = false,
        argumentHint: String? = nil,
        whenToUse: String? = nil,
        version: String? = nil,
        disableModelInvocation: Bool = false,
        userInvocable: Bool? = nil,
        loadedFrom: CommandSource? = nil,
        kind: CommandKind? = nil,
        immediate: Bool = false,
        isSensitive: Bool = false,
        userFacingName: @escaping @Sendable () -> String? = { nil }
    ) {
        self.availability = availability
        self.description = description
        self.hasUserSpecifiedDescription = hasUserSpecifiedDescription
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.name = name
        self.aliases = aliases
        self.isMcp = isMcp
        self.argumentHint = argumentHint
        self.whenToUse = whenToUse
        self.version = version
        self.disableModelInvocation = disableModelInvocation
        self.userInvocable = userInvocable
        self.loadedFrom = loadedFrom
        self.kind = kind
        self.immediate = immediate
        self.isSensitive = isSensitive
        self.userFacingName = userFacingName
    }
}

/// Matches CC's Command.loadedFrom: 'commands_DEPRECATED' | 'skills' | 'plugin' | 'managed' | 'bundled' | 'mcp'.
public enum CommandSource: String, Codable, Sendable {
    case commandsDEPRECATED = "commands_DEPRECATED"
    case skills
    case plugin
    case managed
    case bundled
    case mcp
}

/// Matches CC's Command.kind: 'workflow'.
public enum CommandKind: String, Codable, Sendable {
    case workflow
}

// MARK: - Prompt Command

/// A skill/command that generates a prompt for the model.
/// Matches CC's PromptCommand (type: 'prompt', 17 fields).
public struct PromptCommand: Sendable {
    public let type = "prompt"
    public let progressMessage: String
    /// Length of command content in characters (used for token estimation). Matches CC's contentLength.
    public let contentLength: Int
    public let argNames: [String]?
    public let allowedTools: [String]?
    public let model: String?
    public let source: PromptCommandSource
    public let pluginInfo: PluginCommandInfo?
    public let disableNonInteractive: Bool
    /// Hooks to register when this skill is invoked.
    public let hooks: HookConfig?
    /// Base directory for skill resources (CLAUDE_PLUGIN_ROOT).
    public let skillRoot: String?
    /// Execution context: 'inline' (default) or 'fork' (run as sub-agent).
    public let context: CommandExecutionContext?
    /// Agent type to use when forked (only when context is 'fork').
    public let agent: String?
    /// Effort value for the skill. Matches CC's EffortValue.
    public let effort: EffortValue?
    /// Glob patterns for file paths this skill applies to — only visible after model touches matching files.
    public let paths: [String]?
    /// Async function returning content blocks for the model prompt.
    /// Matches CC's getPromptForCommand(args, context) => Promise<ContentBlockParam[]>.
    public let getPromptForCommand: @Sendable (String, ToolUseContext) async -> [ContentBlock]

    public init(
        progressMessage: String,
        contentLength: Int = 0,
        argNames: [String]? = nil,
        allowedTools: [String]? = nil,
        model: String? = nil,
        source: PromptCommandSource = .builtin,
        pluginInfo: PluginCommandInfo? = nil,
        disableNonInteractive: Bool = false,
        hooks: HookConfig? = nil,
        skillRoot: String? = nil,
        context: CommandExecutionContext? = nil,
        agent: String? = nil,
        effort: EffortValue? = nil,
        paths: [String]? = nil,
        getPromptForCommand: @escaping @Sendable (String, ToolUseContext) async -> [ContentBlock] = { _, _ in [] }
    ) {
        self.progressMessage = progressMessage
        self.contentLength = contentLength
        self.argNames = argNames
        self.allowedTools = allowedTools
        self.model = model
        self.source = source
        self.pluginInfo = pluginInfo
        self.disableNonInteractive = disableNonInteractive
        self.hooks = hooks
        self.skillRoot = skillRoot
        self.context = context
        self.agent = agent
        self.effort = effort
        self.paths = paths
        self.getPromptForCommand = getPromptForCommand
    }
}

/// Matches CC's PromptCommand.source: SettingSource | 'builtin' | 'mcp' | 'plugin' | 'bundled'.
public enum PromptCommandSource: String, Codable, Sendable {
    case userSettings
    case projectSettings
    case localSettings
    case flagSettings
    case policySettings
    case builtin
    case mcp
    case plugin
    case bundled
}

/// Matches CC's PromptCommand.pluginInfo: { pluginManifest: PluginManifest, repository: string }.
/// PluginManifest is intentionally omitted — type would create circular import with PluginManifest.
public struct PluginCommandInfo: Sendable {
    public let repository: String

    public init(repository: String) {
        self.repository = repository
    }
}

/// Matches CC's PromptCommand.context: 'inline' | 'fork'.
public enum CommandExecutionContext: String, Codable, Sendable {
    case inline
    case fork
}

// MARK: - Local Command

/// A command that runs synchronously and returns text, compact result, or skip.
/// Matches CC's LocalCommand (type: 'local').
public struct LocalCommand: Sendable {
    public let type = "local"
    public let supportsNonInteractive: Bool

    public init(supportsNonInteractive: Bool = true) {
        self.supportsNonInteractive = supportsNonInteractive
    }
}

/// Matches CC's LocalCommandResult: { type: 'text', value } | { type: 'compact', compactionResult, displayText? } | { type: 'skip' }.
public enum LocalCommandResult: Sendable {
    case text(value: String)
    case compact(displayText: String?)
    case skip
}

// MARK: - Local JSX Command

/// A command that renders Ink React UI.
/// Matches CC's LocalJSXCommand (type: 'local-jsx').
public struct LocalJSXCommand: Sendable {
    public let type = "local-jsx"

    public init() {}
}

// MARK: - Command (Discriminated Union)

/// The top-level Command type — intersection of CommandBase with a discriminated union of subtypes.
/// Matches CC's Command = CommandBase & (PromptCommand | LocalCommand | LocalJSXCommand).
public enum CommandType: Sendable {
    case prompt(PromptCommand)
    case local(LocalCommand)
    case localJSX(LocalJSXCommand)
}

/// Full command with base metadata and type-specific behavior.
/// Matches CC's Command.
public struct FullCommand: Sendable, Identifiable {
    public let base: CommandBase
    public let type: CommandType

    public var id: String { base.name }

    public init(base: CommandBase, type: CommandType) {
        self.base = base
        self.type = type
    }

    /// Resolve the user-visible name, falling back to base.name. Matches CC's getCommandName().
    public var userFacingName: String {
        base.userFacingName() ?? base.name
    }

    /// Resolve whether the command is enabled, defaulting to true. Matches CC's isCommandEnabled().
    public var isEnabled: Bool {
        base.isEnabled()
    }
}

// MARK: - Legacy Types (backwards compatibility)

/// Legacy Command struct — kept for backwards compatibility with existing code.
/// Deprecated in favor of FullCommand / CommandBase + CommandType.
public struct Command: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let type: LegacyCommandType
    public let arguments: [CommandArgument]
    public let aliases: [String]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        type: LegacyCommandType = .prompt,
        arguments: [CommandArgument] = [],
        aliases: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.arguments = arguments
        self.aliases = aliases
    }
}

/// Legacy command type — matches CC's discriminated union values.
public enum LegacyCommandType: String, Codable, Sendable {
    case prompt
    case local
    case localJSX = "local-jsx"
}

/// Legacy command argument.
public struct CommandArgument: Codable, Sendable {
    public var name: String
    public var description: String
    public var isRequired: Bool

    public init(name: String, description: String, isRequired: Bool = false) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
    }
}

/// Context passed to command execution.
public struct CommandContext: Sendable {
    public let input: String
    public let sessionID: String
    public let workingDirectory: String

    public init(input: String, sessionID: String, workingDirectory: String) {
        self.input = input
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Resume Entrypoint

/// Matches CC's ResumeEntrypoint.
public enum ResumeEntrypoint: String, Codable, Sendable {
    case cliFlag = "cli_flag"
    case slashCommandPicker = "slash_command_picker"
    case slashCommandSessionId = "slash_command_session_id"
    case slashCommandTitle = "slash_command_title"
    case fork
}

// MARK: - Command Result Display

/// Matches CC's CommandResultDisplay: 'skip' | 'system' | 'user'.
public enum CommandResultDisplay: String, Codable, Sendable {
    case skip
    case system
    case user
}
