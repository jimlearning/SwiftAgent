import Foundation
import ArgumentParser
import SwiftAgentCore

/// Interactive chat command — the primary interaction mode.
/// Uses a Nanobot-style REPL: colored prompt, spinner while thinking,
/// write-once response panel, readline history.
/// Mutable state for Ctrl+O expand/collapse toggle, shared between
/// the REPL loop and helper methods via reference semantics.
final class ExpandState: Decodable, @unchecked Sendable {
    var expandedGroupIndex: Int? = nil
    var expandedLineCount: Int = 0
}

/// Mutable model reference shared between the agent loop and slash commands.
/// Allows /model to change the model at runtime without restart.
final class SharedModel: @unchecked Sendable {
    var current: String
    init(_ model: String) { self.current = model }
}

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

    /// Tracks Ctrl+O expand/collapse toggle state across the session.
    var expandState = ExpandState()

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

        // Build system prompt once — rebuilding on every API call breaks prompt caching.
        let cachedSystemPrompt = buildSystemPrompt()

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
        let toolDefs = await registry.toolDefinitions()

        let editor = LineEditor()

        // ── Set up inline popup data sources (@ and / completions) ──
        let cwd = FileManager.default.currentDirectoryPath
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
        while true {
            // Drain any keystrokes typed while the model was generating
            renderer.drainTTYInput()

            guard let line = editor.readLine(prompt: "You: ") else { break }

            // Ctrl+O toggles expand/collapse of last group
            if editor.ctrlOTriggered {
                editor.ctrlOTriggered = false
                let didSomething = await handleCtrlO(cache: toolResultCache, capability: capability)
                if !didSomething {
                    // Nothing to show — clean up the extra line from defer's \r\n
                    writeToStdout("\u{001B}[1A")   // move up
                    writeToStdout("\u{001B}[0J")   // clear to end
                }
                continue
            }

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
                // --- Inline agent loop ---
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
                    let stream = client.send(
                        messages: conversationHistory,
                        model: sharedModel.current,
                        systemPrompt: sysPrompt,
                        maxTokens: 16384,
                        tools: toolDefs,
                        betas: [Betas.promptCachingScope, Betas.interleavedThinking]
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

                        case .messageDelta(let reason, let usage):
                            stopReason = reason
                            if let u = usage {
                                sessionState.addTokens(in: u.inputTokens, out: u.outputTokens)
                                cumulativeCacheRead += u.cacheReadInputTokens
                                cumulativeCacheCreation += u.cacheCreationInputTokens
                                cumulativeInputTokens += u.inputTokens
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
                                    let summary = await executeTool(name: call.name, input: call.input, toolUseID: call.id, registry: registry, sessionState: sessionState, currentTool: currentTool, sharedModel: sharedModel)
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
                            conversationHistory.append(Message(type: .user, content: resultBlocks))
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
                                sharedModel: sharedModel
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
                    conversationHistory.append(Message(type: .user, content: resultBlocks))
                    if sentUserMessage { break }
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

            // Display cache hit rate after the response (footnote)
            if cumulativeInputTokens > 0 && !wasCancelled {
                let cacheHitRate = Double(cumulativeCacheRead) / Double(cumulativeInputTokens) * 100.0
                let cacheInfo = String(format: "  ↳ cache: %.0f%% hit (%d read, %d created, %d total in)",
                                       cacheHitRate, cumulativeCacheRead, cumulativeCacheCreation, cumulativeInputTokens)
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
    private func emitBlock(_ text: String) {
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        print(normalized)
    }

    /// Format a tool result as a user-visible summary showing the full command
    /// and at least 3 lines of output before truncation.
    private func toolResultSummary(
        name: String,
        input: [String: JSONValue],
        output: String,
        capability: TerminalCapability
    ) -> String {
        let nameColor = capability.color("  \(name)", color: .brightCyan)
        let dim = capability.color(" → ", color: .brightBlack)
        let cmdStr = formatToolCommand(name: name, input: input, capability: capability)

        var lines: [String] = [nameColor + dim + cmdStr]

        // Show at least 3 lines of output (or all if ≤3)
        let outputLines = output.components(separatedBy: "\n")
        let maxPreview = 3
        let previewCount = min(outputLines.count, maxPreview)

        for i in 0..<previewCount {
            var line = outputLines[i]
            if line.count > 200 {
                line = String(line.prefix(200)) + "..."
            }
            lines.append(capability.color("    \(line)", color: .brightBlack))
        }

        let remaining = outputLines.count - previewCount
        if remaining > 0 {
            lines.append(capability.color(
                "    ... \(remaining) more line\(remaining == 1 ? "" : "s") (\(output.count) total chars)",
                color: .brightBlack
            ))
        }

        return lines.joined(separator: "\n")
    }

    /// Format a tool's input as a readable command string, showing the most
    /// relevant parameter for each tool type.
    private func formatToolCommand(name: String, input: [String: JSONValue], capability: TerminalCapability) -> String {
        switch name {
        case "Bash":
            if case .string(let cmd) = input["command"] { return cmd }

        case "Read":
            if case .string(let path) = input["file_path"] { return path }

        case "Write":
            if case .string(let path) = input["file_path"] { return path }

        case "Edit":
            if case .string(let path) = input["file_path"] { return path }

        case "Glob":
            if case .string(let pattern) = input["pattern"] { return pattern }

        case "Grep":
            var parts: [String] = []
            if case .string(let pattern) = input["pattern"] { parts.append(pattern) }
            if case .string(let path) = input["path"] { parts.append("in \(path)") }
            if !parts.isEmpty { return parts.joined(separator: " ") }

        case "Agent":
            if case .string(let desc) = input["description"] { return desc }

        case "TaskCreate":
            if case .string(let subject) = input["subject"] { return subject }

        case "WebFetch":
            if case .string(let url) = input["url"] { return url }

        case "WebSearch":
            if case .string(let query) = input["query"] { return query }

        default:
            break
        }

        // Generic: compact key=value representation
        return formatGenericInput(input)
    }

    /// Compact formatting for tools without a dedicated command formatter.
    private func formatGenericInput(_ input: [String: JSONValue]) -> String {
        let parts = input.compactMap { key, value -> String? in
            let valStr: String
            switch value {
            case .string(let s): valStr = s
            case .number(let n): valStr = String(format: "%g", n)
            case .bool(let b): valStr = b ? "true" : "false"
            case .null: return nil
            case .array: valStr = "[...]"
            case .object: valStr = "{...}"
            }
            if valStr.count > 80 { return "\(key): ..." }
            return "\(key): \(valStr)"
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }

    // MARK: - Collapsed tool result display

    /// Groups consecutive collapsible tool results, stores their full output in
    /// the cache, and emits single-line summaries. Non-collapsible results
    /// remain individual summary lines.
    private func emitCollapsedResults(
        results: [ChatToolExecutionResult],
        detector: CollapseDetector,
        formatter: CollapsedSummaryFormatter,
        cache: ToolResultCache
    ) async {
        guard !results.isEmpty else { return }

        // Convert to SingleToolResult for grouping
        let singleResults: [SingleToolResult] = results.map { result in
            SingleToolResult(
                name: result.call.name,
                input: result.call.input,
                output: result.output,
                isCollapsible: CollapseDetector.isCollapsible(
                    name: result.call.name, input: result.call.input
                )
            )
        }

        // Group consecutive collapsible results together.
        // Non-collapsible results get their own group.
        var groups: [[SingleToolResult]] = []
        var buffer: [SingleToolResult] = []

        for r in singleResults {
            if r.isCollapsible {
                buffer.append(r)
            } else {
                if !buffer.isEmpty {
                    groups.append(buffer)
                    buffer = []
                }
                groups.append([r])
            }
        }
        if !buffer.isEmpty {
            groups.append(buffer)
        }

        // Clear the spinner line before rendering results. The spinner writes
        // to whatever line the cursor is on via \r\e[K, but emitBlock moves
        // the cursor down. Without this clear, the old "Running Tool → cmd"
        // text stays visible above the tool result, duplicating the header.
        writeToStdout("\r\u{001B}[K")

        // Store each group in the cache and emit its summary.
        // Single-result groups get a detailed display with content preview;
        // multi-result groups get the aggregated one-line summary.
        for groupResults in groups {
            let storedIndex = await cache.store(results: groupResults)
            let group = CollapsedGroup(
                results: groupResults,
                summaryLine: "",
                refIndex: storedIndex
            )
            if groupResults.count == 1 {
                // Show detailed tool result with content preview
                emitBlock(formatter.formatDetailed(for: group))
            } else {
                // Show aggregated summary for multiple similar tools
                emitBlock(formatter.format(for: group))
            }
        }
    }

    /// Handles Ctrl+O: pure toggle — collapse if something is expanded,
    /// expand the last stored group if nothing is.
    /// - Returns: true if something was expanded or collapsed; false if no-op.
    private func handleCtrlO(
        cache: ToolResultCache,
        capability: TerminalCapability
    ) async -> Bool {
        // If something is currently expanded → just collapse it
        if expandState.expandedGroupIndex != nil {
            collapseExpandedOutput()
            return true
        }
        // Nothing expanded → expand the last stored group
        guard let idx = await cache.lastIndex() else { return false }
        let expanded = await expandCollapsedResult(
            arg: "last", cache: cache, capability: capability,
            clearLinesAbove: 1
        )
        expandState.expandedLineCount = expanded.components(separatedBy: "\n").count + 1
        emitBlock(expanded)
        expandState.expandedGroupIndex = idx
        return true
    }

    /// Removes the expanded output block from the terminal using ANSI
    /// escape codes. After Ctrl+O returns, the cursor is 1 line below
    /// the "You: " prompt (defer's \r\n). We move up to the start of
    /// the expanded block and clear to end of display.
    private func collapseExpandedOutput() {
        guard expandState.expandedLineCount > 0 else { return }
        let n = expandState.expandedLineCount
        // Cursor is n+1 lines below the expanded block start:
        //   n lines of emitBlock output + 1 line from defer's \r\n
        writeToStdout("\u{001B}[\(n + 1)A")
        writeToStdout("\u{001B}[0J")
        expandState.expandedGroupIndex = nil
        expandState.expandedLineCount = 0
    }

    /// Write raw bytes directly to stdout (for ANSI escape codes).
    private func writeToStdout(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        _ = data.withUnsafeBytes { ptr in
            Darwin.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
        }
    }

    /// Expand a previously collapsed tool result group identified by
    /// an index number or the keyword "last".
    private func expandCollapsedResult(
        arg: String,
        cache: ToolResultCache,
        capability: TerminalCapability,
        clearLinesAbove: Int = 0
    ) async -> String {
        let prefix = clearLinesAbove > 0 ? "\u{001B}[\(clearLinesAbove)A\u{001B}[0J" : ""
        let stored: StoredGroup?
        if arg == "last" {
            stored = await cache.last()
        } else if let idx = Int(arg) {
            stored = await cache.get(idx)
        } else {
            return prefix + "Usage: /expand <N> or /expand last"
        }

        guard let stored = stored else {
            return prefix + "No collapsed result found for \"\(arg)\"."
        }

        var output = capability.color(
            "── Expanded group [#\(stored.index)] (\(stored.results.count) tool\(stored.results.count == 1 ? "" : "s")) ──",
            color: .brightBlack
        ) + "\n"

        for result in stored.results {
            let nameColor = capability.color("  \(result.name)", color: .brightCyan)
            let cmd = CollapseDetector.commandSummary(
                name: result.name, input: result.input
            )
            output += nameColor + " → " + cmd + "\n"
            output += capability.color(
                "  " + String(repeating: "─", count: min(capability.columns - 4, 60)),
                color: .brightBlack
            ) + "\n"

            let resultOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if resultOutput.isEmpty {
                output += capability.color("  (empty)", color: .brightBlack) + "\n"
            } else {
                let lines = resultOutput.components(separatedBy: "\n")
                // Show up to 50 lines to avoid overwhelming the terminal
                let showAll = lines.count <= 50
                for (_, line) in lines.prefix(50).enumerated() {
                    let trimmed = line.count > 200 ? String(line.prefix(200)) + "…" : line
                    output += capability.color("  \(trimmed)", color: .brightBlack) + "\n"
                }
                if !showAll {
                    output += capability.color(
                        "  … \(lines.count - 50) more lines",
                        color: .brightBlack
                    ) + "\n"
                }
            }
            output += "\n"
        }

        return prefix + output
    }

    // MARK: - System prompt

    /// Built once per session. Rebuilding on every API call would break prompt caching.
    private func buildSystemPrompt() -> String {
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
        currentTool: CurrentToolTracker? = nil,
        sharedModel: SharedModel
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
            mainLoopModel: sharedModel.current,
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

    /// Outcome of a slash command execution — richer than a simple tuple,
    /// supporting in-place session resume without restarting.
    private enum CommandOutcome {
        case normal(output: String?)
        case exit
        case resume(sessionId: String)
    }

    // MARK: - Interactive session picker

    /// Display an interactive arrow-key menu for selecting a saved session.
    /// Enters raw terminal mode, shows a highlighted list, and returns the
    /// chosen session ID (or nil if cancelled with Esc).
    private func sessionPicker(sessions: [SessionMetadata]) -> String? {
        guard !sessions.isEmpty else { return nil }
        guard isatty(STDIN_FILENO) != 0 else { return nil }

        // Save terminal state and enter raw mode
        var saved = termios()
        tcgetattr(STDIN_FILENO, &saved)
        var raw = saved
        raw.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        raw.c_cflag &= ~tcflag_t(CSIZE | PARENB)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_cc.0 = 1   // VMIN
        raw.c_cc.1 = 0   // VTIME
        tcsetattr(STDIN_FILENO, TCSADRAIN, &raw)

        defer {
            tcsetattr(STDIN_FILENO, TCSADRAIN, &saved)
        }

        // Hide cursor
        writeToStdout("\u{001B}[?25l")
        defer { writeToStdout("\u{001B}[?25h") }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        var selected = 0
        let itemCount = sessions.count
        let linesPerItem = 2  // Each item occupies 2 terminal lines (id line + date line)
        let totalMenuLines = itemCount * linesPerItem

        /// Redraw the full menu. `offset` accounts for the header line.
        func drawMenu() {
            var output = "\r\u{001B}[K"  // clear current line
            output += "\u{001B}[1mSaved Sessions (↑↓ to move, Enter to select, Esc to cancel):\u{001B}[0m\r\n"
            for (i, s) in sessions.enumerated() {
                let prefix = i == selected ? "\u{001B}[7m" : ""
                let suffix = i == selected ? "\u{001B}[0m" : ""
                let idShort = String(s.id.prefix(36))
                let dateStr = df.string(from: s.updatedAt)
                let titleHint = s.title.map { "  \"\($0.prefix(60))\"" } ?? ""
                output += "\r\u{001B}[K"
                output += "\(prefix)  [\(i+1)] \(idShort)\(titleHint)\(suffix)\r\n"
                output += "\r\u{001B}[K"
                output += "\(prefix)      \(dateStr)  ·  \(s.messageCount) msgs\(suffix)\r\n"
            }
            // Move cursor back up to the first item
            output += "\u{001B}[\(totalMenuLines + 1)A"
            writeToStdout(output)
        }

        drawMenu()

        while true {
            guard let byte = readRawByte() else { return nil }

            switch byte {
            case 3:  // Ctrl+C
                writeToStdout("\r\n")
                return nil
            case 10, 13:  // Enter
                let chosen = sessions[selected].id
                // Clear menu area: move to bottom, clear each line
                writeToStdout("\u{001B}[\(totalMenuLines)B")
                for _ in 0..<(totalMenuLines + 1) {
                    writeToStdout("\u{001B}[2K\u{001B}[A")
                }
                writeToStdout("\r\n")
                return chosen
            case 27:  // Escape
                // Check if it's an arrow key sequence
                if let seq = readEscapeSeq() {
                    switch seq {
                    case .up:
                        if selected > 0 {
                            selected -= 1
                            drawMenu()
                        }
                    case .down:
                        if selected < itemCount - 1 {
                            selected += 1
                            drawMenu()
                        }
                    default:
                        break
                    }
                } else {
                    // Bare Escape → cancel
                    writeToStdout("\r\n")
                    return nil
                }
            default:
                break
            }
        }
    }

    private func readRawByte() -> UInt8? {
        var byte: UInt8 = 0
        let n = Darwin.read(STDIN_FILENO, &byte, 1)
        if n <= 0 { return nil }
        return byte
    }

    private func readRawByteWithTimeout(ms: Int32 = 50) -> UInt8? {
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ret = poll(&fds, 1, ms)
        if ret <= 0 { return nil }
        return readRawByte()
    }

    private enum EscapeSeq { case up, down, left, right }

    private func readEscapeSeq() -> EscapeSeq? {
        guard let second = readRawByteWithTimeout() else { return nil }
        if second == 91 {  // '['
            guard let third = readRawByteWithTimeout() else { return nil }
            switch third {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            default: return nil
            }
        }
        return nil
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
        var displayCmd: String?
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
                if let cmd = entry.displayCmd {
                    return entry.status ?? "Running \(entry.name) → \(cmd)"
                }
                return entry.status ?? "Running \(entry.name)..."
            }

            let fragments = active.prefix(3).map { entry in
                if let status = entry.status {
                    return Self.singleLine(status)
                }
                if let cmd = entry.displayCmd {
                    return "\(entry.name) → \(cmd)"
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

    func start(id: String, name: String, displayCmd: String? = nil) {
        lock.withLock {
            entries[id] = Entry(name: name, status: nil, displayCmd: displayCmd)
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
