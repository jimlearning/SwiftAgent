import Foundation

// MARK: - CollectingChannel

/// Internal channel that records events locally for the non-streaming `respond(to:)` path.
/// Does NOT yield to a continuation — the agent loop inspects collected events after
/// the executor finishes, then decides whether to re-prompt for tool calls.
private actor CollectingChannel: GenerationChannel {
    private(set) var events: [SessionEvent] = []
    private var isFinished: Bool = false
    private var accumulatedText: String = ""
    private(set) var accumulatedThinking: String = ""
    private(set) var thinkingSignature: String? = nil

    func send(textDelta: String) async {
        guard !isFinished else { return }
        accumulatedText = textDelta
        events.append(.textDelta(accumulatedText))
    }

    func send(thinkingDelta: String) async {
        guard !isFinished else { return }
        accumulatedThinking = thinkingDelta
        events.append(.thinkingDelta(accumulatedThinking))
    }

    func update(thinkingSignature: String) async {
        self.thinkingSignature = thinkingSignature
    }

    func send(toolCallRequest id: String, name: String, input: Data) async {
        guard !isFinished else { return }
        events.append(.toolCallRequested(id: id, name: name, input: input))
    }

    func send(toolCallCompleted id: String, output: ToolOutputValue) async {
        guard !isFinished else { return }
        events.append(.toolCallCompleted(id: id, output: output, isError: false))
    }

    func complete(stopReason: String?, usage: Usage?) async {
        guard !isFinished else { return }
        isFinished = true
        events.append(.turnCompleted(usage: usage, stopReason: stopReason))
    }

    func fail(with error: AgentRuntimeError) async {
        guard !isFinished else { return }
        isFinished = true
        events.append(.error(error))
    }
}

// MARK: - LanguageModelSessionImpl

