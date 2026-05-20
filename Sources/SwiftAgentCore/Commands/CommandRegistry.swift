import Foundation

/// Result of executing a slash command.
/// Matches CC's LocalCommandResult: text | compact | skip.
public enum CommandResult: Sendable {
    case text(String)
    case exit
    case error(String)
}

/// State snapshot provided to slash commands that need app context.
/// Matches CC's command execution context (AppState, settings, etc.).
public struct CommandStateProvider: Sendable {
    public var currentModel: String?
    public var permissionMode: String?
    public var sessionInfo: SessionInfo?
    public var mcpServers: [String]?
    public var activeTasks: [String]?
    public var workingDirectory: String?

    public struct SessionInfo: Sendable {
        public let sessionId: String
        public let startTime: Date
        public let tokenUsage: TokenUsageInfo?
        public init(sessionId: String, startTime: Date = Date(), tokenUsage: TokenUsageInfo? = nil) {
            self.sessionId = sessionId
            self.startTime = startTime
            self.tokenUsage = tokenUsage
        }
    }

    public struct TokenUsageInfo: Sendable {
        public let inputTokens: Int
        public let outputTokens: Int
        public init(inputTokens: Int, outputTokens: Int) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public init(
        currentModel: String? = nil,
        permissionMode: String? = nil,
        sessionInfo: SessionInfo? = nil,
        mcpServers: [String]? = nil,
        activeTasks: [String]? = nil,
        workingDirectory: String? = nil
    ) {
        self.currentModel = currentModel
        self.permissionMode = permissionMode
        self.sessionInfo = sessionInfo
        self.mcpServers = mcpServers
        self.activeTasks = activeTasks
        self.workingDirectory = workingDirectory
    }
}

/// Handler closure for executing a slash command.
/// Receives the full input line (including / prefix) and returns a result.
/// Matches CC's LocalCommand behavior.
public typealias CommandHandler = @Sendable (String) async -> CommandResult

/// Registry for slash commands matching CC's command system.
/// Commands can be local (immediate execution) or prompt-based (injected into LLM context).
/// Matches CC's command registration in commands/*/index.ts.
public final class CommandRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String: Command] = [:]
    private var handlers: [String: CommandHandler] = [:]

    /// Optional state provider for commands that need app state (model, permissions, sessions, tasks).
    /// Matches CC's command context passing pattern.
    public var stateProvider: (@Sendable () -> CommandStateProvider?)?

    public init(stateProvider: (@Sendable () -> CommandStateProvider?)? = nil) {
        self.stateProvider = stateProvider
        registerBuiltins()
    }

    public func register(_ command: Command, handler: CommandHandler? = nil) {
        lock.lock()
        commands[command.name] = command
        if let h = handler { handlers[command.name] = h }
        lock.unlock()
    }

    public func find(_ name: String) -> Command? {
        lock.lock()
        defer { lock.unlock() }
        return commands[name]
    }

    public var allCommands: [Command] {
        lock.lock()
        defer { lock.unlock() }
        return Array(commands.values).sorted { $0.name < $1.name }
    }

    /// Parse a slash command from input and return the matched command.
    /// Matches CC's parseSlashCommand() in slashCommandParsing.ts.
    public func match(input: String) -> (command: Command, args: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let withoutSlash = String(trimmed.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let name = String(parts[0])
        let args = parts.count > 1 ? String(parts[1]) : ""
        guard let command = find(name) else { return nil }
        return (command, args)
    }

    /// Execute a matched command. Returns the execution result.
    /// Matches CC's local command dispatch in processSlashCommand.tsx.
    public func execute(input: String) async -> CommandResult? {
        guard let (command, _) = match(input: input) else { return nil }
        if let handler = handlers[command.name] {
            return await handler(input)
        }
        return nil
    }

    /// Build help text listing all registered commands.
    /// Matches CC's /help command output.
    public func renderHelp() -> String {
        let cmds = allCommands
        var lines: [String] = ["Available Commands:"]
        for cmd in cmds {
            let argsDesc = formatArgs(cmd.arguments)
            let aliasStr = cmd.aliases.map { " (alias: \($0.joined(separator: ", ")))" } ?? ""
            lines.append("  /\(cmd.name)\(argsDesc) — \(cmd.description)\(aliasStr)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatArgs(_ arguments: [CommandArgument]) -> String {
        if arguments.isEmpty { return "" }
        let inner = arguments.map { arg -> String in
            let left = arg.isRequired ? "<" : "["
            let right = arg.isRequired ? ">" : "]"
            return "\(left)\(arg.name)\(right)"
        }.joined(separator: " ")
        return " [\(inner)]"
    }

    // MARK: - Builtins

    private func registerBuiltins() {
        // /help
        register(Command(name: "help", description: "Show available commands and their usage", type: .local)) { [weak self] _ in
            guard let self = self else { return .text("") }
            return .text(self.renderHelp())
        }

        // /exit, /quit
        register(Command(name: "exit", description: "Exit the current session", type: .local)) { _ in .exit }
        register(Command(name: "quit", description: "Alias for /exit", type: .local)) { _ in .exit }

        // /clear (CC aliases: reset, new)
        register(Command(name: "clear", description: "Clear the screen", type: .local)) { _ in
            .text("\u{001B}[2J\u{001B}[H")
        }

        // /model
        register(Command(name: "model", description: "Show or change the current model", type: .local,
            arguments: [CommandArgument(name: "model-id", description: "Model ID to switch to")]))

        // /config (CC alias: /settings)
        register(Command(name: "config", description: "Open config panel", type: .local,
            arguments: [CommandArgument(name: "key", description: "Configuration key to show")]))

        // /memory
        register(Command(name: "memory", description: "Edit Claude memory files", type: .local,
            arguments: [CommandArgument(name: "action", description: "add, list, or forget")]))

        // /doctor — CC parity: diagnostics
        register(Command(name: "doctor", description: "Diagnose and verify your Claude Code installation and settings", type: .local))

        // /cost — CC parity: session cost/duration
        register(Command(name: "cost", description: "Show the total cost and duration of the current session", type: .local))

        // /status — CC parity: session status
        register(Command(name: "status", description: "Show current session status and token usage", type: .local))

        // /compact — CC parity: manual compaction
        register(Command(name: "compact", description: "Compact conversation history to free context", type: .local))

        // /review — CC parity: PR review
        register(Command(name: "review", description: "Review a pull request", type: .local))

        // /diff — CC parity: show branch diff
        register(Command(name: "diff", description: "Show the diff of the current branch", type: .local))

        // /stats — CC parity: usage statistics
        register(Command(name: "stats", description: "Show your usage statistics and activity", type: .local))

        // /plan — CC parity: enable plan mode
        register(Command(name: "plan", description: "Enable plan mode or view the current session plan", type: .local))

        // /resume — CC parity: resume previous conversation (aliases: continue)
        register(Command(name: "resume", description: "Resume a previous conversation", type: .local))

        // MARK: - Iteration 58 — CC-parity commands

        // /mcp — list/add/remove MCP servers. CC parity.
        register(Command(name: "mcp", description: "Manage MCP server connections", type: .local,
            arguments: [CommandArgument(name: "action", description: "list, add, remove, or reconnect")])) { [weak self] _ in
            guard let self = self, let state = self.stateProvider?() else {
                return .text("MCP state unavailable")
            }
            var lines = ["MCP Server Connections:"]
            if let servers = state.mcpServers, !servers.isEmpty {
                for s in servers.sorted() { lines.append("  • \(s)") }
                lines.append("\(servers.count) server(s) configured")
            } else {
                lines.append("  (no MCP servers configured)")
            }
            return .text(lines.joined(separator: "\n"))
        }

        // /tasks — list active background tasks. CC parity.
        register(Command(name: "tasks", description: "List and manage background tasks", type: .local,
            arguments: [CommandArgument(name: "action", description: "list or cancel")])) { [weak self] _ in
            guard let self = self, let state = self.stateProvider?() else {
                return .text("Task state unavailable")
            }
            var lines = ["Active Tasks:"]
            if let tasks = state.activeTasks, !tasks.isEmpty {
                for t in tasks { lines.append("  • \(t)") }
                lines.append("\(tasks.count) active task(s)")
            } else {
                lines.append("  (no active tasks)")
            }
            return .text(lines.joined(separator: "\n"))
        }

        // /init — scaffold project settings. CC parity.
        register(Command(name: "init", description: "Initialize Claude Code in the current project", type: .local)) { [weak self] _ in
            guard let self = self else { return .text("") }
            let cwd = self.stateProvider?()?.workingDirectory ?? FileManager.default.currentDirectoryPath
            let claudeDir = "\(cwd)/.claude"
            let settingsPath = "\(claudeDir)/settings.json"
            let claudeMdPath = "\(cwd)/CLAUDE.md"

            let fm = FileManager.default
            var report: [String] = ["Initializing project..."]

            // Create .claude directory
            if !fm.fileExists(atPath: claudeDir) {
                try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
                report.append("  ✓ Created \(claudeDir)")
            } else {
                report.append("  • \(claudeDir) already exists")
            }

            // Create settings.json if missing
            if !fm.fileExists(atPath: settingsPath) {
                let defaultSettings = "{\n  \"permissions\": {}\n}\n"
                try? defaultSettings.write(toFile: settingsPath, atomically: true, encoding: .utf8)
                report.append("  ✓ Created \(settingsPath)")
            } else {
                report.append("  • \(settingsPath) already exists")
            }

            // Create CLAUDE.md if missing
            if !fm.fileExists(atPath: claudeMdPath) {
                let defaultMd = "# \(String(cwd.split(separator: "/").last ?? ""))\n\nAdd project instructions here.\n"
                try? defaultMd.write(toFile: claudeMdPath, atomically: true, encoding: .utf8)
                report.append("  ✓ Created \(claudeMdPath)")
            } else {
                report.append("  • \(claudeMdPath) already exists")
            }

            report.append("\nProject initialized. Edit CLAUDE.md to add project instructions.")
            return .text(report.joined(separator: "\n"))
        }

        // /permissions — view/change permission mode. CC parity.
        register(Command(name: "permissions", description: "View or change permission settings", type: .local,
            arguments: [CommandArgument(name: "mode", description: "Permission mode: default, acceptEdits, bypass, plan")])) { [weak self] input in
            guard let self = self, let state = self.stateProvider?() else {
                return .text("Permission state unavailable")
            }
            let parts = input.split(separator: " ", maxSplits: 1)
            if parts.count > 1 {
                let newMode = String(parts[1]).trimmingCharacters(in: .whitespaces)
                let validModes = ["default", "acceptEdits", "bypass", "plan", "dontAsk", "auto"]
                if validModes.contains(newMode) {
                    return .text("Permission mode change requested: \(newMode)\nRestart or reload to apply.")
                } else {
                    return .text("Invalid mode: \(newMode)\nValid modes: \(validModes.joined(separator: ", "))")
                }
            }
            let current = state.permissionMode ?? "default"
            return .text("Current permission mode: \(current)\nUse /permissions <mode> to change.\nModes: default, acceptEdits, bypass, plan, dontAsk, auto")
        }

        // /session — show session info. CC parity.
        register(Command(name: "session", description: "Show session info: cost, duration, tokens", type: .local)) { [weak self] _ in
            guard let self = self, let state = self.stateProvider?(), let info = state.sessionInfo else {
                return .text("Session info unavailable")
            }
            let duration = Date().timeIntervalSince(info.startTime)
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            var lines = ["Session: \(info.sessionId.prefix(8))...", "Duration: \(hours)h \(minutes)m"]
            if let usage = info.tokenUsage {
                lines.append("Input tokens: \(usage.inputTokens)")
                lines.append("Output tokens: \(usage.outputTokens)")
                lines.append("Total tokens: \(usage.inputTokens + usage.outputTokens)")
            }
            if let model = state.currentModel {
                lines.append("Model: \(model)")
            }
            return .text(lines.joined(separator: "\n"))
        }
    }
}
