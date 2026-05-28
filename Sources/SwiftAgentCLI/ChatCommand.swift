import Foundation
import ArgumentParser
import SwiftAgentCore

/// Interactive chat command — the primary interaction mode.
/// Uses a Nanobot-style REPL: colored prompt, spinner while thinking,
/// write-once response panel, readline history.
struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive AI coding session"
    )

    @Option(name: .long, help: "Model to use (or ANTHROPIC_MODEL env var)")
    var model: String = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"] ?? "deepseek-v4-pro"

    @Option(name: .long, help: "Permission mode: default, plan, acceptEdits, bypass")
    var permission: String = "default"

    @Option(name: .long, help: "API Key (or ANTHROPIC_API_KEY, keychain, ~/.claude.json)")
    var apiKey: String?

    @Flag(name: .long, help: "Disable colors")
    var noColor: Bool = false

    @Flag(name: .long, help: "Disable markdown rendering in responses")
    var noMarkdown: Bool = false

    @Flag(name: .shortAndLong, help: "Enable debug logging of all API requests and responses")
    var debug: Bool = false

    func run() async throws {
        // Resolve API key
        let resolver = APIKeyResolver()
        let key = apiKey ?? resolver.resolve() ?? ""
        if key.isEmpty {
            print("Error: API key not found. SwiftAgent checks the same sources as Claude Code:")
            print("  - ANTHROPIC_API_KEY env var")
            print("  - ANTHROPIC_AUTH_TOKEN env var")
            print("  - macOS keychain (Claude Code)")
            print("  - ~/.claude.json (primaryApiKey)")
            print("Or use --api-key to pass it directly.")
            throw ExitCode.failure
        }

        let baseURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.deepseek.com/anthropic"

        let capability = TerminalCapability()
        let theme: ColorTheme = noColor ? .monochrome : .default
        let renderer = TerminalRenderer(capability: capability, theme: theme)
        let syntaxHighlighter = TreeSitterSyntaxHighlighter()
        let codeTheme: CodeTheme = .monokai
        let markdown = MarkdownRenderer(
            capability: capability,
            theme: theme,
            syntaxHighlighter: syntaxHighlighter,
            codeTheme: codeTheme
        )

        emitBlock(renderer.renderBanner(version: "0.1.0"))
        emitBlock("Type [bold]/help[/] for commands, [bold]/exit[/] to quit.\n")

        // Set up debug logging
        let debugLog: DebugLogger? = debug ? DebugLogger() : nil
        if let dl = debugLog {
            dl.logInfo("Session started. Model: \(model), Base URL: \(baseURL)")
            emitBlock("Debug logging enabled → \(dl.logFilePath)\n")
        }

        // Set up client and tools
        let client = LLMClient(apiKey: key, baseURL: baseURL, model: model, debugLogger: debugLog)
        let registry = ToolRegistry()
        let taskManager = TaskManager()
        let toolExecutor = ToolExecutor(registry: registry)
        let subAgentEngine = QueryEngine(
            client: client,
            toolExecutor: toolExecutor,
            contextManager: ContextManager(),
            promptBuilder: SystemPromptBuilder()
        )
        let subAgentManager = SubAgentManager(engine: subAgentEngine, taskManager: taskManager)
        registerBuiltinTools(into: registry, taskManager: taskManager, subAgentManager: subAgentManager)
        let toolDefs = await registry.toolDefinitions()

        let editor = LineEditor()

        // Session tracking for slash commands (/cost, /status, /stats, etc.)
        let sessionStartTime = Date()
        let sessionId = UUID().uuidString
        let sessionState = SessionState()

        // Conversation history accumulates across turns so the LLM has full context.
        // Each turn appends user message → assistant message(s) → tool results.
        var conversationHistory: [Message] = []

        // Nanobot-style REPL
        while true {
            // Drain any keystrokes typed while the model was generating
            renderer.drainTTYInput()

            guard let line = editor.readLine(prompt: "You: ") else { break }
            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }

            // Handle slash commands
            if input.hasPrefix("/") {
                let parts = input.split(separator: " ", maxSplits: 1)
                let cmd = String(parts[0])
                if cmd == "/exit" || cmd == "/quit" { break }
                if cmd == "/clear" {
                    print(renderer.clearScreen())
                    conversationHistory = []
                    continue
                }
                let (shouldExit, cmdOutput) = await handleCommand(
                    input, model: model, permission: permission,
                    sessionId: sessionId, startTime: sessionStartTime,
                    tokensIn: sessionState.totalTokensIn, tokensOut: sessionState.totalTokensOut,
                    planActive: sessionState.isPlanModeActive
                )
                if let output = cmdOutput {
                    emitBlock(output)
                }
                if shouldExit { break }
                continue
            }

            // Append user message to conversation history
            let historyCount = conversationHistory.count
            conversationHistory.append(Message(type: .user, content: [.text(input)]))

            // Shared cancellation flag: escape watcher sets it, agent loop checks it
            let isCancelled = AtomicBool()

            // Escape watcher — runs in background, sets flag on bare ESC
            let escapeTask = Task { [isCancelled] in
                if await editor.interceptEscape() {
                    isCancelled.value = true
                }
            }

            // Track current tool name for spinner display
            let currentTool = CurrentToolTracker()

            // Spinner runs during the entire agent loop (may involve multiple
            // LLM calls and tool executions)
            let spinnerTask = Task {
                var frame = 0
                while !Task.isCancelled {
                    if currentTool.isThinking {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    let line: String
                    if let display = currentTool.displayLine {
                        line = "\r\u{001B}[K  \(renderer.spinnerFrame(index: frame)) \(display)"
                    } else {
                        line = renderer.renderThinkingLine(frame: frame)
                    }
                    print(line, terminator: "")
                    fflush(stdout)
                    frame += 1
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                print("\r\u{001B}[K", terminator: "")
                fflush(stdout)
            }

            var responseText = ""
            var wasCancelled = false

            do {
                // --- Inline agent loop (ported from TUIApp's submitInput) ---
                let maxIterations = 25
                var iteration = 0

                while iteration < maxIterations {
                    // Check for ESC cancellation before each LLM round
                    if isCancelled.value { wasCancelled = true; break }

                    iteration += 1
                    var turnText = ""
                    var thinkingText = ""
                    var toolInputAccumulator = ChatToolInputAccumulator()
                    var stopReason: String?

                    let sysPrompt = systemPrompt()
                    let stream = client.send(
                        messages: conversationHistory,
                        model: model,
                        systemPrompt: sysPrompt,
                        maxTokens: 8192,
                        tools: toolDefs
                    )

                    for try await event in stream {
                        // Check for ESC cancellation during stream
                        if isCancelled.value { wasCancelled = true; break }
                        switch event {
                        case .textDelta(let text):
                            if currentTool.isThinking {
                                print("\u{001B}[0m\n")  // end dim + blank line separator
                                currentTool.isThinking = false
                            }
                            turnText += text

                        case .thinkingDelta(let text):
                            if !currentTool.isThinking {
                                // First thinking delta: clear spinner and start dim mode
                                currentTool.isThinking = true
                                print("\r\u{001B}[K  \u{001B}[2m\(text)", terminator: "")
                            } else {
                                print(text, terminator: "")
                            }
                            thinkingText += text
                            fflush(stdout)

                        case .contentBlockStart(_, let block):
                            if currentTool.isThinking {
                                print("\u{001B}[0m\n")  // end dim + blank line separator
                                currentTool.isThinking = false
                            }
                            if case .toolUse(let name, let id) = block {
                                toolInputAccumulator.startTool(name: name, id: id)
                                currentTool.name = name
                            }

                        case .inputJSONDelta(let delta):
                            toolInputAccumulator.appendInputJSONDelta(delta)

                        case .messageDelta(let reason, let usage):
                            stopReason = reason
                            if let u = usage {
                                sessionState.addTokens(in: u.inputTokens, out: u.outputTokens)
                            }

                        case .contentBlockStop:
                            toolInputAccumulator.stopCurrentBlock()
                            currentTool.name = nil

                        default:
                            break
                        }
                    }

                    // If stream was interrupted by ESC, break out of agent loop
                    if wasCancelled { break }

                    if let toolInputError = toolInputAccumulator.finish(stopReason: stopReason) {
                        responseText = toolInputError.message
                        conversationHistory.append(Message(type: .assistant, content: [.text(responseText)]))
                        break
                    }

                    let toolBlocks = toolInputAccumulator.parsedCalls

                    // No tool calls → model signaled completion
                    if toolBlocks.isEmpty {
                        var blocks: [ContentBlock] = []
                        if !thinkingText.isEmpty { blocks.append(.thinking(thinkingText)) }
                        if !turnText.isEmpty { blocks.append(.text(turnText)) }
                        if !blocks.isEmpty {
                            conversationHistory.append(Message(type: .assistant, content: blocks))
                        } else {
                            conversationHistory.append(Message(type: .assistant, content: [.text("[OK]")]))
                        }
                        responseText = turnText
                        break
                    }

                    // Build assistant message with thinking + tool_use blocks.
                    // Must include thinking block per API requirements (echoed back).
                    var assistantBlocks: [ContentBlock] = []
                    if !thinkingText.isEmpty { assistantBlocks.append(.thinking(thinkingText)) }
                    if !turnText.isEmpty { assistantBlocks.append(.text(turnText)) }
                    for tb in toolBlocks {
                        assistantBlocks.append(.toolUse(id: tb.id, name: tb.name, input: JSONValue.object(tb.input)))
                    }
                    conversationHistory.append(Message(type: .assistant, content: assistantBlocks))

                    // Execute tools and collect results. Consecutive concurrency-safe
                    // tools run in parallel, but non-safe tools preserve serial order.
                    let results = await ChatToolExecutionScheduler.execute(
                        calls: toolBlocks,
                        isConcurrencySafe: { call in
                            registry.tool(named: call.name)?.isConcurrencySafe(call.input) ?? false
                        },
                        execute: { call in
                            currentTool.start(id: call.id, name: call.name)
                            let summary = await executeTool(
                                name: call.name,
                                input: call.input,
                                toolUseID: call.id,
                                registry: registry,
                                sessionState: sessionState,
                                currentTool: currentTool
                            )
                            currentTool.finish(id: call.id)
                            return summary
                        }
                    )

                    // Render tool results visible to the user
                    for result in results {
                        let line = toolResultSummary(name: result.call.name, output: result.output, capability: capability)
                        emitBlock(line)
                    }

                    let resultBlocks = results.map { result in
                        ContentBlock.toolResult(
                            toolUseID: result.call.id,
                            content: .string(result.output),
                            isError: result.output.hasPrefix("Error:")
                        )
                    }

                    // Send tool results as a user message with tool_result blocks
                    conversationHistory.append(Message(type: .user, content: resultBlocks))
                }

                if iteration >= maxIterations {
                    responseText = "(Reached max iterations — task may be incomplete)"
                }
            } catch {
                debugLog?.logError(error)
                responseText = "Error: \(error.localizedDescription)"
            }

            spinnerTask.cancel()
            escapeTask.cancel()
            try? await Task.sleep(nanoseconds: 50_000_000)

            if wasCancelled {
                conversationHistory.removeSubrange(historyCount...)
                responseText = "(cancelled — press ↑ to recall previous input)"
            }

            // Display response with left border
            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let rendered = noMarkdown
                    ? renderer.renderLeftBorder(content: trimmed)
                    : markdown.render(trimmed)
                emitBlock(rendered)
            } else {
                emitBlock(renderer.renderLeftBorder(content: "(done)"))
            }
        }

        editor.save()
        // Move cursor up to overwrite the "You: " prompt line, then print goodbye
        print("\u{001B}[1A\u{001B}[2K🐬 See you!")
    }

    // MARK: - Block output

    /// Emit a content block followed by exactly one blank line.
    /// Normalises trailing newlines: ensures exactly one `\n` at end,
    /// then `print` adds a second, producing one blank line after the block.
    private func emitBlock(_ text: String) {
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        print(normalized)
    }

    /// Format a tool result as a compact user-visible summary line.
    private func toolResultSummary(name: String, output: String, capability: TerminalCapability) -> String {
        let maxLen = 120
        let trimmed: String
        if output.count > maxLen {
            trimmed = String(output.prefix(maxLen)).replacingOccurrences(of: "\n", with: " ")
                + "... (\(output.count) total chars)"
        } else {
            trimmed = output.replacingOccurrences(of: "\n", with: " ")
        }

        let nameColor = capability.color("  \(name)", color: .brightCyan)
        let dim = capability.color(" → ", color: .brightBlack)
        let resultColor = capability.color(trimmed, color: .brightBlack)
        return nameColor + dim + resultColor
    }

    // MARK: - System prompt

    private func systemPrompt() -> String {
        let builder = SystemPromptBuilder()
        return builder.build(for: Conversation())
    }

    // MARK: - Tool execution

    /// Execute a tool by name and return a string result.
    /// Uses ToolExecutor for full permission checking and validation,
    /// falling back to direct Process execution for Bash commands.
    private func executeTool(
        name: String,
        input: [String: JSONValue],
        toolUseID: String,
        registry: ToolRegistry,
        sessionState: SessionState,
        currentTool: CurrentToolTracker? = nil
    ) async -> String {
        let bylassAvailable = permission == "bypass"

        var context = ToolUseContext(
            workingDirectory: FileManager.default.currentDirectoryPath,
            sessionID: "repl",
            toolUseID: toolUseID,
            mode: sessionState.isPlanModeActive ? .plan : parsePermissionMode(permission),
            isBypassPermissionsModeAvailable: bylassAvailable,
            isAutoModeAvailable: bylassAvailable,
            prePlanMode: sessionState.isPlanModeActive ? .plan : nil,
            tools: registry.allTools,
            mainLoopModel: model,
            querySource: .repl,
            permissionPromptHandler: { _, _, _ in
                bylassAvailable ? .allow : .deny(reason: "Permission prompts not available in REPL mode")
            }
        )

        // Plan mode state callback — allows EnterPlanMode/ExitPlanMode tools to toggle state
        context.setPlanModeActive = { active in
            sessionState.setPlanModeActive(active)
        }

        // Register agent definitions for AgentTool
        context.agentDefinitions = BuiltInAgents.all.values.map { $0 }

        // Register bundled skills as commands for SkillTool
        context.commands = buildBundledSkillCommands()

        let executor = ToolExecutor(registry: registry)
        let onProgress: ToolCallProgress = { progress in
            if let agentProgress = progress.data as? AgentToolProgressData {
                currentTool?.update(id: progress.toolUseID, status: agentProgress.message)
            } else if let taskProgress = progress.data as? TaskOutputProgressData {
                currentTool?.update(id: progress.toolUseID, status: Self.formatTaskOutputProgress(taskProgress))
            } else {
                currentTool?.update(id: progress.toolUseID, status: "\(name): \(progress.data.type)")
            }
        }

        do {
            let result = try await executor.execute(name: name, input: input, context: context, onProgress: onProgress)
            return result.content
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Build FullCommand wrappers for all bundled skills.
    /// These are passed to SkillTool via context.commands so the LLM can invoke skills.
    private func buildBundledSkillCommands() -> [any Sendable] {
        BundledSkills.all.map { skill -> FullCommand in
            let base = CommandBase(
                description: skill.description,
                name: skill.name,
                aliases: skill.aliases,
                argumentHint: skill.argumentHint,
                whenToUse: skill.whenToUse,
                disableModelInvocation: skill.disableModelInvocation,
                userInvocable: skill.userInvocable,
                loadedFrom: .bundled
            )
            return FullCommand(
                base: base,
                type: .prompt(PromptCommand(
                    progressMessage: skill.progressMessage,
                    contentLength: skill.contentLength,
                    argNames: skill.argNames,
                    allowedTools: skill.allowedTools,
                    model: skill.model,
                    source: .bundled,
                    context: skill.context != nil ? (skill.context == .fork ? .fork : .inline) : nil,
                    agent: skill.agent,
                    effort: skill.effort,
                    paths: skill.paths,
                    getPromptForCommand: skill.getPromptForCommand
                ))
            )
        }
    }

    static func formatTaskOutputProgress(_ progress: TaskOutputProgressData) -> String {
        let summary = progress.summary
        let label: String
        switch summary.phase {
        case .pending:
            label = "pending"
        case .running:
            label = shortTaskMessage(summary.lastMessage, taskName: summary.taskName)
        case .thinking:
            label = "thinking"
        case .usingTool:
            label = shortTaskMessage(summary.lastMessage, taskName: summary.taskName)
        case .writingResults:
            label = "writing results"
        case .turnComplete:
            label = "turn \(summary.turnCount) complete"
        case .completed:
            label = "done"
        case .failed:
            label = "failed"
        case .killed:
            label = "stopped"
        }
        return "\(summary.taskName): \(label)"
    }

    private static func shortTaskMessage(_ message: String, taskName: String) -> String {
        let prefix = taskName + " "
        let trimmed = message.hasPrefix(prefix) ? String(message.dropFirst(prefix.count)) : message
        return trimmed
    }

/// Thread-safe session state shared between the REPL loop and tool execution.
/// Enables plan mode state changes and token tracking from within tool callbacks.
private final class SessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var _planModeActive = false
    private var _totalTokensIn = 0
    private var _totalTokensOut = 0

    var planModeActive: Bool {
        get { lock.withLock { _planModeActive } }
        set { lock.withLock { _planModeActive = newValue } }
    }

    var totalTokensIn: Int {
        get { lock.withLock { _totalTokensIn } }
        set { lock.withLock { _totalTokensIn = newValue } }
    }

    var totalTokensOut: Int {
        get { lock.withLock { _totalTokensOut } }
        set { lock.withLock { _totalTokensOut = newValue } }
    }

    var isPlanModeActive: Bool { planModeActive }

    func setPlanModeActive(_ active: Bool) {
        planModeActive = active
    }

    func addTokens(in: Int, out: Int) {
        lock.withLock {
            _totalTokensIn += `in`
            _totalTokensOut += out
        }
    }
}

    // MARK: - Helpers

    private func parsePermissionMode(_ mode: String) -> PermissionMode {
        switch mode {
        case "plan": return .plan
        case "acceptEdits": return .acceptEdits
        case "bypass": return .bypassPermissions
        default: return .default
        }
    }

    /// Returns (shouldExit, outputToDisplay).
    private func handleCommand(_ input: String, model: String, permission: String,
                                sessionId: String, startTime: Date,
                                tokensIn: Int, tokensOut: Int, planActive: Bool) async -> (Bool, String?) {
        let registry = CommandRegistry()
        registry.stateProvider = {
            CommandStateProvider(
                currentModel: model,
                permissionMode: permission,
                sessionInfo: .init(
                    sessionId: sessionId,
                    startTime: startTime,
                    tokenUsage: .init(inputTokens: tokensIn, outputTokens: tokensOut)
                ),
                workingDirectory: FileManager.default.currentDirectoryPath,
                planModeActive: planActive,
                totalTokensIn: tokensIn,
                totalTokensOut: tokensOut
            )
        }
        switch await registry.execute(input: input) {
        case .exit:
            return (true, nil)
        case .text(let output):
            return (false, output)
        case .error(let msg):
            return (false, "Error: \(msg)")
        case .none:
            return (false, "Unknown command: \(input). Type /help for available commands.")
        }
    }

    private func registerBuiltinTools(
        into registry: ToolRegistry,
        taskManager: TaskManager,
        subAgentManager: SubAgentManager
    ) {
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileEditTool())
        registry.register(BashTool())
        registry.register(GlobTool())
        registry.register(GrepTool())
        registry.register(WebFetchTool())
        registry.register(WebSearchTool())
        registry.register(TodoWriteTool())
        registry.register(NotebookEditTool())
        registry.register(ConfigTool())
        registry.register(EnterWorktreeTool())
        registry.register(ExitWorktreeTool())
        registry.register(MCPTool())
        registry.register(McpAuthTool())
        registry.register(ListMcpResourcesTool())
        registry.register(ReadMcpResourceTool())
        registry.register(BriefTool())
        registry.register(TaskCreateTool(taskManager: taskManager))
        registry.register(TaskGetTool(taskManager: taskManager))
        registry.register(TaskListTool(taskManager: taskManager))
        registry.register(TaskOutputTool(taskManager: taskManager))
        registry.register(TaskUpdateTool(taskManager: taskManager))
        registry.register(TaskStopTool(taskManager: taskManager))
        registry.register(AgentTool(subAgentManager: subAgentManager))
        registry.register(SkillTool(knownSkills: BundledSkills.all.map { $0.name }))
        registry.register(SendMessageTool())
        registry.register(AskUserQuestionTool())
        registry.register(LSPTool())
        registry.register(EnterPlanModeTool())
        registry.register(ExitPlanModeV2Tool())
        registry.register(CronCreateTool())
        registry.register(CronDeleteTool())
        registry.register(CronListTool())
        registry.register(PowerShellTool())
        registry.register(ToolSearchTool(toolRegistry: registry))
        registry.register(SleepTool())
        registry.register(SyntheticOutputTool())
        registry.register(RemoteTriggerTool())
        registry.register(TeamCreateTool())
        registry.register(TeamDeleteTool())
    }
}