/// Concrete actor implementation of the LanguageModelSession protocol.
/// Owns the agent loop: prompt → executor → tool-call processing → transcript → memory.
/// Guards against reentrancy, routes all subsystem calls through protocol boundaries,
/// and provides both streaming (ResponseStream) and non-streaming (Response) APIs.
public actor LanguageModelSessionImpl: LanguageModelSession {

    // MARK: - Subsystem Properties (LanguageModelSession conformance)

    public let modelProvider: any LanguageModel
    public let memoryStore: any SessionMemoryStore
    public let permissionEngine: any SessionPermissionEngine
    public let toolEngine: any ToolEngine
    public let contextManager: any SessionContextManager
    public let profileManager: any ProfileManager
    public let graphEngine: (any AgentGraph)?
    public let hookSystem: any SessionHookSystem

    // MARK: - Internal State

    private var transcript: Transcript = Transcript()
    public private(set) var isResponding: Bool = false

    // MARK: - Initialization

    public init(
        modelProvider: any LanguageModel,
        memoryStore: any SessionMemoryStore,
        permissionEngine: any SessionPermissionEngine,
        toolEngine: any ToolEngine,
        contextManager: any SessionContextManager = NoOpSessionContextManager(),
        profileManager: any ProfileManager = NoOpProfileManager(),
        graphEngine: (any AgentGraph)? = nil,
        hookSystem: any SessionHookSystem = NoOpSessionHookSystem(),
        systemPrompt: String? = nil
    ) {
        self.modelProvider = modelProvider
        self.memoryStore = memoryStore
        self.permissionEngine = permissionEngine
        self.toolEngine = toolEngine
        self.contextManager = contextManager
        self.profileManager = profileManager
        self.graphEngine = graphEngine
        self.hookSystem = hookSystem
        if let prompt = systemPrompt, !prompt.isEmpty {
            transcript.entries.append(.instruction(prompt))
        }
    }

    // MARK: - Reentrancy Guard

    /// Assert that no other turn is in progress. Throws rateLimited if concurrent.
    private func assertNotResponding() throws {
        guard !isResponding else {
            throw AgentRuntimeError.rateLimited(.init(retryAfter: nil))
        }
    }

    // MARK: - Tool Execution

    /// Execute a tool by name with permission gating.
    /// Maps tool names to AgentPermission cases — each tool category checks the
    /// appropriate permission instead of everything routing through .runCommands.
    private func executeTool(name: String, input: Data) async throws -> ToolOutputValue {
        // Communication tools — always allowed, no permission check needed.
        if name == "SendUserMessage" || name == "TaskOutput" {
            return try await toolEngine.execute(name: name, input: input)
        }

        let permission = Self.permissionForTool(name)
        let result = try await permissionEngine.check(permission)
        switch result {
        case .allowed:
            break
        case .denied(let reason):
            throw AgentRuntimeError.permissionDenied(
                permission: name,
                reason: reason
            )
        }
        return try await toolEngine.execute(name: name, input: input)
    }

    /// Map a tool name to its AgentPermission category.
    private static func permissionForTool(_ toolName: String) -> AgentPermission {
        switch toolName {
        case "Bash", "PowerShell":
            return .runCommands
        case "Read", "Glob", "Grep":
            return .readFiles(paths: [])
        case "Write", "Edit", "NotebookEdit":
            return .writeFiles(paths: [])
        case "WebFetch", "WebSearch":
            return .network(domains: [])
        case "Delete":
            return .delete
        default:
            // Unknown tools: use a reasonable default based on name convention.
            // Read-only tools default to .readFiles, destructive tools to .writeFiles.
            if toolName.lowercased().contains("read") || toolName.lowercased().contains("get") {
                return .readFiles(paths: [])
            }
            return .runCommands
        }
    }

    // MARK: - respond(to:) — Non-streaming Turn

    /// Run a single conversation turn, returning a Response with transcript,
    /// usage metadata, and stop reason.
    /// Uses CollectingChannel internally — events are inspected locally,
    /// not yielded to a consumer. Tool calls are executed, results appended
    /// to transcript, and the model is re-prompted until no more tools are requested.
    public func respond(to prompt: String) async throws -> Response {
        try assertNotResponding()
        isResponding = true
        defer { isResponding = false }

        transcript.entries.append(.prompt(prompt))
        let toolDefs = await toolEngine.getAllDefinitions()

        var turnComplete = false
        var iterationCount = 0
        let maxIterations = 50
        var responseText = ""
        var thinkingText = ""
        var thinkingSig: String? = nil
        var finalUsage: Usage? = nil
        var finalStopReason: String? = nil

        while !turnComplete && iterationCount < maxIterations {
            iterationCount += 1

            let channel = CollectingChannel()
            let executor = modelProvider.makeExecutor()
            let generationRequest = LanguageModelExecutorGenerationRequest(
                transcript: transcript,
                enabledTools: toolDefs,
                generationOptions: GenerationOptions()
            )
            try await executor.respond(to: generationRequest, streamingInto: channel)

            let events = await channel.events
            var hasToolCalls = false
            thinkingText = await channel.accumulatedThinking
            let rawSig = await channel.thinkingSignature
            thinkingSig = (rawSig?.isEmpty == false) ? rawSig : UUID().uuidString

            // First pass: collect all events, identify tool calls
            var pendingToolCalls: [(id: String, name: String, input: Data)] = []
            var receivedCompletion = false
            for event in events {
                switch event {
                case .textDelta(let text):
                    responseText = text
                case .thinkingDelta:
                    break
                case .toolCallRequested(let id, let name, let input):
                    hasToolCalls = true
                    pendingToolCalls.append((id, name, input))
                case .toolCallCompleted:
                    break
                case .turnCompleted(let usage, let stopReason):
                    finalUsage = usage
                    finalStopReason = stopReason
                    receivedCompletion = true
                case .error(let err):
                    throw err
                }
            }

            // Guard: the SSE stream must include a completion event.
            // Without it, the response was truncated or malformed.
            guard receivedCompletion else {
                throw AgentRuntimeError.invalidResponse(
                    reason: "Model response truncated — no completion event received"
                )
            }

            // Guard: the model must produce some content (text, thinking, or tools).
            // An empty response with end_turn is likely an API error.
            if !hasToolCalls && thinkingText.isEmpty && responseText.isEmpty {
                throw AgentRuntimeError.invalidResponse(
                    reason: "Model returned end_turn with no content (iteration \(iterationCount))"
                )
            }

            // Second pass: flush thinking + text, then ALL tool_calls, then ALL tool_outputs.
            // This keeps the transcript well-formed: one assistant message with all
            // tool_use blocks, followed by one user message with all tool_results.
            // Without batching, each tool_call + tool_output pair creates separate
            // assistant/user messages, which some API endpoints reject.
            if hasToolCalls {
                if !thinkingText.isEmpty {
                    transcript.entries.append(.thinking(thinkingText, signature: thinkingSig))
                    thinkingText = ""
                }
                if !responseText.isEmpty {
                    transcript.entries.append(.response(responseText))
                    responseText = ""
                }
                for call in pendingToolCalls {
                    transcript.entries.append(.toolCall(id: call.id, name: call.name, input: call.input))
                }
                for call in pendingToolCalls {
                    do {
                        let output = try await executeTool(name: call.name, input: call.input)
                        transcript.entries.append(.toolOutput(id: call.id, output: output.stringValue, isError: false))
                    } catch {
                        transcript.entries.append(.toolOutput(id: call.id, output: error.localizedDescription, isError: true))
                    }
                }
            }

            turnComplete = !hasToolCalls
        }

        if !thinkingText.isEmpty {
            transcript.entries.append(.thinking(thinkingText, signature: thinkingSig))
        }
        if !responseText.isEmpty {
            transcript.entries.append(.response(responseText))
        }
        try? await memoryStore.store(key: "latest", namespace: "sessions", value: transcript)
        return Response(transcript: transcript, usage: finalUsage, stopReason: finalStopReason)
    }

    // MARK: - streamResponse(to:) — Streaming Turn

    /// Stream a conversation turn, yielding SessionEvent values progressively.
    /// Returns an AsyncThrowingStream immediately; the agent loop runs in a Task.
    /// Tool calls are yielded to the consumer AND recorded for the loop to execute.
    /// After tool execution, toolCallCompleted is yielded, transcript updated, and
    /// the model is re-prompted with tool results.
    public func streamResponse(to prompt: String) -> ResponseStream {
        // Reentrancy: can't throw from non-throwing function, so return an
        // immediately-failing stream if already responding.
        guard !isResponding else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AgentRuntimeError.rateLimited(.init(retryAfter: nil)))
            }
        }
        isResponding = true

        return AsyncThrowingStream(
            SessionEvent.self,
            bufferingPolicy: .bufferingNewest(10)
        ) { continuation in
            let task = Task { [self] in
                defer { self.isResponding = false }

                do {
                    // Set up turn state
                    await self.transcript.entries.append(.prompt(prompt))
                    let toolDefs = await self.toolEngine.getAllDefinitions()

                    var turnComplete = false
                    var iterationCount = 0
                    let maxIterations = 50

                    while !turnComplete && iterationCount < maxIterations {
                        iterationCount += 1

                        // Create a fresh channel for this executor call.
                        let channel = StreamingGenerationChannel()
                        await channel.setContinuation(continuation)

                        let executor = await self.modelProvider.makeExecutor()
                        let generationRequest = LanguageModelExecutorGenerationRequest(
                            transcript: await self.transcript,
                            enabledTools: toolDefs,
                            generationOptions: GenerationOptions()
                        )
                        try await executor.respond(to: generationRequest, streamingInto: channel)

                        // After executor finishes, check for tool calls.
                        let calls = await channel.recordedToolCalls

                        // Append assistant thinking + response text to transcript.
                        // Must happen before tool-call processing so the transcript
                        // order matches generation order: thinking → text → tools.
                        // Thinking MUST be in the transcript so the API receives it
                        // back on subsequent turns (required by thinking mode).
                        let thinkingText = await channel.accumulatedThinking
                        let rawSig = await channel.thinkingSignature
                        let thinkingSig: String? = (rawSig?.isEmpty == false) ? rawSig : UUID().uuidString
                        if !thinkingText.isEmpty {
                            await self.transcript.entries.append(.thinking(thinkingText, signature: thinkingSig))
                        }
                        let responseText = await channel.accumulatedText
                        if !responseText.isEmpty {
                            await self.transcript.entries.append(.response(responseText))
                        }

                        // Guard 1: If the SSE stream never sent a completion event, the
                        // response was truncated or malformed — fail the stream so the
                        // consumer sees an error instead of a silent hang.
                        let receivedCompletion = await channel.receivedCompletion
                        guard receivedCompletion else {
                            continuation.finish(throwing: AgentRuntimeError.invalidResponse(
                                reason: "Model response truncated — no completion event received"
                            ))
                            return
                        }

                        if calls.isEmpty && thinkingText.isEmpty && responseText.isEmpty {
                            continuation.finish(throwing: AgentRuntimeError.invalidResponse(
                                reason: "Model returned end_turn with no content"
                            ))
                            return
                        }

                        if calls.isEmpty {
                            // No tool calls — turn is complete.
                            turnComplete = true
                        } else {
                            // Tool calls were requested. Batch all tool_calls
                            // into one assistant message FIRST (so thinking stays
                            // in the same content array as ALL tool_use blocks),
                            // then execute and append results in a second pass.
                            for call in calls {
                                await self.transcript.entries.append(
                                    .toolCall(id: call.id, name: call.name, input: call.input)
                                )
                            }
                            for call in calls {
                                do {
                                    let output = try await self.executeTool(name: call.name, input: call.input)
                                    await self.transcript.entries.append(
                                        .toolOutput(id: call.id, output: output.stringValue, isError: false)
                                    )
                                    continuation.yield(
                                        .toolCallCompleted(id: call.id, output: output, isError: false)
                                    )
                                } catch {
                                    let errorMsg = error.localizedDescription
                                    await self.transcript.entries.append(
                                        .toolOutput(id: call.id, output: errorMsg, isError: true)
                                    )
                                    continuation.yield(
                                        .toolCallCompleted(
                                            id: call.id,
                                            output: .string(errorMsg),
                                            isError: true
                                        )
                                    )
                                }
                            }
                            // Loop continues — re-prompt the model with tool results.
                        }
                    }

                    // After turn completes: update memory and finish the stream.
                    try? await self.memoryStore.store(
                        key: "latest", namespace: "sessions",
                        value: await self.transcript
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable reason in
                if case .cancelled = reason {
                    task.cancel()
                }
            }
        }
    }
}
