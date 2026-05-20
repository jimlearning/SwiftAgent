import Foundation

/// Thread-safe message collector for progress events emitted during tool execution.
/// Used by QueryEngine to safely accumulate progress messages from @Sendable callbacks.
private final class ProgressMessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Message] = []

    func append(_ msg: Message) {
        lock.lock()
        messages.append(msg)
        lock.unlock()
    }

    func drain() -> [Message] {
        lock.lock()
        defer { lock.unlock() }
        let result = messages
        messages = []
        return result
    }
}

/// The core query agent conversation loop engine.
/// Mirrors Claude Code's `query.ts` (1,729 lines) + `QueryEngine.ts` (1,295 lines).
public struct QueryEngine: Sendable {
    private let client: LLMClient
    private let registry: ModelRegistry
    private let toolExecutor: ToolExecutor
    private let contextManager: ContextManager
    private let promptBuilder: SystemPromptBuilder
    /// Optional hook system for lifecycle hooks (Stop, PreToolUse, PostToolUse, etc.).
    /// Matches CC's hook integration in query.ts.
    private let hookSystem: HookSystem?

    public init(
        client: LLMClient,
        registry: ModelRegistry = .shared,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager,
        promptBuilder: SystemPromptBuilder,
        hookSystem: HookSystem? = nil
    ) {
        self.client = client
        self.registry = registry
        self.toolExecutor = toolExecutor
        self.contextManager = contextManager
        self.promptBuilder = promptBuilder
        self.hookSystem = hookSystem
    }

