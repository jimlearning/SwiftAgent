import Foundation

// MARK: - CollectingChannel

/// Internal channel that records events locally for the non-streaming `respond(to:)` path.
/// Does NOT yield to a continuation — the agent loop inspects collected events after
/// the executor finishes, then decides whether to re-prompt for tool calls.
private actor CollectingChannel: GenerationChannel {
    private(set) var events: [SessionEvent] = []
    private var isFinished: Bool = false
    private var accumulatedText: String = ""
    private var accumulatedThinking: String = ""

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

// MARK: - AgentRuntimeImpl

/// Concrete actor implementation of the AgentRuntime protocol.
/// Owns the agent loop: prompt → executor → tool-call processing → transcript → memory.
/// Guards against reentrancy, routes all subsystem calls through protocol boundaries,
/// and provides both streaming (AsyncThrowingStream) and non-streaming (Transcript) APIs.
public actor AgentRuntimeImpl: AgentRuntime {

    // MARK: - Subsystem Properties (AgentRuntime conformance)

    public let modelProvider: any LanguageModel
    public let memoryStore: any RuntimeMemoryStore
    public let permissionEngine: any RuntimePermissionEngine
    public let toolEngine: any ToolEngine
    public let contextManager: any RuntimeContextManager
    public let profileManager: any ProfileManager
    public let graphEngine: (any AgentGraph)?
    public let hookSystem: any RuntimeHookSystem

    // MARK: - Internal State

    private var transcript: Transcript = Transcript()
    private var isResponding: Bool = false

    // MARK: - Initialization

    public init(
        modelProvider: any LanguageModel,
        memoryStore: any RuntimeMemoryStore,
        permissionEngine: any RuntimePermissionEngine,
        toolEngine: any ToolEngine,
        contextManager: any RuntimeContextManager = NoOpContextManager(),
        profileManager: any ProfileManager = NoOpProfileManager(),
        graphEngine: (any AgentGraph)? = nil,
        hookSystem: any RuntimeHookSystem = NoOpHookSystem()
    ) {
        self.modelProvider = modelProvider
        self.memoryStore = memoryStore
        self.permissionEngine = permissionEngine
        self.toolEngine = toolEngine
        self.contextManager = contextManager
        self.profileManager = profileManager
        self.graphEngine = graphEngine
        self.hookSystem = hookSystem
    }

    // MARK: - Reentrancy Guard

    /// Assert that no other turn is in progress. Throws rateLimited if concurrent.
    private func assertNotResponding() throws {
        guard !isResponding else {
            throw AgentRuntimeError.rateLimited(retryAfter: nil)
        }
    }

    // MARK: - Tool Execution

    /// Execute a tool by name with permission gating.
    /// Every tool call routes through permissionEngine.check(.runCommands) before execution.
    private func executeTool(name: String, input: Data) async throws -> ToolOutputValue {
        let allowed = try await permissionEngine.check(.runCommands)
        guard allowed else {
            throw AgentRuntimeError.permissionDenied(
                permission: "runCommands",
                reason: "Tool execution blocked by permission engine"
            )
        }
        return try await toolEngine.execute(name: name, input: input)
    }

    // MARK: - respond(to:) — Non-streaming Turn

    /// Run a single conversation turn, returning the updated transcript.
    /// Uses CollectingChannel internally — events are inspected locally,
    /// not yielded to a consumer. Tool calls are executed, results appended
    /// to transcript, and the model is re-prompted until no more tools are requested.
    public func respond(to prompt: String) async throws -> Transcript {
        try assertNotResponding()
        isResponding = true
        defer { isResponding = false }

        transcript.entries.append(.prompt(prompt))
        let toolDefs = await toolEngine.getAllDefinitions()

        var turnComplete = false
        var iterationCount = 0
        let maxIterations = 50
        var responseText = ""

        while !turnComplete && iterationCount < maxIterations {
            iterationCount += 1

            let channel = CollectingChannel()
            let executor = modelProvider.makeExecutor()
            try await executor.respond(
                to: transcript,
                tools: toolDefs,
                options: GenerationOptions(),
                streamingInto: channel
            )

            let events = await channel.events
            var hasToolCalls = false

            for event in events {
                switch event {
                case .textDelta(let text):
                    responseText = text
                case .thinkingDelta:
                    break
                case .toolCallRequested(let id, let name, let input):
                    hasToolCalls = true
                    transcript.entries.append(.toolCall(id: id, name: name, input: input))
                    let output = try await executeTool(name: name, input: input)
                    transcript.entries.append(.toolOutput(id: id, output: output.stringValue, isError: false))
                case .toolCallCompleted:
                    break  // Already handled inline with toolCallRequested
                case .turnCompleted:
                    break  // Loop control uses hasToolCalls, not stop reason
                case .error(let err):
                    throw err
                }
            }

            turnComplete = !hasToolCalls
        }

        if !responseText.isEmpty {
            transcript.entries.append(.response(responseText))
        }
        try? await memoryStore.store(key: "latest", namespace: "sessions", value: transcript)
        return transcript
    }

    // MARK: - streamResponse(to:) — Streaming Turn

    /// Stream a conversation turn, yielding SessionEvent values progressively.
    /// Returns an AsyncThrowingStream immediately; the agent loop runs in a Task.
    /// Tool calls are yielded to the consumer AND recorded for the loop to execute.
    /// After tool execution, toolCallCompleted is yielded, transcript updated, and
    /// the model is re-prompted with tool results.
    public func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error> {
        // Reentrancy: can't throw from non-throwing function, so return an
        // immediately-failing stream if already responding.
        guard !isResponding else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AgentRuntimeError.rateLimited(retryAfter: nil))
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
                        let channel = RuntimeGenerationChannel()
                        await channel.setContinuation(continuation)

                        let executor = await self.modelProvider.makeExecutor()
                        try await executor.respond(
                            to: await self.transcript,
                            tools: toolDefs,
                            options: GenerationOptions(),
                            streamingInto: channel
                        )

                        // After executor finishes, check for tool calls.
                        let calls = await channel.recordedToolCalls

                        if calls.isEmpty {
                            // No tool calls — turn is complete.
                            turnComplete = true
                        } else {
                            // Tool calls were requested. Execute each one,
                            // yield completion events, and append to transcript.
                            for call in calls {
                                await self.transcript.entries.append(
                                    .toolCall(id: call.id, name: call.name, input: call.input)
                                )
                                let output = try await self.executeTool(name: call.name, input: call.input)
                                await self.transcript.entries.append(
                                    .toolOutput(id: call.id, output: output.stringValue, isError: false)
                                )
                                continuation.yield(
                                    .toolCallCompleted(id: call.id, output: output, isError: false)
                                )
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
