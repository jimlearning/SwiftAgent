import Foundation

/// Result of executing a slash command.
/// Matches CC's LocalCommandResult: text | compact | skip.
public enum CommandResult: Sendable {
    case text(String)
    case exit
    case error(String)
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

    public init() {
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
    }
}