    /// Run a single user turn. Returns the final assistant text output.
    /// - Parameters:
    ///   - userInput: The user's message text.
    ///   - conversation: Current conversation state.
    ///   - state: Application state (settings, tokens, streaming).
    ///   - tools: Optional tool definitions to present to the model.
    ///   - querySource: Origin of this query (REPL, agent, compact, etc.).
    ///                  Matches CC's querySource for analytics and branching.
    public func run(
        userInput: String,
        conversation: Conversation,
        state: AppState,
        tools: [ToolDefinition]? = nil,
        querySource: QuerySource = .repl,
        onEvent: ((StreamingQueryEvent) -> Void)? = nil
    ) async throws -> RunResult {
        await state.startProcessing()
        defer { Task { await state.stopProcessing() } }

        let model = await state.settings.model.modelID
        let maxTokens = await state.settings.maxTokens
        let toolNames = tools?.map(\.name) ?? []
        let systemPrompt = promptBuilder.build(for: conversation, toolNames: Set(toolNames))

        // Build initial messages
        var messages = conversation.messages
        messages.append(Message(type: .user, content: [.text(userInput)]))
        let progressCollector = ProgressMessageCollector()

        _ = registry.effectiveContextWindow(for: model)
        var fullText = ""
        var completedTurns = conversation.turns
        var totalToolCalls = 0

        // Track query chain identity and depth across compactions.
        // Matches CC's queryTracking creation at query.ts line 347-355.
        let queryTracking = QueryChainTracking(chainId: UUID().uuidString, depth: 0)

        // Structured output enforcement tracking.
        // Matches CC's QueryEngine.ts lines 661-673.
        let syntheticOutputToolName = "StructuredOutput"
        let hasStructuredOutputTool = tools?.contains(where: { $0.name == syntheticOutputToolName }) ?? false
        let maxStructuredOutputRetries = Int(ProcessInfo.processInfo.environment["MAX_STRUCTURED_OUTPUT_RETRIES"] ?? "5") ?? 5
        var structuredOutputFromTool: JSONValue? = nil
        let initialStructuredOutputCalls: Int = hasStructuredOutputTool
            ? countStructuredOutputCalls(in: messages, toolName: syntheticOutputToolName)
            : 0

        // Main loop: stream → parse tools → execute → repeat
        while true {
            // Abort check (matches CC's AbortController pattern)
            if Task.isCancelled {
                await state.appendStreamingOutput("\n⏹ Aborted\n")
                break
            }

            // Normalize messages for API (merge consecutive tool results, filter progress)
            let apiMessages = normalizeMessagesForAPI(messages, tools: toolNames)

            // Auto-compact (matches CC's autoCompactIfNeeded + shouldAutoCompact)
            // Uses LLM-based compaction with token threshold detection, circuit breaker,
            // and blocking limit enforcement.
            let tokenCount = contextManager.count(messages: apiMessages)
            let compactor = Compactor(client: client, modelRegistry: registry)
            let tracking = await state.compactionTracking
            if compactor.shouldAutoCompact(tokenCount: tokenCount, model: model) {
                do {
                    if let outcome = try await compactor.autoCompactIfNeeded(
                        messages: apiMessages,
                        model: model,
                        tracking: tracking
                    ) {
                        messages = outcome.newMessages
                        await state.setCompactionTracking(outcome.trackingUpdate)
                        await state.appendStreamingOutput("\n📦 Context compacted (LLM summary) — \(outcome.result.preCompactTokenCount ?? tokenCount) → ~\(outcome.result.truePostCompactTokenCount ?? 0) tokens\n")
                        continue
                    }
                } catch CompactionError.blockingLimit(let count) {
                    await state.appendStreamingOutput("\n⚠️ Context window at blocking limit (\(count) tokens), cannot continue\n")
                    break
                } catch {
                    await state.appendStreamingOutput("\n⚠️ Compaction failed: \(error.localizedDescription)\n")
                    // Fall back to microcompact
                    let compacted = contextManager.microcompact(messages: apiMessages)
                    if compacted.count < apiMessages.count {
                        messages = compacted
                        continue
                    }
                }
            }

            var turnText = ""
            var toolCalls: [(id: String, name: String, input: [String: JSONValue])] = []
            var stopReason: String? = nil

            do {
                let thinking = await state.settings.thinking
                let fallbackModel = await state.settings.fallbackModel
                let stream: AsyncThrowingStream<StreamEvent, Error>
                if let fallback = fallbackModel {
                    stream = client.sendWithRetry(
                        messages: apiMessages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: tools,
                        thinking: thinking,
                        enablePromptCaching: true,
                        options: RetryOptions(
                            model: model,
                            fallbackModel: fallback,
                            thinkingConfig: thinking ?? .disabled,
                            querySource: querySource
                        )
                    )
                } else {
                    stream = client.send(
                        messages: apiMessages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: tools,
                        thinking: thinking,
                        enablePromptCaching: true
                    )
                }

                // Use ContentBlockAccumulator for proper content block state tracking.
                // Matches CC's content block tracking: text/thinking deltas are routed
                // by block index, tool input partial_json is accumulated and parsed at stop.
                var accumulator = ContentBlockAccumulator()

                // Pre-build tool context and progress callback for streaming tool execution.
                // Tools start executing during streaming (content_block_stop) and need
                // these captured before the stream loop.
                let workingDir = FileManager.default.currentDirectoryPath
                let assistantUUID = UUID().uuidString
                let currentMode = await state.permissionMode
                let isBypassAvailable = await state.isAutoModeActive
                let isPlanActive = await state.isPlanModeActive

                let baseContext = ToolUseContext(
                    workingDirectory: workingDir,
                    sessionID: await state.currentSession.id,
                    mode: currentMode,
                    isBypassPermissionsModeAvailable: isBypassAvailable,
                    isAutoModeAvailable: isBypassAvailable,
                    prePlanMode: isPlanActive ? currentMode : nil,
                    messages: messages,
                    tools: toolExecutor.registry.allTools,
                    queryTracking: queryTracking,
                    abortSignal: { Task.isCancelled },
                    mainLoopModel: model,
                    querySource: querySource,
                    permissionPromptHandler: { toolName, toolUseID, decision in
                        // In non-interactive sessions, auto-deny permission prompts.
                        // Matches CC's behavior when no TUI prompt is available.
                        if isBypassAvailable {
                            return .allow
                        }
                        return .deny(reason: "Interactive permission prompts not available in non-TUI mode")
                    }
                )

                let onProgress: ToolCallProgress = { [progressCollector] progress in
                    let progressMsg = createProgressMessage(
                        toolUseID: progress.toolUseID,
                        parentToolUseID: assistantUUID,
                        content: "[progress: \(progress.data.type)]"
                    )
                    progressCollector.append(progressMsg)
                }

                // Streaming tool execution: launch tools during streaming, not after.
                // Matches CC's StreamingToolExecutor — concurrent-safe tools start
                // executing as soon as their content_block_stop fires, so tool work
                // overlaps with model streaming for lower latency.
                struct PendingToolExecution {
                    let index: Int
                    let id: String
                    let name: String
                    let task: Task<ToolResult, Never>
                }
                var pendingExecutions: [PendingToolExecution] = []

                // Signal model streaming started to caller
                onEvent?(.modelStreaming)

                for try await event in stream {
                    // Feed every event to the accumulator for ordered block tracking
                    accumulator.feed(event)

                    switch event {
                    case .textDelta(let text):
                        turnText += text
                        await state.appendStreamingOutput(text)

                    case .contentBlockStart(_, let block):
                        if case .toolUse(_, let id) = block {
                            await state.addToolCall(id)
                        }

                    case .contentBlockStop(let index):
                        // Streaming tool execution: start executing tools as soon as
                        // their tool_use block completes, overlapping with model streaming.
                        // Matches CC's StreamingToolExecutor.content_block_stop handling.
                        if let tool = accumulator.completedToolBlock(at: index),
                           case .object(let inputDict) = tool.input {
                            let toolName = tool.name
                            let toolId = tool.id
                            let task = Task { [toolExecutor, hookSystem] in
                                // PreToolUse hook dispatch — matches CC's runPreToolUseHooks().
                                // Can block, modify input, or allow execution.
                                if let hs = hookSystem {
                                    let hookResult = await hs.dispatch(event: .preToolUse, input: toolName)
                                    switch hookResult {
                                    case .blockingError(let reason):
                                        return ToolResult(content: "PreToolUse hook blocked: \(reason)", isError: true)
                                    case .stop(let reason):
                                        return ToolResult(content: "PreToolUse hook stopped: \(reason)", isError: true)
                                    case .continue, .nonBlockingError, .modify:
                                        break
                                    }
                                }
                                let result = (try? await toolExecutor.execute(
                                    name: toolName,
                                    input: inputDict,
                                    context: baseContext,
                                    onProgress: onProgress
                                )) ?? ToolResult(content: "Failed to execute", isError: true)
                                // PostToolUse / PostToolUseFailure hook dispatch.
                                if let hs = hookSystem {
                                    if result.isError {
                                        let _ = await hs.dispatch(event: .postToolUseFailure, input: toolName)
                                    } else {
                                        let _ = await hs.dispatch(event: .postToolUse, input: toolName)
                                    }
                                }
                                return result
                            }
                            pendingExecutions.append(PendingToolExecution(
                                index: index, id: toolId, name: toolName, task: task
                            ))
                            onEvent?(.toolStarted(toolUseID: toolId, toolName: toolName))
                        }

                    case .messageDelta(let reason, let usage):
                        stopReason = reason
                        if let u = usage {
                            await state.addTokenUsage(input: u.inputTokens, output: u.outputTokens)
                        }

                    case .messageStart(let msg):
                        _ = msg // metadata

                    case .messageStop, .thinkingDelta, .signatureDelta, .inputJSONDelta, .ping:
                        break

                    case .error(let msg):
                        // Cancel pending tool executions on stream error
                        for pe in pendingExecutions { pe.task.cancel() }
                        throw AgentError.llmError(msg)
                    }
                }

                // Build final content blocks from the accumulator.
                let accumulatedBlocks = accumulator.build()
                fullText += turnText

                // Extract tool calls from accumulated blocks (for ordering and history)
                toolCalls = accumulatedBlocks.compactMap { block in
                    if case .toolUse(let id, let name, let input) = block {
                        if case .object(let dict) = input {
                            return (id: id, name: name, input: dict)
                        }
                        return (id: id, name: name, input: [:])
                    }
                    return nil
                }

                // No tool calls → assistant is done.
                if toolCalls.isEmpty {
                    let assistantMsg = createAssistantMessage(
                        content: accumulatedBlocks,
                        model: model,
                        stopReason: stopReason
                    )
                    completedTurns.append(Turn(
                        userMessage: Message(type: .user, content: [.text(userInput)]),
                        assistantMessage: assistantMsg
                    ))
                    break
                }

                // Set up tool result collection
                var toolResultBlocks: [ContentBlock] = []

                for call in toolCalls {
                    await state.addToolCall(call.id)
                }

                // Build ToolUseContext with normalized inputs and tool instances
                // Await all streaming-launched tool executions (matching CC: tools
                // were launched during streaming, now collect results in block order).
                var toolResultsByIndex: [Int: ToolResult] = [:]
                for pe in pendingExecutions {
                    let result = await pe.task.value
                    // Find the matching tool call index by id
                    if let matchIdx = toolCalls.firstIndex(where: { $0.id == pe.id }) {
                        toolResultsByIndex[matchIdx] = result
                    }
                }

                // Assemble results in tool call order (preserves CC's ordered-output guarantee)
                for (i, call) in toolCalls.enumerated() {
                    let result = toolResultsByIndex[i] ?? ToolResult(content: "Error: execution skipped", isError: true)
                    toolResultBlocks.append(.toolResult(toolUseID: call.id, content: .string(result.content), isError: result.isError))

                    // Yield tool result to caller for real-time UI updates.
                    // Matches CC's tool_result yield in the query AsyncGenerator.
                    onEvent?(.toolCompleted(
                        toolUseID: call.id,
                        toolName: call.name,
                        content: result.content,
                        isError: result.isError
                    ))

                    // Capture structured output from StructuredOutput tool calls.
                    // Matches CC's QueryEngine.ts line 837-839: extract structured_output
                    // from StructuredOutput tool attachment data.
                    if call.name == syntheticOutputToolName && !result.isError {
                        if let data = result.content.data(using: .utf8),
                           let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                            structuredOutputFromTool = json
                        }
                    }

                    await state.removeToolCall(call.id)
                    totalToolCalls += 1
                }

                // Drain progress messages into the message stream.
                messages.append(contentsOf: progressCollector.drain())

                // Append assistant message (with tool_use blocks) to conversation history.
                // Matches CC's behavior: the assistant message that triggered tool calls
                // must be part of the message history so the LLM sees its own tool_use blocks.
                let assistantMsg = createAssistantMessage(
                    content: accumulatedBlocks,
                    model: model,
                    stopReason: stopReason,
                    uuid: assistantUUID
                )
                messages.append(assistantMsg)
                completedTurns.append(Turn(
                    userMessage: Message(type: .user, content: [.text(userInput)]),
                    assistantMessage: assistantMsg
                ))

                // Assemble tool result message
                let toolResultMsg = Message(type: .user, content: toolResultBlocks)
                messages.append(toolResultMsg)

                // Yield turn completion to caller for UI updates.
                onEvent?(.turnComplete(turnNumber: completedTurns.count + 1, toolCallCount: toolCalls.count))

                // Check if structured output retry limit exceeded.
                // Matches CC's QueryEngine.ts lines 1004-1048: after user
                // messages (tool results), count SyntheticOutput calls minus
                // initial, compare against MAX_STRUCTURED_OUTPUT_RETRIES.
                if hasStructuredOutputTool {
                    let currentCalls = countStructuredOutputCalls(in: messages, toolName: syntheticOutputToolName)
                    let callsThisQuery = currentCalls - initialStructuredOutputCalls
                    if callsThisQuery >= maxStructuredOutputRetries {
                        await state.appendStreamingOutput("\n⚠️ Max structured output retries exceeded (\(maxStructuredOutputRetries))\n")
                        return RunResult(
                            text: fullText,
                            turns: completedTurns,
                            totalToolCalls: totalToolCalls,
                            tokenUsage: await state.tokenUsage,
                            structuredOutput: structuredOutputFromTool,
                            isErrorMaxStructuredOutputRetries: true
                        )
                    }
                }

                // Dispatch stop hooks after tool results are collected.
                // Matches CC's handleStopHooks() in query.ts — checks whether
                // continuation should be prevented based on hook output.
                // blockingError (exit code 2) prevents continuation and is reported
                // as an error. stop prevents continuation with user-facing reason.
                // nonBlockingError is logged but allows continuation.
                if let hs = hookSystem {
                    let hookResult = await hs.dispatch(event: .stop, input: turnText)
                    switch hookResult {
                    case .blockingError(let reason):
                        await state.appendStreamingOutput("\n🚫 Hook blocked continuation: \(reason)\n")
                        stopReason = "stop_hook_blocking"
                    case .stop(let reason):
                        await state.appendStreamingOutput("\n🛑 Stop hook: \(reason)\n")
                        stopReason = "stop_hook"
                    case .nonBlockingError(let message):
                        await state.appendStreamingOutput("\n⚠️ Hook error (non-blocking): \(message)\n")
                    case .modify, .continue:
                        break
                    }
                }

            } catch {
                // Dispatch stop failure hooks on API errors (rate limit, prompt-too-long,
                // auth failure, etc.). Matches CC's executeStopFailureHooks in query.ts.
                if let hs = hookSystem {
                    let _ = await hs.dispatch(event: .stopFailure, input: error.localizedDescription)
                }
                await state.appendStreamingOutput("\n❌ Error: \(error.localizedDescription)\n")
                throw error
            }

            // If stop was end_turn, stop_hook, or stop_hook_blocking, break
            if stopReason == "end_turn" || stopReason == "stop_hook" || stopReason == "stop_hook_blocking" {
                break
            }
        }

