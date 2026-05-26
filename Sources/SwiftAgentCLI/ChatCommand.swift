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
        let markdown = MarkdownRenderer(capability: capability, theme: theme)

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
        registerBuiltinTools(into: registry)
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
                    if let toolName = currentTool.name {
                        line = "\r\u{001B}[K  \(renderer.spinnerFrame(index: frame)) Running \(toolName)..."
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
                    var toolBlocks: [(name: String, id: String, input: [String: JSONValue])] = []
                    var currentToolName: String = ""
                    var currentToolID: String = ""
                    var currentToolInputJSON: String = ""

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
                                print("\r\u{001B}[K  \u{001B}[2m\(text)", terminator: "")
                                currentTool.isThinking = true
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
                                currentToolName = name
                                currentToolID = id
                                currentToolInputJSON = ""
                                currentTool.name = name
                            }

                        case .inputJSONDelta(let delta):
                            currentToolInputJSON += delta

                        case .messageDelta(_, let usage):
                            if let u = usage {
                                sessionState.addTokens(in: u.inputTokens, out: u.outputTokens)
                            }

                        case .contentBlockStop:
                            if !currentToolInputJSON.isEmpty, !currentToolID.isEmpty {
                                if let data = currentToolInputJSON.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    var input: [String: JSONValue] = [:]
                                    for (k, v) in json {
                                        if let jv = JSONValue.fromAny(v) { input[k] = jv }
                                    }
                                    toolBlocks.append((name: currentToolName, id: currentToolID, input: input))
                                }
                                currentToolInputJSON = ""
                                currentToolID = ""
                                currentTool.name = nil
                            }

                        default:
                            break
                        }
                    }

                    // If stream was interrupted by ESC, break out of agent loop
                    if wasCancelled { break }

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

                    // Execute tools and collect results
                    var resultBlocks: [ContentBlock] = []
                    for tb in toolBlocks {
                        let summary = await executeTool(name: tb.name, input: tb.input, registry: registry, sessionState: sessionState)
                        resultBlocks.append(.toolResult(
                            toolUseID: tb.id,
                            content: .string(summary),
                            isError: summary.hasPrefix("Error:")
                        ))
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
        print("🐬 See you!")
    }

    // MARK: - Block output

    /// Emit a content block followed by exactly one blank line.
    /// Normalises trailing newlines: ensures exactly one `\n` at end,
    /// then `print` adds a second, producing one blank line after the block.
    private func emitBlock(_ text: String) {
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        print(normalized)
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
        registry: ToolRegistry,
        sessionState: SessionState
    ) async -> String {
        let bylassAvailable = permission == "bypass"

        var context = ToolUseContext(
            workingDirectory: FileManager.default.currentDirectoryPath,
            sessionID: "repl",
            mode: sessionState.isPlanModeActive ? .plan : parsePermissionMode(permission),
            isBypassPermissionsModeAvailable: bylassAvailable,
            isAutoModeAvailable: bylassAvailable,
            prePlanMode: sessionState.isPlanModeActive ? .plan : nil,
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
        do {
            let result = try await executor.execute(name: name, input: input, context: context)
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

    private func registerBuiltinTools(into registry: ToolRegistry) {
        let taskManager = TaskManager()

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
        registry.register(AgentTool())
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

/// Thread-safe tracker for the currently executing tool name.
/// Written by the agent loop and read by the spinner Task.
private final class CurrentToolTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _name: String?
    private var _isThinking: Bool = false

    var name: String? {
        get { lock.withLock { _name } }
        set { lock.withLock { _name = newValue } }
    }

    var isThinking: Bool {
        get { lock.withLock { _isThinking } }
        set { lock.withLock { _isThinking = newValue } }
    }
}