/// Thread-safe tracker for the currently executing tool name.
/// Written by the agent loop and read by the spinner Task.
/// Thread-safe boolean flag for ESC cancellation coordination between Tasks.
private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Thread-safe tracker for currently executing tools.
/// Written by the agent loop and read by the spinner Task.
private final class CurrentToolTracker: @unchecked Sendable {
    private struct Entry {
        let name: String
        var status: String?
    }

    private static let pendingToolID = "__pending_tool__"
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var _isThinking: Bool = false

    var displayLine: String? {
        lock.withLock {
            let active = order.compactMap { id -> Entry? in entries[id] }
            guard !active.isEmpty else { return nil }
            if active.count == 1 {
                let entry = active[0]
                return entry.status ?? "Running \(entry.name)..."
            }

            let fragments = active.prefix(3).map { entry in
                if let status = entry.status {
                    return Self.singleLine(status)
                }
                return "\(entry.name) running"
            }
            let suffix = active.count > 3 ? "; +\(active.count - 3) more" : ""
            let label = active.allSatisfy { $0.name == "TaskOutput" } ? "background tasks" : "tools"
            return "\(active.count) \(label) running | " + fragments.joined(separator: "; ") + suffix
        }
    }

    var name: String? {
        get {
            lock.withLock {
                entries[Self.pendingToolID]?.name
            }
        }
        set {
            lock.withLock {
                if let value = newValue {
                    entries[Self.pendingToolID] = Entry(name: value, status: nil)
                    if !order.contains(Self.pendingToolID) {
                        order.append(Self.pendingToolID)
                    }
                } else {
                    entries[Self.pendingToolID] = nil
                    order.removeAll { $0 == Self.pendingToolID }
                }
            }
        }
    }

    func start(id: String, name: String) {
        lock.withLock {
            entries[id] = Entry(name: name, status: nil)
            if !order.contains(id) {
                order.append(id)
            }
        }
    }

    func update(id: String, status: String) {
        lock.withLock {
            if var entry = entries[id] {
                entry.status = status
                entries[id] = entry
            } else {
                entries[id] = Entry(name: id, status: status)
                order.append(id)
            }
        }
    }

    func finish(id: String) {
        lock.withLock {
            entries[id] = nil
            order.removeAll { $0 == id }
        }
    }

    var isThinking: Bool {
        get { lock.withLock { _isThinking } }
        set { lock.withLock { _isThinking = newValue } }
    }

    private static func singleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