        await state.resetStreamingOutput()

        return RunResult(
            text: fullText,
            turns: completedTurns,
            totalToolCalls: totalToolCalls,
            tokenUsage: await state.tokenUsage,
            structuredOutput: structuredOutputFromTool
        )
    }
}

/// Streaming query events emitted during a query loop.
/// Matches CC's QueryYield events in query.ts — tool results and progress
/// are yielded to the caller as they complete for real-time UI updates.
public enum StreamingQueryEvent: Sendable {
    /// A tool started executing.
    case toolStarted(toolUseID: String, toolName: String)
    /// A tool completed with its result.
    case toolCompleted(toolUseID: String, toolName: String, content: String, isError: Bool)
    /// Progress message from a running tool.
    case toolProgress(toolUseID: String, message: String)
    /// The model started streaming its response.
    case modelStreaming
    /// The query completed a turn (will continue with more tool calls or stop).
    case turnComplete(turnNumber: Int, toolCallCount: Int)
}

public struct RunResult: Sendable {
    public let text: String
    public let turns: [Turn]
    public let totalToolCalls: Int
    public let tokenUsage: Usage
    public let structuredOutput: JSONValue?
    public let isErrorMaxStructuredOutputRetries: Bool

    public init(
        text: String,
        turns: [Turn],
        totalToolCalls: Int,
        tokenUsage: Usage,
        structuredOutput: JSONValue? = nil,
        isErrorMaxStructuredOutputRetries: Bool = false
    ) {
        self.text = text
        self.turns = turns
        self.totalToolCalls = totalToolCalls
        self.tokenUsage = tokenUsage
        self.structuredOutput = structuredOutput
        self.isErrorMaxStructuredOutputRetries = isErrorMaxStructuredOutputRetries
    }
}

/// Counts tool calls to a specific tool name in message history.
/// Matches CC's countToolCalls in utils/messages.ts.
private func countStructuredOutputCalls(in messages: [Message], toolName: String, maxCount: Int? = nil) -> Int {
    var count = 0
    for msg in messages {
        guard msg.type == .assistant else { continue }
        let hasToolUse = msg.content.contains { block in
            if case .toolUse(_, let name, _) = block { return name == toolName }
            return false
        }
        if hasToolUse {
            count += 1
            if let max = maxCount, count >= max { return count }
        }
    }
    return count
}

public enum AgentError: Error {
    case llmError(String)
    case toolError(String)
    case contextExceeded(current: Int, limit: Int)
}

extension JSONValue {
    var jsonString: String {
        if let data = try? JSONEncoder().encode(self),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }
}
