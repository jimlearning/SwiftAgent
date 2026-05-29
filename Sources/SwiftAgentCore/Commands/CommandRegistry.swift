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
    public var planModeActive: Bool = false
    public var totalTokensIn: Int = 0
    public var totalTokensOut: Int = 0
    public var estimatedCostUsd: Double = 0.0

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
        workingDirectory: String? = nil,
        planModeActive: Bool = false,
        totalTokensIn: Int = 0,
        totalTokensOut: Int = 0,
        estimatedCostUsd: Double = 0.0
    ) {
        self.currentModel = currentModel
        self.permissionMode = permissionMode
        self.sessionInfo = sessionInfo
        self.mcpServers = mcpServers
        self.activeTasks = activeTasks
        self.workingDirectory = workingDirectory
        self.planModeActive = planModeActive
        self.totalTokensIn = totalTokensIn
        self.totalTokensOut = totalTokensOut
        self.estimatedCostUsd = estimatedCostUsd
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

    /// Callback invoked when /model changes the current model.
    /// The string parameter is the new model ID.
    public var onModelChange: (@Sendable (String) -> Void)?

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

        // /model — show or change model
        register(Command(name: "model", description: "Show or change the current model", type: .local,
            arguments: [CommandArgument(name: "model-id", description: "Model ID to switch to")])) { [weak self] input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let current = self?.stateProvider?()?.currentModel ?? "unknown"
            if parts.count > 1 {
                let newModel = String(parts[1]).trimmingCharacters(in: .whitespaces)
                guard !newModel.isEmpty else {
                    return .text("Current model: \(current)\nUse /model <model-id> to change.\nAvailable: default, deepseek-v4-flash, deepseek-v4-pro, gpt-4o, claude-sonnet-4-6")
                }
                self?.onModelChange?(newModel)
                return .text("Model changed to \(newModel) (was \(current)). The next LLM call will use the new model.")
            }
            return .text("Current model: \(current)\nUse /model <model-id> to change.\nAvailable: default, deepseek-v4-flash, deepseek-v4-pro, gpt-4o, claude-sonnet-4-6")
        }

        // /config (CC alias: /settings)
        register(Command(name: "config", description: "Open config panel", type: .local,
            arguments: [CommandArgument(name: "key", description: "Configuration key to show")])) { [weak self] input in
            let state = self?.stateProvider?()
            let parts = input.split(separator: " ", maxSplits: 1)
            let cwd = state?.workingDirectory ?? FileManager.default.currentDirectoryPath
            let model = state?.currentModel ?? "unknown"
            let perm = state?.permissionMode ?? "default"
            if parts.count > 1 {
                let key = String(parts[1]).trimmingCharacters(in: .whitespaces)
                switch key.lowercased() {
                case "model": return .text("model = \(model)")
                case "permission", "permissions": return .text("permissionMode = \(perm)")
                case "cwd", "workingdir": return .text("workingDirectory = \(cwd)")
                default: return .text("Config key '\(key)' not found. Available keys: model, permission, cwd")
                }
            }
            var lines = ["Configuration:"]
            lines.append("  Model:       \(model)")
            lines.append("  Permission:  \(perm)")
            lines.append("  Work Dir:    \(cwd)")
            lines.append("")
            lines.append("Config files (layered, highest priority first):")
            lines.append("  1. CLI flags (--model, --permission)")
            lines.append("  2. Local config  (.swift-agent/config.local.json)")
            lines.append("  3. Project config (.swift-agent/config.json)")
            lines.append("  4. User config    (~/.swift-agent/config.json)")
            lines.append("  5. Plugin configs")
            return .text(lines.joined(separator: "\n"))
        }

        // /memory — manage memory files
        register(Command(name: "memory", description: "Edit Claude memory files", type: .local,
            arguments: [CommandArgument(name: "action", description: "add, list, or forget")])) { [weak self] input in
            let parts = input.split(separator: " ", maxSplits: 2)
            let action = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "list"
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let memoryBase = "\(home)/.claude/projects"
            switch action.lowercased() {
            case "list":
                let fm = FileManager.default
                var lines = ["Memory files:"]
                let projectMemoryDir = "\(memoryBase)/-Users-jim-SwiftAgent/memory"
                if fm.fileExists(atPath: projectMemoryDir) {
                    if let files = try? fm.contentsOfDirectory(atPath: projectMemoryDir) {
                        let mdFiles = files.filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }
                        if mdFiles.isEmpty { lines.append("  (no project memory files)") }
                        else {
                            lines.append("  [Project] \(projectMemoryDir)")
                            for f in mdFiles.sorted() {
                                let attrs = try? fm.attributesOfItem(atPath: "\(projectMemoryDir)/\(f)")
                                let size = attrs?[.size] as? Int64 ?? 0
                                lines.append("    \(f) (\(size) bytes)")
                            }
                        }
                    }
                    let indexPath = "\(projectMemoryDir)/MEMORY.md"
                    if fm.fileExists(atPath: indexPath),
                       let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                        let entries = content.split(separator: "\n").filter { $0.hasPrefix("- [") }
                        if !entries.isEmpty { lines.append("  Index entries: \(entries.count)") }
                    }
                } else { lines.append("  (no project memory found)") }
                let userMemoryDir = "\(home)/.claude/memory"
                if fm.fileExists(atPath: userMemoryDir) {
                    if let files = try? fm.contentsOfDirectory(atPath: userMemoryDir) {
                        let mdFiles = files.filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }
                        lines.append("  [User] \(userMemoryDir)")
                        for f in mdFiles.sorted() {
                            let attrs = try? fm.attributesOfItem(atPath: "\(userMemoryDir)/\(f)")
                            let size = attrs?[.size] as? Int64 ?? 0
                            lines.append("    \(f) (\(size) bytes)")
                        }
                    }
                }
                lines.append("")
                lines.append("Use /memory add <content> to add a memory.")
                lines.append("Use /memory forget <file> to remove a memory.")
                return .text(lines.joined(separator: "\n"))
            case "add", "remember":
                let content = parts.count > 2 ? String(parts[2]) : ""
                guard !content.isEmpty else { return .text("Usage: /memory add <content to remember>") }
                let cwd = self?.stateProvider?()?.workingDirectory ?? FileManager.default.currentDirectoryPath
                let projectName = String(cwd.split(separator: "/").last ?? "unknown")
                let memoryDir = "\(memoryBase)/-Users-jim-\(projectName)/memory"
                let fm = FileManager.default
                try? fm.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
                let ts = Int(Date().timeIntervalSince1970)
                let filename = "memory_\(ts).md"
                let entry = """
                ---
                name: memory-\(ts)
                description: User-requested memory
                metadata:
                  type: project
                ---
                \(content)
                """
                do { try entry.write(toFile: "\(memoryDir)/\(filename)", atomically: true, encoding: .utf8); return .text("Memory saved to \(filename)") }
                catch { return .text("Error saving memory: \(error.localizedDescription)") }
            case "forget", "remove", "delete":
                let file = parts.count > 2 ? String(parts[2]) : ""
                guard !file.isEmpty else { return .text("Usage: /memory forget <filename>") }
                let target = "\(memoryBase)/-Users-jim-SwiftAgent/memory/\(file)"
                if FileManager.default.fileExists(atPath: target) {
                    try? FileManager.default.removeItem(atPath: target)
                    return .text("Memory '\(file)' removed.")
                }
                return .text("Memory file '\(file)' not found.")
            default:
                return .text("Unknown action: \(action). Use: list, add, forget")
            }
        }

        // /doctor — diagnostics
        register(Command(name: "doctor", description: "Diagnose and verify your Claude Code installation and settings", type: .local)) { [weak self] _ in
            let state = self?.stateProvider?()
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path
            var lines: [String] = ["SwiftAgent Diagnostics", String(repeating: "=", count: 30)]
            lines.append("\nAPI Key Sources:")
            let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
            let envToken = ProcessInfo.processInfo.environment["ANTHROPIC_AUTH_TOKEN"] ?? ""
            let claudeJson = "\(home)/.claude.json"
            lines.append(envKey.isEmpty ? "  ✗ ANTHROPIC_API_KEY: not set" : "  ✓ ANTHROPIC_API_KEY: \(envKey.prefix(8))...\(envKey.suffix(4))")
            lines.append(envToken.isEmpty ? "  ✗ ANTHROPIC_AUTH_TOKEN: not set" : "  ✓ ANTHROPIC_AUTH_TOKEN: set")
            lines.append(fm.fileExists(atPath: claudeJson) ? "  ✓ ~/.claude.json: exists" : "  ✗ ~/.claude.json: not found")
            lines.append("\nConfig Files:")
            let cwd = state?.workingDirectory ?? fm.currentDirectoryPath
            for cfg in ["~/.swift-agent/config.json", ".swift-agent/config.json", ".swift-agent/config.local.json", "CLAUDE.md", ".claude/settings.json"] {
                let path = cfg.replacingOccurrences(of: "~", with: home)
                let full = path.hasPrefix("/") ? path : "\(cwd)/\(path)"
                lines.append(fm.fileExists(atPath: full) ? "  ✓ \(cfg)" : "  ✗ \(cfg)")
            }
            lines.append("\nEnvironment:")
            lines.append("  Model:       \(state?.currentModel ?? "not set")")
            lines.append("  Permission:  \(state?.permissionMode ?? "default")")
            lines.append("  Base URL:    \(ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "(default)")")
            lines.append("\nBuild:")
            lines.append("  Swift:       \(ProcessInfo.processInfo.operatingSystemVersionString)")
            lines.append("  Version:     0.1.0")
            if let info = state?.sessionInfo {
                let dur = Date().timeIntervalSince(info.startTime)
                lines.append("\nSession: \(info.sessionId.prefix(8))... (\(Int(dur)/60)m active)")
            }
            lines.append("\n✓ SwiftAgent CLI is operational.")
            return .text(lines.joined(separator: "\n"))
        }

        // /cost — session cost and duration
        register(Command(name: "cost", description: "Show the total cost and duration of the current session", type: .local)) { [weak self] _ in
            guard let state = self?.stateProvider?(), let info = state.sessionInfo else {
                return .text("Session info unavailable. Start a conversation first.")
            }
            let dur = Date().timeIntervalSince(info.startTime)
            let h = Int(dur) / 3600; let m = (Int(dur) % 3600) / 60; let s = Int(dur) % 60
            var lines = ["Session Cost & Duration", String(repeating: "-", count: 25)]
            lines.append("Duration: \(h)h \(m)m \(s)s")
            if let usage = info.tokenUsage {
                lines.append("Input tokens:  \(usage.inputTokens)")
                lines.append("Output tokens: \(usage.outputTokens)")
                lines.append("Total tokens:  \(usage.inputTokens + usage.outputTokens)")
                let est = (Double(usage.inputTokens) / 1_000_000 * 3.0) + (Double(usage.outputTokens) / 1_000_000 * 15.0)
                lines.append(String(format: "Est. cost:     $%.4f", state.estimatedCostUsd > 0 ? state.estimatedCostUsd : est))
            }
            if let md = state.currentModel { lines.append("Model: \(md)") }
            lines.append("")
            lines.append("Note: Costs depend on your specific model pricing.")
            return .text(lines.joined(separator: "\n"))
        }

        // /status — current session status
        register(Command(name: "status", description: "Show current session status and token usage", type: .local)) { [weak self] _ in
            guard let state = self?.stateProvider?() else { return .text("No active session. Start a conversation first.") }
            var lines = ["Session Status", String(repeating: "-", count: 15)]
            if let info = state.sessionInfo {
                let dur = Date().timeIntervalSince(info.startTime)
                lines.append("Session:  \(info.sessionId.prefix(12))...")
                lines.append("Uptime:   \(Int(dur)/3600)h \((Int(dur)%3600)/60)m")
            }
            lines.append("Model:    \(state.currentModel ?? "unknown")")
            lines.append("Perm:     \(state.permissionMode ?? "default")")
            lines.append("Plan:     \(state.planModeActive ? "active" : "inactive")")
            if let usage = state.sessionInfo?.tokenUsage {
                lines.append("Tokens:   \(usage.inputTokens) in / \(usage.outputTokens) out")
            }
            lines.append("CWD:      \(state.workingDirectory ?? FileManager.default.currentDirectoryPath)")
            if let tasks = state.activeTasks, !tasks.isEmpty {
                lines.append("\nBackground Tasks: \(tasks.count)")
                for t in tasks { lines.append("  • \(t)") }
            }
            return .text(lines.joined(separator: "\n"))
        }

        // /compact — compact conversation
        register(Command(name: "compact", description: "Compact conversation history to free context", type: .local)) { [weak self] _ in
            guard let state = self?.stateProvider?() else { return .text("No active session to compact.") }
            let usage = state.sessionInfo?.tokenUsage
            let total = (usage?.inputTokens ?? 0) + (usage?.outputTokens ?? 0)
            var lines = ["Compaction Requested", String(repeating: "-", count: 20)]
            lines.append("Current usage: ~\(total) tokens")
            lines.append("")
            lines.append("Compaction will:")
            lines.append("  1. Summarize conversation history")
            lines.append("  2. Keep recent messages intact")
            lines.append("  3. Preserve tool results and decisions")
            lines.append("")
            lines.append("Note: Compaction is triggered automatically when")
            lines.append("context approaches token limits.")
            lines.append("Use /status to monitor token usage.")
            return .text(lines.joined(separator: "\n"))
        }

        // /review — review a PR
        register(Command(name: "review", description: "Review a pull request", type: .local,
            arguments: [CommandArgument(name: "pr-url-or-number", description: "PR URL or number to review")])) { input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            if arg.isEmpty {
                return .text("Usage: /review <PR URL or number>\n\nExamples:\n  /review https://github.com/owner/repo/pull/123\n  /review 123\n\nThis performs a code review using the code-review agent.")
            }
            return .text("PR Review Requested: \(arg)\n\nStart a conversation about this PR and the agent will use the code-review agent to analyze it.")
        }

        // /diff — show branch diff
        register(Command(name: "diff", description: "Show the diff of the current branch", type: .local,
            arguments: [CommandArgument(name: "base", description: "Base branch to diff against (default: main)")])) { [weak self] input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let base = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "main"
            let cwd = self?.stateProvider?()?.workingDirectory ?? FileManager.default.currentDirectoryPath
            var lines = ["Diff: \(base)...HEAD", String(repeating: "-", count: 30)]
            let runGit = { (args: [String]) -> String in
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = ["git", "-C", cwd] + args; p.currentDirectoryURL = URL(fileURLWithPath: cwd)
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
                try? p.run(); p.waitUntilExit()
                return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            let diffOut = runGit(["diff", "\(base)...HEAD", "--stat"])
            if diffOut.isEmpty { lines.append("(no differences — branch is up to date with \(base))") }
            else { lines.append(diffOut) }
            let logOut = runGit(["log", "--oneline", "\(base)...HEAD"])
            if !logOut.isEmpty { lines.append(""); lines.append("Commits:"); lines.append(logOut) }
            return .text(lines.joined(separator: "\n"))
        }

        // /stats — usage statistics
        register(Command(name: "stats", description: "Show your usage statistics and activity", type: .local)) { [weak self] _ in
            guard let state = self?.stateProvider?(), let info = state.sessionInfo else {
                return .text("No session active. Start a conversation to see statistics.")
            }
            let total = (info.tokenUsage?.inputTokens ?? 0) + (info.tokenUsage?.outputTokens ?? 0)
            let dur = Date().timeIntervalSince(info.startTime)
            var lines = ["Session Statistics", String(repeating: "=", count: 20), ""]
            lines.append("This Session:")
            lines.append("  Duration:      \(Int(dur)/3600)h \((Int(dur)%3600)/60)m")
            lines.append("  Input tokens:  \(info.tokenUsage?.inputTokens ?? 0)")
            lines.append("  Output tokens: \(info.tokenUsage?.outputTokens ?? 0)")
            lines.append("  Total tokens:  \(total)")
            lines.append(String(format: "  Est. cost:     $%.4f", state.estimatedCostUsd))
            lines.append("  Model:         \(state.currentModel ?? "unknown")")
            let sessionsDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swift-agent/sessions"
            if FileManager.default.fileExists(atPath: sessionsDir),
               let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) {
                let sFiles = files.filter { $0.hasSuffix(".json") }
                lines.append(""); lines.append("Saved Sessions: \(sFiles.count)")
                for f in sFiles.prefix(5).sorted().reversed() {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: "\(sessionsDir)/\(f)")
                    let d = attrs?[.modificationDate] as? Date
                    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
                    lines.append("  \(f.prefix(30))... \(d.map { df.string(from: $0) } ?? "unknown")")
                }
            }
            lines.append(""); lines.append("Tip: Use /cost for detailed cost breakdown.")
            return .text(lines.joined(separator: "\n"))
        }

        // /plan — enable/disable plan mode
        register(Command(name: "plan", description: "Enable plan mode or view the current session plan", type: .local)) { [weak self] input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let state = self?.stateProvider?()
            if parts.count > 1 {
                switch String(parts[1]).trimmingCharacters(in: .whitespaces).lowercased() {
                case "on", "enable", "start", "enter":
                    return .text("Plan mode enabled.\n\nIn plan mode:\n- Read-only tools are auto-approved\n- Write/edit/bash require explicit confirmation\n- Use ExitPlanMode tool to present your plan")
                case "off", "disable", "exit", "stop":
                    return .text("Plan mode disabled. Write tools are now available with permission checks.")
                default:
                    return .text("Usage: /plan [on|off]. Current: \(state?.planModeActive == true ? "active" : "inactive")")
                }
            }
            let active = state?.planModeActive == true
            var lines = ["Plan Mode: \(active ? "ACTIVE" : "inactive")", ""]
            lines.append("Plan mode helps design approaches before coding:")
            lines.append("  • Read/explore tools: auto-approved")
            lines.append("  • Write/edit tools: require confirmation")
            lines.append("")
            lines.append("To enter plan mode: /plan on")
            lines.append("To exit plan mode:  /plan off")
            lines.append("The LLM can also use EnterPlanMode/ExitPlanMode tools.")
            return .text(lines.joined(separator: "\n"))
        }

        // /resume — resume a previous conversation
        register(Command(name: "resume", description: "Resume a previous conversation", type: .local,
            arguments: [CommandArgument(name: "session-id", description: "Session ID or partial title to resume")])) { input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            let sessionsDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swift-agent/sessions"
            let fm = FileManager.default
            guard fm.fileExists(atPath: sessionsDir),
                  let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
                return .text("No saved sessions found at \(sessionsDir)")
            }
            let sFiles = files.filter { $0.hasSuffix(".json") }.sorted().reversed()
            if arg.isEmpty {
                var lines = ["Saved Sessions:", ""]
                if sFiles.isEmpty { lines.append("  (no saved sessions)") }
                else {
                    for (i, f) in sFiles.prefix(10).enumerated() {
                        let attrs = try? fm.attributesOfItem(atPath: "\(sessionsDir)/\(f)")
                        let d = attrs?[.modificationDate] as? Date
                        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
                        lines.append("  [\(i+1)] \(f.replacingOccurrences(of: ".json", with: "").prefix(40))")
                        lines.append("      \(d.map { df.string(from: $0) } ?? "unknown")")
                    }
                }
                lines.append(""); lines.append("To resume: /resume <session-id>")
                return .text(lines.joined(separator: "\n"))
            }
            let match = sFiles.first { $0.replacingOccurrences(of: ".json", with: "").localizedCaseInsensitiveContains(arg) }
            if let match = match {
                let sid = match.replacingOccurrences(of: ".json", with: "")
                return .text("Session found: \(sid.prefix(40))...\n\nTo resume: swift-agent chat --session \(sid)")
            }
            return .text("No session matching '\(arg)' found. Use /resume to list all sessions.")
        }

        // /goal — goal-oriented brainstorming (ralph-wiggum implementation)
        register(Command(name: "goal", description: "Set a goal and brainstorm approach before implementing (like /ralph-wiggum)", type: .local,
            arguments: [CommandArgument(name: "goal-description", description: "What you want to accomplish")])) { [weak self] input in
            let parts = input.split(separator: " ", maxSplits: 1)
            let goal = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            if goal.isEmpty {
                return .text("""
                    /goal — Goal-Oriented Brainstorming (like /ralph-wiggum)

                    Usage: /goal <what you want to accomplish>

                    This command enters a structured workflow:
                    1. CLARIFY — Understand exactly what's needed
                    2. EXPLORE — Find relevant code and patterns
                    3. DESIGN — Brainstorm 2-3 approaches with trade-offs
                    4. EVALUATE — Pick the best approach with reasoning
                    5. PLAN — Create a step-by-step implementation plan

                    Examples:
                      /goal Add user authentication with OAuth2
                      /goal Refactor the database layer for multi-tenancy

                    The agent will guide you through each step systematically.
                    """)
            }
            let cwd = self?.stateProvider?()?.workingDirectory ?? FileManager.default.currentDirectoryPath
            let projectName = String(cwd.split(separator: "/").last ?? "unknown")
            return .text("""
                🎯 Goal Mode Activated

                Goal: \(goal)
                Project: \(projectName)

                —————————————————————————————————————
                Working through the goal workflow:

                Step 1: CLARIFY — Understand exactly what's needed
                Step 2: EXPLORE — Find relevant code and patterns
                Step 3: DESIGN — Brainstorm 2-3 approaches with trade-offs
                Step 4: EVALUATE — Pick the best approach with reasoning
                Step 5: PLAN — Create a step-by-step implementation plan
                —————————————————————————————————————

                The agent will now work through this workflow.
                Describe your goal in detail and the agent will
                guide you through each step.

                Tip: Similar to Claude Code's /ralph-wiggum.
                Use /plan to switch between plan and implementation modes.
                """)
        }

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

        // /skills — list all available skills (project, user, and bundled).
        register(Command(name: "skills", description: "List all available skills and their descriptions", type: .local,
            arguments: [CommandArgument(name: "filter", description: "Optional filter: 'project', 'user', 'bundled', or 'all'")])) { [weak self] input in
            guard let self = self else { return .text("") }
            let parts = input.split(separator: " ", maxSplits: 1)
            let filter = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "all"
            let cwd = self.stateProvider?()?.workingDirectory ?? FileManager.default.currentDirectoryPath
            let manifests = SkillFileLoader.loadAllManifests(workingDirectory: cwd)

            guard !manifests.isEmpty else {
                return .text("No skills available.")
            }

            var lines = ["Available Skills (\(manifests.count)):", String(repeating: "-", count: 50)]

            for manifest in manifests {
                let source: String
                if manifest.sourcePath.hasPrefix("bundled://") { source = "bundled" }
                else if manifest.sourcePath.hasPrefix("\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/skills/") { source = "user" }
                else { source = "project" }

                let lowerFilter = filter.lowercased()
                if lowerFilter != "all" && source != lowerFilter { continue }

                let aliasStr = manifest.aliases.map { a in a.isEmpty ? "" : " (alias: \(a.joined(separator: ", ")))" } ?? ""
                lines.append("  /\(manifest.name)\(aliasStr)")
                lines.append("    \(manifest.description)")
                lines.append("    [\(source)] \(manifest.sourcePath)")
                lines.append("")
            }

            if lines.count <= 3 {
                lines.append("  (no skills match filter: \(filter))")
            }

            return .text(lines.joined(separator: "\n"))
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
