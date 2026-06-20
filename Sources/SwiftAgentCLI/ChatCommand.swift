import Foundation
import Darwin
import ArgumentParser
import SwiftAgentCore

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

    @Option(name: .long, help: "Resume a previous session by ID or partial title")
    var session: String?

    @Flag(name: .shortAndLong, help: "Enable debug logging of all API requests and responses")
    var debug: Bool = false

    @Flag(name: .long, help: "Show model thinking content in dim text")
    var showThinking: Bool = false

    @Option(name: .long, help: "Send a single prompt and exit (non-interactive, automated mode)")
    var prompt: String?

    /// Tracks Ctrl+O expand/collapse toggle state across the session.
    var expandState = ExpandState()

    /// Holds connected MCP clients. Reference type so it can be mutated in run()
    /// without needing struct mutation (same pattern as ExpandState).
    var mcpClientsList = MCPClientsHolder()

    func run() async throws {
        // Capture terminal state before LineEditor puts it in raw mode.
        // promptUserForQuestions needs a fully correct cooked-mode terminal,
        // and OR-ing flags on top of raw mode is fragile (c_cc, ICRNL, etc.).
        var orig = termios()
        tcgetattr(STDIN_FILENO, &orig)
        let originalTermios = SendableTermios(value: orig)

        // Resolve API key
        let resolver = APIKeyResolver()
        let key = apiKey ?? resolver.resolve() ?? ""

        // Mutable model reference — allows /model to change at runtime
        let sharedModel = SharedModel(model)

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
            dl.logInfo("Session started. Model: \(sharedModel.current), Base URL: \(baseURL)")
            emitBlock("Debug logging enabled → \(dl.logFilePath)\n")
        }

        // Set up client and tools
        let client = LLMClient(apiKey: key, baseURL: baseURL, model: sharedModel.current, debugLogger: debugLog)
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

        let editor = LineEditor()

        // Pause the spinner during interactive prompts so its \r\e[K output
        // doesn't clear the user's typed input in cooked terminal mode.
        let spinnerPause = SpinnerPauseFlag()

        // Holds the current escape-watcher Task so the interactive prompt
        // handler can cancel it (preventing stdin stealing) and restart it.
        let currentEscapeTask = EscapeTaskHolder()

        // ── Bootstrap MCP servers ──
        let cwd = FileManager.default.currentDirectoryPath
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let mcpBootstrapper = MCPBootstrapper()
        let mcpToolDefs = await mcpBootstrapper.bootstrap(cwd: cwd, home: homeDir)

        // Register each discovered MCP tool into the ToolRegistry
        for def in mcpToolDefs {
            let parts = def.name.split(separator: "__", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 3, parts[0] == "mcp" {
                let serverName = String(parts[1])
                let toolName = String(parts[2])
                let dynamicTool = DynamicMCPTool(
                    serverName: serverName,
                    toolName: toolName,
                    toolDescription: def.description,
                    inputSchema: def.inputSchema,
                    bootstrapper: mcpBootstrapper
                )
                registry.register(dynamicTool)
            }
        }

        // Store clients in the holder for use in ToolUseContext
        let mcpClientMap = await mcpBootstrapper.clients
        mcpClientsList.clients = Array(mcpClientMap.values)

        // Collect MCP server instructions for system prompt injection
        let mcpInstructions = await mcpBootstrapper.serverInstructions

        // Log MCP startup status
        if !mcpClientMap.isEmpty {
            let serverNames = mcpClientMap.keys.sorted().joined(separator: ", ")
            emitBlock("[bold]MCP:[/] \(mcpToolDefs.count) tools from \(serverNames)")
        }
        let mcpFailures = await mcpBootstrapper.failures
        for (server, error) in mcpFailures {
            emitBlock("[bold]MCP:[/] [yellow]\(server)[/] — \(error)")
        }

        // Refresh toolDefs after MCP registration
        let toolDefs = await registry.toolDefinitions()

        // Build system prompt once — rebuilding on every API call breaks prompt caching.
        // Must happen AFTER MCP bootstrap to include server instructions.
        let toolNames = Set(toolDefs.map { $0.name })
        let cachedSystemPrompt = buildSystemPrompt(model: sharedModel.current, toolNames: toolNames)

        // ── Set up inline popup data sources (@ and / completions) ──
        let sessionStore = SessionStore()  // needed early for SessionDataSource in popup

        // Shared file search index: built once via git ls-files, reused across
        // all @-mention searches so each keystroke is in-memory, not disk I/O.
        let fileSearchIndex = FileSearchIndex()

        // Command completions: built-in slash commands + skills
        var commandEntries: [(name: String, help: String?)] = [
            ("/help",        "Show available commands and their usage"),
            ("/exit",        "Exit the current session"),
            ("/quit",        "Alias for /exit"),
            ("/clear",       "Clear the screen"),
            ("/model",       "Show or change the current model"),
            ("/config",      "Open config panel"),
            ("/memory",      "Edit session memory files"),
            ("/doctor",      "Diagnose and verify installation"),
            ("/cost",        "Show total cost and duration"),
            ("/status",      "Show current session status"),
            ("/compact",     "Compact conversation history"),
            ("/review",      "Review a pull request"),
            ("/diff",        "Show the diff of the current branch"),
            ("/stats",       "Show usage statistics"),
            ("/plan",        "Enable/disable plan mode"),
            ("/resume",      "Resume a previous conversation"),
            ("/goal",        "Goal-oriented brainstorming"),
            ("/mcp",         "Manage MCP server connections"),
            ("/tasks",       "List and manage background tasks"),
            ("/init",        "Initialize project settings"),
            ("/permissions", "View or change permission settings"),
            ("/skills",      "List all available skills"),
            ("/session",     "Show session info"),
            ("/expand",      "Expand a collapsed tool result (e.g. /expand last or /expand 3)"),
        ]

        // Add skills from disk
        let skillManifests = SkillFileLoader.loadAllManifests(workingDirectory: cwd)
        for m in skillManifests {
            commandEntries.append(("/" + m.name, m.description))
        }

        let cmdDataSource = CommandDataSource(commands: commandEntries, argumentHints: [
                "model": "[model-name]",
                "permissions": "[mode]",
                "plan": "[on|off]",
                "memory": "[list|add|forget]",
                "review": "[pr-url-or-number]",
                "diff": "[base-branch]",
                "resume": "[session-id]",
                "mcp": "[action]",
                "tasks": "[action]",
                "goal": "[description]",
                "expand": "[N|last]",
                "config": "[key]",
                "skills": "[filter]"
            ], subOptions: [
                "model": ["default", "deepseek-v4-flash", "deepseek-v4-pro", "gpt-4o", "claude-sonnet-4-6"],
                "permissions": ["default", "acceptEdits", "bypass", "plan", "dontAsk", "auto"],
                "plan": ["on", "off"]
            ])
        cmdDataSource.sessionDataSource = SessionDataSource(store: sessionStore)

        editor.setPopupDataSources(
            slash: cmdDataSource,
            at: FileDataSource(workingDirectory: cwd, index: fileSearchIndex)
        )

        // Session tracking for slash commands (/cost, /status, /stats, etc.)
        let sessionStartTime = Date()
        var sessionId = UUID().uuidString
        let sessionState = SessionState()

        // Conversation history accumulates across turns so the LLM has full context.
        // Each turn appends user message → assistant message(s) → tool results.
        var conversationHistory: [Message] = []

        // If --session flag provided, load the previous session
        if let resumeID = session {
            if let loaded = try? sessionStore.load(resumeID) {
                conversationHistory = loaded.conversation.messages
                sessionId = resumeID
                let msgCount = conversationHistory.count
                let titleSuffix = loaded.title.map { ": \"\($0)\"" } ?? ""
                emitBlock("Resumed session \(resumeID.prefix(8))...\(titleSuffix) (\(msgCount) messages)")
            } else {
                // Try fuzzy match by partial title or ID prefix
                if let match = try? sessionStore.listRecent(limit: 50).first(where: {
                    $0.id.hasPrefix(resumeID) || ($0.title?.localizedCaseInsensitiveContains(resumeID) ?? false)
                }) {
                    if let loaded = try? sessionStore.load(match.id) {
                        conversationHistory = loaded.conversation.messages
                        sessionId = match.id
                        let msgCount = conversationHistory.count
                        emitBlock("Resumed session: \"\(match.title ?? match.id)\" (\(msgCount) messages)")
                    }
                } else {
                    emitBlock("Session '\(resumeID)' not found. Starting fresh.")
                }
            }
        }

        // ── Collapsed tool result tracking ──
        let toolResultCache = ToolResultCache()
        let collapseDetector = CollapseDetector()
        let summaryFormatter = CollapsedSummaryFormatter(capability: capability)


        // Nanobot-style REPL
        /// Thread-safe queue for messages typed during agent execution.
        let lineBuffer = LineBuffer()

        while true {
            // Drain any keystrokes typed while the model was generating
            renderer.drainTTYInput()

            // In non-interactive mode (--prompt), use the provided string.
            // Otherwise read from the terminal editor, unless there are
            // queued messages from background input during agent run.
            let inputLine: String
            if !lineBuffer.isEmpty {
                inputLine = lineBuffer.pop()!
                print("\r\u{001B}[KYou: \(inputLine)")
            } else if let promptArg = self.prompt {
                inputLine = promptArg
                // Echo the prompt so the user sees what was sent
                print("You: \(promptArg)")
            } else {
                guard let l = editor.readLine(prompt: "You: ") else { break }
                inputLine = l
            }

            // Ctrl+O toggles expand/collapse of last group
            if self.prompt == nil, editor.ctrlOTriggered {
                editor.ctrlOTriggered = false
                let didSomething = await handleCtrlO(cache: toolResultCache, capability: capability)
                if !didSomething {
                    // Nothing to show — clean up the extra line from defer's \r\n
                    writeToStdout("\u{001B}[1A")   // move up
                    writeToStdout("\u{001B}[0J")   // clear to end
                }
                continue
            }

            let input = inputLine.trimmingCharacters(in: .whitespacesAndNewlines)
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
                if cmd == "/expand" {
                    let arg = parts.count > 1 ? String(parts[1]) : "last"
                    if arg == "last", let idx = await toolResultCache.lastIndex(),
                       idx == expandState.expandedGroupIndex {
                        // Already expanded — clear the command line
                        writeToStdout("\u{001B}[2A\u{001B}[0J")
                        continue
                    }
                    let expanded = await expandCollapsedResult(
                        arg: arg, cache: toolResultCache, capability: capability,
                        clearLinesAbove: 2
                    )
                    emitBlock(expanded)
                    if arg == "last", let idx = await toolResultCache.lastIndex() {
                        expandState.expandedGroupIndex = idx
                        expandState.expandedLineCount = expanded.components(separatedBy: "\n").count + 1
                    } else if let n = Int(arg) {
                        expandState.expandedGroupIndex = n
                        expandState.expandedLineCount = expanded.components(separatedBy: "\n").count + 1
                    }
                    continue
                }
                // /resume without args → interactive session picker menu
                if cmd == "/resume" && parts.count == 1 {
                    let sessions = (try? sessionStore.listRecent(limit: 20)) ?? []
                    if let picked = sessionPicker(sessions: sessions) {
                        if let loaded = try? sessionStore.load(picked) {
                            conversationHistory = loaded.conversation.messages
                            sessionId = picked
                            let msgCount = conversationHistory.count
                            let titleSuffix = loaded.title.map { ": \"\($0)\"" } ?? ""
                            emitBlock("Resumed session \(picked.prefix(8))...\(titleSuffix) (\(msgCount) messages)")
                        } else {
                            emitBlock("Session '\(picked)' not found on disk.")
                        }
                    }
                    continue
                }
                let outcome = await handleCommand(
                    input, model: sharedModel.current, permission: permission,
                    sessionId: sessionId, startTime: sessionStartTime,
                    tokensIn: sessionState.totalTokensIn, tokensOut: sessionState.totalTokensOut,
                    planActive: sessionState.isPlanModeActive,
                    sharedModel: sharedModel
                )
                switch outcome {
                case .normal(let output):
                    if let output = output {
                        emitBlock(output)
                    }
                case .exit:
                    break  // will exit outer loop
                case .resume(let resumeID):
                    if let loaded = try? sessionStore.load(resumeID) {
                        conversationHistory = loaded.conversation.messages
                        sessionId = resumeID
                        let msgCount = conversationHistory.count
                        let titleSuffix = loaded.title.map { ": \"\($0)\"" } ?? ""
                        emitBlock("Resumed session \(resumeID.prefix(8))...\(titleSuffix) (\(msgCount) messages)")
                    } else {
                        emitBlock("Session '\(resumeID)' not found on disk.")
                    }
                }
                // .exit needs to break the outer while loop
                if case .exit = outcome {
                    break
                }
                continue
            }

            // Handle ! (bang) bash mode — execute command directly without LLM
            if input.hasPrefix("!") {
                let command = String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
                if command.isEmpty { continue }
                let cwd = FileManager.default.currentDirectoryPath
                guard !cwd.isEmpty else { continue }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh", isDirectory: false)
                proc.arguments = ["-c", command]
                proc.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
                proc.environment = ProcessInfo.processInfo.environment
                let outPipe = Pipe(); let errPipe = Pipe()
                proc.standardOutput = outPipe; proc.standardError = errPipe
                try? proc.run()
                proc.waitUntilExit()
                let stdoutData = try? outPipe.fileHandleForReading.readToEnd()
                let stderrData = try? errPipe.fileHandleForReading.readToEnd()
                var output = ""
                if let s = stdoutData.flatMap({ String(data: $0, encoding: .utf8) }), !s.isEmpty { output += s }
                if let s = stderrData.flatMap({ String(data: $0, encoding: .utf8) }), !s.isEmpty {
                    if !output.isEmpty && !output.hasSuffix("\n") { output += "\n" }
                    output += s
                }
                if output.isEmpty { output = "(no output)" }
                if !showThinking { print("") }  // spacing before output
                emitBlock(output.trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }

            // Append user message to conversation history.
            // On the first turn, prepend MCP server instructions as a
            // <system-reminder> block — matching Claude Code's injection
            // mechanism which places MCP instructions in the conversation
            // where the model is forced to attend to them.
            let historyCount = conversationHistory.count

            // On the first turn, inject system-reminder blocks as SEPARATE
            // text content blocks — matching Claude Code's message structure
            // where each <system-reminder> is its own {type: "text", text: "..."}
            // block. This preserves semantic separation for the LLM.
            let userContent: [ContentBlock]
            if historyCount == 0 {
                var blocks: [ContentBlock] = []

                // Block 1: Deferred tools announcement (if any tools are deferred)
                let deferredNames = toolDefs
                    .filter { $0.deferLoading }
                    .map { $0.name }
                if let deferredReminder = buildDeferredToolsReminder(deferredNames: deferredNames) {
                    blocks.append(.text(deferredReminder))
                }

                // Block 2: MCP server instructions (if any)
                if let mcpReminder = buildMcpSystemReminder(instructions: mcpInstructions),
                   !mcpInstructions.isEmpty {
                    blocks.append(.text(mcpReminder))
                }

                // Block 3: CLAUDE.md + project memory + current date
                if let claudeReminder = buildClaudeMdReminder() {
                    blocks.append(.text(claudeReminder))
                }

                // Block 4: User input (always last, separate block)
                blocks.append(.text(input))
                userContent = blocks
            } else {
                userContent = [.text(input)]
            }
            conversationHistory.append(Message(type: .user, content: userContent))

            // Shared cancellation flag: ESC sets it, agent loop checks it
            let isCancelled = AtomicBool()

            // Background line reader — collects full lines during agent execution.
            // Bare ESC → cancel; typed text + Enter → queued message.
            currentEscapeTask.task = Task { [isCancelled, lineBuffer] in
                for await line in editor.backgroundLineReader(onCancel: {
                    isCancelled.value = true
                }) {
                    lineBuffer.push(line)
                }
            }

            // Interactive user input handler for AskUserQuestionTool.
            // Defined inside the while loop so it can cancel/restart the
            // escape-watcher Task. The watcher must be stopped before
            // promptUserForQuestions switches to cooked mode, otherwise
            // its poll()+read() loop steals the user's input byte-by-byte.
            let userInputHandler: UserInputPromptHandler = { [currentEscapeTask, isCancelled] questions in
                spinnerPause.paused = true
                // Cancel the escape watcher so it stops reading stdin, then
                // wait up to 150ms for its 100ms poll() timeout to let it exit.
                currentEscapeTask.task?.cancel()
                try? await Task.sleep(nanoseconds: 150_000_000)
                defer {
                    spinnerPause.paused = false
                    // Restart escape watcher for any remaining LLM rounds
                    currentEscapeTask.task = Task { [isCancelled] in
                        if await editor.interceptEscape() {
                            isCancelled.value = true
                        }
                    }
                }
                var term = originalTermios.value
                return await promptUserForQuestions(questions, originalTermios: &term)
            }

            // Track current tool name for spinner display
            let currentTool = CurrentToolTracker()

            // Spinner runs during the entire agent loop (may involve multiple
            // LLM calls and tool executions)
            let spinnerTask = Task {
                var frame = 0
                while !Task.isCancelled {
                    // Pause spinner during interactive user prompts (AskUserQuestion)
                    // so its \r\e[K output doesn't clear the user's typed input.
                    if spinnerPause.paused {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        continue
                    }
                    // When showing thinking text, pause the spinner so thinking
                    // can render in-place without flicker.
                    if showThinking, currentTool.isThinking {
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
            var cumulativeCacheRead = 0
            var cumulativeCacheCreation = 0
            var cumulativeInputTokens = 0
            let turnStart = Date()

            do {
                // No artificial iteration limit — the model decides when to stop
                // by returning text without tool calls (stop_reason: "end_turn").
                // The user can always ESC to cancel.

                while true {
                    // Check for ESC cancellation before each LLM round
                    if isCancelled.value { wasCancelled = true; break }

                    var turnText = ""
                    var thinkingText = ""
                    var toolInputAccumulator = ChatToolInputAccumulator()
                    var stopReason: String?

                    let sysPrompt = cachedSystemPrompt
                    // Filter tools to match CC's deferred-tool behavior:
                    // Undiscovered deferred tools are REMOVED from the array
                    // (the model cannot call them). Discovered tools are
                    // included with full schemas (deferLoading: false).
                    // Matches CC's claude.ts:1154-1167.
                    let discovered = extractDiscoveredToolNames(messages: conversationHistory)
                    let adjustedToolDefs = filterDeferredTools(toolDefs, discovered: discovered)
                    // Build betas: include advanced-tool-use when deferred tools exist.
                    // CC: "required for defer_loading to be accepted" (claude.ts:1174)
                    var betas = Betas.claudeCodeRequestHeaders
                    let hasDeferred = adjustedToolDefs.contains { $0.deferLoading }
                    if hasDeferred, !betas.contains(Betas.toolSearch1P) { betas.append(Betas.toolSearch1P) }
                    let stream = client.send(
                        messages: conversationHistory,
                        model: sharedModel.current,
                        systemPrompt: sysPrompt,
                        maxTokens: 32000,
                        tools: adjustedToolDefs,
                        thinking: .adaptive,
                        betas: betas
                    )

                    for try await event in stream {
                        // Check for ESC cancellation during stream
                        if isCancelled.value { wasCancelled = true; break }
                        switch event {
                        case .textDelta(let text):
                            if currentTool.isThinking {
                                // End thinking: if we were showing thinking text,
                                // reset dim mode + newline so thinking stays on
                                // screen. Otherwise just clear the spinner.
                                if showThinking {
                                    print("\u{001B}[0m\n")
                                } else {
                                    print("\r\u{001B}[K", terminator: "")
                                }
                                currentTool.isThinking = false
                            }
                            turnText += text

                        case .thinkingDelta(let text):
                            currentTool.isThinking = true
                            thinkingText += text
                            if showThinking {
                                // Stream thinking in dim mode, clearing the spinner
                                // line on first delta. Thinking text stays on screen
                                // after the turn because we emit a reset+newline on
                                // the next textDelta or contentBlockStart.
                                if thinkingText == text {
                                    // First delta: clear spinner, indent, start dim
                                    print("\r\u{001B}[K  \u{001B}[2m\(text)", terminator: "")
                                } else {
                                    print(text, terminator: "")
                                }
                                fflush(stdout)
                            }

                        case .contentBlockStart(_, let block):
                            if currentTool.isThinking {
                                if showThinking {
                                    print("\u{001B}[0m\n")
                                } else {
                                    print("\r\u{001B}[K", terminator: "")
                                }
                                currentTool.isThinking = false
                            }
                            if case .toolUse(let name, let id) = block {
                                toolInputAccumulator.startTool(name: name, id: id)
                                // Suppress SendUserMessage spinner — it's a transparent
                                // delivery mechanism, not a user-facing tool.
                                if name != "SendUserMessage" {
                                    currentTool.name = name
                                }
                            }

                        case .inputJSONDelta(let delta):
                            toolInputAccumulator.appendInputJSONDelta(delta)

                        case .messageStart(let msg):
                            // message_start carries full usage (input_tokens, cache fields)
                            // per Anthropic API. message_delta only has output_tokens.
                            if let u = msg.usage {
                                cumulativeInputTokens = u.inputTokens
                                cumulativeCacheRead = u.cacheReadInputTokens
                                cumulativeCacheCreation = u.cacheCreationInputTokens
                            }

                        case .messageDelta(let reason, let usage):
                            stopReason = reason
                            if let u = usage {
                                sessionState.addTokens(in: u.inputTokens, out: u.outputTokens)
                                // message_delta.usage typically only has output_tokens
                                // per Anthropic API spec. Accumulate defensively.
                                if u.cacheReadInputTokens > 0 {
                                    cumulativeCacheRead += u.cacheReadInputTokens
                                }
                                if u.cacheCreationInputTokens > 0 {
                                    cumulativeCacheCreation += u.cacheCreationInputTokens
                                }
                                if u.inputTokens > 0 {
                                    cumulativeInputTokens += u.inputTokens
                                }
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

                    let toolInputError = toolInputAccumulator.finish(stopReason: stopReason)
                    let toolBlocks = toolInputAccumulator.parsedCalls
                    let wasTruncated = toolInputError != nil || stopReason == "max_tokens"

                    // ── Truncation recovery ──
                    if wasTruncated {
                        if !toolBlocks.isEmpty {
                            var ab: [ContentBlock] = []
                            if !thinkingText.isEmpty { ab.append(.thinking(thinkingText)) }
                            if !turnText.isEmpty { ab.append(.text(turnText)) }
                            for tb in toolBlocks { ab.append(.toolUse(id: tb.id, name: tb.name, input: JSONValue.object(tb.input))) }
                            conversationHistory.append(Message(type: .assistant, content: ab))

                            let results = await ChatToolExecutionScheduler.execute(
                                calls: toolBlocks,
                                isConcurrencySafe: { call in registry.tool(named: call.name)?.isConcurrencySafe(call.input) ?? false },
                                execute: { call in
                                    if call.name != "SendUserMessage" { currentTool.start(id: call.id, name: call.name, displayCmd: formatToolCommand(name: call.name, input: call.input, capability: capability)) }
                                    let summary = await executeTool(name: call.name, input: call.input, toolUseID: call.id, registry: registry, sessionState: sessionState, currentTool: currentTool, sharedModel: sharedModel, userInputPromptHandler: userInputHandler)
                                    if call.name != "SendUserMessage" { currentTool.finish(id: call.id) }
                                    return summary
                                }
                            )
                            var sentUserMessage = false
                            for result in results {
                                if result.call.name == "SendUserMessage", case .string(let msg) = result.call.input["message"] {
                                    responseText = msg
                                    sentUserMessage = true
                                }
                            }
                            if sentUserMessage { break }
                            // Collapse and emit tool results (excluding SendUserMessage)
                            let nonMessageResults = results.filter { $0.call.name != "SendUserMessage" }
                            await emitCollapsedResults(
                                results: nonMessageResults,
                                detector: collapseDetector,
                                formatter: summaryFormatter,
                                cache: toolResultCache
                            )
                            expandState.expandedGroupIndex = nil; expandState.expandedLineCount = 0  // New results → reset expand state
                            let resultBlocks = results.map { result in
                                ContentBlock.toolResult(toolUseID: result.call.id, content: .string(result.output), isError: result.output.hasPrefix("Error:"))
                            }
                            conversationHistory.append(Message(
                                type: .user,
                                content: appendToolResultCacheBreakpointReminder(to: resultBlocks)
                            ))
                        } else if !thinkingText.isEmpty || !turnText.isEmpty {
                            var blocks: [ContentBlock] = []
                            if !thinkingText.isEmpty { blocks.append(.thinking(thinkingText)) }
                            if !turnText.isEmpty { blocks.append(.text(turnText)) }
                            conversationHistory.append(Message(type: .assistant, content: blocks))
                        }
                        let hint = toolInputError?.message ?? "Output truncated by token limit. Please continue."
                        conversationHistory.append(Message(type: .user, content: [.text("[system] \(hint) Continue from where you left off.")]))
                        continue
                    }

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
                            if call.name != "SendUserMessage" { currentTool.start(id: call.id, name: call.name, displayCmd: formatToolCommand(name: call.name, input: call.input, capability: capability)) }
                            let summary = await executeTool(
                                name: call.name,
                                input: call.input,
                                toolUseID: call.id,
                                registry: registry,
                                sessionState: sessionState,
                                currentTool: currentTool,
                                sharedModel: sharedModel,
                                userInputPromptHandler: userInputHandler
                            )
                            if call.name != "SendUserMessage" { currentTool.finish(id: call.id) }
                            return summary
                        }
                    )

                    // Render tool results visible to the user.
                    // SendUserMessage: the model's user-facing response — display
                    // with left-border treatment and break the agent loop (matching
                    // CC's behavior where SendUserMessage terminates the turn).
                    var sentUserMessage = false
                    for result in results {
                        if result.call.name == "SendUserMessage", case .string(let msg) = result.call.input["message"] {
                            responseText = msg
                            sentUserMessage = true
                        }
                    }
                    // Collapse and emit tool results (excluding SendUserMessage)
                    let nonMessageResults = results.filter { $0.call.name != "SendUserMessage" }
                    await emitCollapsedResults(
                        results: nonMessageResults,
                        detector: collapseDetector,
                        formatter: summaryFormatter,
                        cache: toolResultCache
                    )
                    expandState.expandedGroupIndex = nil; expandState.expandedLineCount = 0  // New results → reset expand state

                    let resultBlocks = results.map { result in
                        ContentBlock.toolResult(
                            toolUseID: result.call.id,
                            content: .string(result.output),
                            isError: result.output.hasPrefix("Error:")
                        )
                    }

                    // Send tool results as a user message with tool_result blocks
                    conversationHistory.append(Message(
                        type: .user,
                        content: appendToolResultCacheBreakpointReminder(to: resultBlocks)
                    ))
                    if sentUserMessage { break }
                }

            } catch {
                debugLog?.logError(error)
                responseText = "Error: \(error.localizedDescription)"
            }

            spinnerTask.cancel()
            currentEscapeTask.task?.cancel()
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

            // Display cache hit rate after the response (footnote)
            if cumulativeInputTokens > 0 && !wasCancelled {
                let comparableInputTokens = cumulativeInputTokens + cumulativeCacheRead + cumulativeCacheCreation
                let cacheHitRate = comparableInputTokens > 0
                    ? Double(cumulativeCacheRead) / Double(comparableInputTokens) * 100.0
                    : 0
                let cacheInfo = String(
                    format: "  ↳ cache: %.0f%% hit (%d read, %d created, %d raw in, %d comparable in)",
                    cacheHitRate,
                    cumulativeCacheRead,
                    cumulativeCacheCreation,
                    cumulativeInputTokens,
                    comparableInputTokens
                )
                let elapsed = Date().timeIntervalSince(turnStart)
                let elapsedStr = elapsed < 1.0
                    ? String(format: "%.0fms", elapsed * 1000)
                    : String(format: "%.0fs", elapsed)
                emitBlock(capability.color("\(cacheInfo)  ✻ \(elapsedStr)", color: .brightBlack))
                debugLog?.logUsage(
                    inputTokens: cumulativeInputTokens,
                    outputTokens: sessionState.totalTokensOut,
                    cacheRead: cumulativeCacheRead,
                    cacheCreation: cumulativeCacheCreation
                )
            }

            // In non-interactive mode (--prompt), exit after the first turn.
            // This enables automated cache testing: feed a prompt, let the
            // full agent loop execute, then parse the debug log for metrics.
            if self.prompt != nil { break }
        }

        // Save session before exiting so /resume can find it
        saveSession(history: conversationHistory, id: sessionId, store: sessionStore)

        editor.save()
        // Move cursor up to overwrite the "You: " prompt line, then print goodbye
        print("\u{001B}[1A\u{001B}[2K🐬 See you!")
    }

    // MARK: - Block output

    /// Emit a content block followed by exactly one blank line.
    /// Normalises trailing newlines: ensures exactly one `\n` at end,
    /// then `print` adds a second, producing one blank line after the block.
    func emitBlock(_ text: String) {
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        print(normalized)
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
        currentTool: CurrentToolTracker? = nil,
        sharedModel: SharedModel,
        userInputPromptHandler: UserInputPromptHandler? = nil
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
            mcpClients: mcpClientsList.clients.isEmpty ? nil : mcpClientsList.clients,
            mainLoopModel: sharedModel.current,
            querySource: .repl,
            permissionPromptHandler: { _, _, _ in
                bylassAvailable ? .allow : .deny(reason: "Permission prompts not available in REPL mode")
            },
            userInputPromptHandler: userInputPromptHandler
        )

        // Plan mode state callback — allows EnterPlanMode/ExitPlanMode tools to toggle state
        context.setPlanModeActive = { active in
            sessionState.setPlanModeActive(active)
        }

        // Register agent definitions for AgentTool
        context.agentDefinitions = BuiltInAgents.all.values.map { $0 }

        // Register bundled skills as commands for SkillTool
        context.commands = buildAllSkillCommands(workingDirectory: context.workingDirectory)

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

    /// Build FullCommand wrappers for all skills: project-level, user-level, and bundled.
    /// These are passed to SkillTool via context.commands so the LLM can invoke skills.
    ///
    /// Priority (first-found wins): project > user > bundled.
    /// Project skills from `.claude/skills/`, user skills from `~/.claude/skills/`.
    private func buildAllSkillCommands(workingDirectory: String) -> [any Sendable] {
        // 1. Load merged manifests (project > user > bundled, deduplicated by name)
        let manifests = SkillFileLoader.loadAllManifests(workingDirectory: workingDirectory)

        var commands: [any Sendable] = []

        for manifest in manifests {
            let isFileBased = !manifest.sourcePath.hasPrefix("bundled://")
            let bundledSkill = !isFileBased ? BundledSkills.all.first(where: { $0.name == manifest.name }) : nil

            let base = CommandBase(
                description: manifest.description,
                name: manifest.name,
                aliases: manifest.aliases,
                argumentHint: manifest.argumentHint,
                whenToUse: manifest.whenToUse,
                disableModelInvocation: manifest.disableModelInvocation,
                userInvocable: manifest.userInvocable,
                loadedFrom: isFileBased ? .skills : .bundled
            )

            let promptCmd: PromptCommand

            if isFileBased {
                // File-based skill: use markdown body as the prompt
                let body = manifest.markdownBody
                promptCmd = PromptCommand(
                    progressMessage: "Launching skill: \(manifest.name)...",
                    contentLength: body.count,
                    argNames: nil,
                    allowedTools: manifest.allowedTools,
                    model: manifest.model,
                    source: .userSettings,
                    skillRoot: URL(fileURLWithPath: manifest.sourcePath).deletingLastPathComponent().path,
                    context: manifest.context,
                    agent: manifest.agent,
                    effort: manifest.effort,
                    paths: manifest.paths,
                    getPromptForCommand: { _, _ in [.text(body)] }
                )
            } else if let b = bundledSkill {
                // Bundled skill: use original dynamic getPromptForCommand
                promptCmd = PromptCommand(
                    progressMessage: b.progressMessage,
                    contentLength: b.contentLength,
                    argNames: b.argNames,
                    allowedTools: b.allowedTools,
                    model: b.model,
                    source: .bundled,
                    context: b.context != nil ? (b.context == .fork ? .fork : .inline) : nil,
                    agent: b.agent,
                    effort: b.effort,
                    paths: b.paths,
                    getPromptForCommand: b.getPromptForCommand
                )
            } else {
                // Fallback for bundled manifest without a matching BundledSkill entry
                promptCmd = PromptCommand(
                    progressMessage: "Launching skill: \(manifest.name)...",
                    contentLength: 0,
                    source: .bundled,
                    getPromptForCommand: { _, _ in [.text(manifest.markdownBody)] }
                )
            }

            commands.append(FullCommand(base: base, type: .prompt(promptCmd)))
        }

        return commands
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

    // MARK: - Helpers

    /// Persist the current conversation history to `~/.swift-agent/sessions/<id>.json`.
    /// Derives a title from the first user message.
    private func saveSession(history: [Message], id: String, store: SessionStore) {
        guard !history.isEmpty else { return }
        let title = history
            .first(where: { $0.type == .user })
            .flatMap { msg -> String? in
                for block in msg.content {
                    if case .text(let text) = block {
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { return String(cleaned.prefix(100)) }
                    }
                }
                return nil
            }
        var conv = Conversation()
        conv.flatMessages = history
        let s = Session(id: id, title: title, conversation: conv)
        do { try store.save(s) }
        catch { /* don't block exit on save failure */ }
    }

    private func parsePermissionMode(_ mode: String) -> PermissionMode {
        switch mode {
        case "plan": return .plan
        case "acceptEdits": return .acceptEdits
        case "bypass": return .bypassPermissions
        default: return .default
        }
    }



    private func handleCommand(_ input: String, model: String, permission: String,
                                sessionId: String, startTime: Date,
                                tokensIn: Int, tokensOut: Int, planActive: Bool,
                                sharedModel: SharedModel) async -> CommandOutcome {
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
        registry.onModelChange = { newModel in
            sharedModel.current = newModel
        }
        switch await registry.execute(input: input) {
        case .exit:
            return .exit
        case .text(let output):
            return .normal(output: output)
        case .error(let msg):
            return .normal(output: "Error: \(msg)")
        case .resume(let id):
            return .resume(sessionId: id)
        case .none:
            return .normal(output: "Unknown command: \(input). Type /help for available commands.")
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
        // NOTE: MCPTool (generic meta-tool) is intentionally NOT registered.
        // DynamicMCPTool instances are created per-tool during MCP bootstrap above.
        // Registering MCPTool would give the model a shortcut to bypass individual
        // tool schemas, defeating deferred loading and proper tool selection.
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
        registry.register(SkillTool(knownSkills: SkillFileLoader.allSkillNames(workingDirectory: FileManager.default.currentDirectoryPath)))
        registry.register(ListSkillsTool())
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
