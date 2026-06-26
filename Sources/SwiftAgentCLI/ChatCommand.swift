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

        let baseURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.deepseek.com"

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

        let cwd = FileManager.default.currentDirectoryPath

        // Set up LanguageModelSession with DeepSeek provider
        let taskManager = TaskManager()
        let provider = DeepSeekProvider(
            apiKey: key,
            baseURL: URL(string: baseURL),
            modelID: sharedModel.current
        )
        let memoryStore = try SQLiteMemoryStore()
        let toolEngine = DefaultToolEngine()
        let permissionBridge = AgentPermissionBridge(engine: PermissionEngine())

        // Register all tools from batch registries
        let batch1 = Batch1ToolRegistry.tools(
            workingDirectory: cwd,
            mcpClients: [],
            taskManager: taskManager,
            availableTools: []
        )
        let batch23 = Batch23ToolRegistry.tools(workingDirectory: cwd)
        var toolNames = Set<String>()
        for (tool, metadata) in batch1 + batch23 {
            toolNames.insert(tool.name)
            await toolEngine.register(tool: tool, metadata: metadata)
        }

        let systemPrompt = SystemPromptBuilder.defaultPrompt(
            workingDirectory: cwd,
            toolNames: toolNames,
            model: sharedModel.current
        )

        let agentSession = LanguageModelSessionImpl(
            modelProvider: provider,
            memoryStore: memoryStore,
            permissionEngine: permissionBridge,
            toolEngine: toolEngine,
            systemPrompt: systemPrompt
        )

        let editor = LineEditor()

        // Pause the spinner during interactive prompts so its \r\e[K output
        // doesn't clear the user's typed input in cooked terminal mode.
        let spinnerPause = SpinnerPauseFlag()

        // Holds the current escape-watcher Task so the interactive prompt
        // handler can cancel it (preventing stdin stealing) and restart it.
        let currentEscapeTask = EscapeTaskHolder()

        // ── Bootstrap MCP servers ──
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let mcpBootstrapper = MCPBootstrapper()
        let mcpToolDefs = await mcpBootstrapper.bootstrap(cwd: cwd, home: homeDir)

        // Register each discovered MCP tool into the ToolEngine
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
                await toolEngine.register(tool: dynamicTool, metadata: ToolMetadata(
                    searchHint: "MCP tool \(serverName)",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Calling MCP tool",
                    requiresApproval: true
                ))
            }
        }

        // Store clients in the holder for use in ToolUseContext
        let mcpClientMap = await mcpBootstrapper.clients
        mcpClientsList.clients = Array(mcpClientMap.values)

        // Log MCP startup status
        if !mcpClientMap.isEmpty {
            let serverNames = mcpClientMap.keys.sorted().joined(separator: ", ")
            emitBlock("[bold]MCP:[/] \(mcpToolDefs.count) tools from \(serverNames)")
        }
        let mcpFailures = await mcpBootstrapper.failures
        for (server, error) in mcpFailures {
            emitBlock("[bold]MCP:[/] [yellow]\(server)[/] — \(error)")
        }

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

        // If --session flag provided, print notice (full resume requires memory store integration)
        if let resumeID = session {
            emitBlock("Session resume requested: \(resumeID). Transcript loading from memory store not yet implemented.")
        }

        // ── Collapsed tool result tracking ──
        let toolResultCache = ToolResultCache()


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
                        sessionId = picked
                        emitBlock("Resumed session \(picked.prefix(8))... (transcript restore from memory store pending)")
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
                    sessionId = resumeID
                    emitBlock("Resumed session \(resumeID.prefix(8))... (transcript restore from memory store pending)")
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

            // Shared cancellation flag: ESC sets it, agent loop checks it
            let isCancelled = AtomicBool()

            // Background line reader — collects full lines during agent execution.
            currentEscapeTask.task = Task { [isCancelled, lineBuffer] in
                for await line in editor.backgroundLineReader(onCancel: {
                    isCancelled.value = true
                }) {
                    lineBuffer.push(line)
                }
            }

            // Track current tool name for spinner display
            let currentTool = CurrentToolTracker()

            // Spinner runs during the entire agent stream
            let spinnerTask = Task {
                var frame = 0
                while !Task.isCancelled {
                    if spinnerPause.paused {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        continue
                    }
                    if showThinking, currentTool.isThinking {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    let line: String
                    if let name = currentTool.name {
                        line = "\r\u{001B}[K  \(renderer.spinnerFrame(index: frame)) \(name)"
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

            var wasCancelled = false
            let turnStart = Date()

            var eventRenderer = SessionEventRenderer(
                terminal: renderer,
                theme: theme,
                showThinking: showThinking
            )

            let stream = await agentSession.streamResponse(to: input)

            do {
                for try await event in stream {
                    if isCancelled.value { wasCancelled = true; break }

                    // Update spinner state from tool events
                    switch event {
                    case .toolCallRequested(_, let name, _):
                        if name != "SendUserMessage" {
                            currentTool.name = name
                        }
                    case .toolCallCompleted:
                        currentTool.name = nil
                    case .textDelta:
                        if currentTool.isThinking {
                            if showThinking { print("\u{001B}[0m\n") }
                            else { print("\r\u{001B}[K", terminator: "") }
                            currentTool.isThinking = false
                        }
                    case .thinkingDelta:
                        currentTool.isThinking = true
                    case .turnCompleted(let usage, _):
                        if let u = usage {
                            sessionState.addTokens(in: u.inputTokens, out: u.outputTokens)
                        }
                    case .error:
                        break
                    }

                    eventRenderer.render(event)
                }
            } catch {
                debugLog?.logError(error)
                eventRenderer = SessionEventRenderer(terminal: renderer, theme: theme, showThinking: showThinking)
            }

            spinnerTask.cancel()
            currentEscapeTask.task?.cancel()
            await editor.stopBackgroundReader()

            let responseText = wasCancelled
                ? "(cancelled — press ↑ to recall previous input)"
                : eventRenderer.accumulatedText

            // Display response with left border
            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let rendered = noMarkdown
                    ? renderer.renderLeftBorder(content: trimmed)
                    : markdown.render(trimmed)
                emitBlock(rendered)
            } else if !wasCancelled {
                emitBlock(renderer.renderLeftBorder(content: "(done)"))
            }

            // Display timing
            let elapsed = Date().timeIntervalSince(turnStart)
            let elapsedStr = elapsed < 1.0
                ? String(format: "%.0fms", elapsed * 1000)
                : String(format: "%.0fs", elapsed)
            emitBlock(capability.color("  ✻ \(elapsedStr)", color: .brightBlack))

            // In non-interactive mode (--prompt), exit after the first turn.
            // This enables automated cache testing: feed a prompt, let the
            // full agent loop execute, then parse the debug log for metrics.
            if self.prompt != nil { break }
        }

        // Session persistence handled by SQLiteMemoryStore internally

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

}
