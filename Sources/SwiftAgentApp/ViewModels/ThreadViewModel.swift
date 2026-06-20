import SwiftUI
import SwiftAgentCore

// MARK: - ThreadState

/// Thread execution state machine.
public enum ThreadState: Equatable, Sendable {
    case idle
    case executing
    case done
    case failed(String)

    /// The composer is never disabled — user can always type and queue messages.
    public var isComposerDisabled: Bool {
        false
    }

    public var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Human-readable status for display.
    public var statusText: String? {
        switch self {
        case .idle: return nil
        case .executing: return nil
        case .done: return nil
        case .failed(let msg): return msg
        }
    }
}

// MARK: - ThreadViewModel

/// View model for a single conversation thread.
/// Manages the agent loop via `AgentSessionManager`, message list,
/// streaming state, and persistence.
@MainActor
public final class ThreadViewModel: ObservableObject, Identifiable {
    public let id: String

    /// The project this thread belongs to (nil for global threads).
    /// Set by AppViewModel at creation and load time. Used to resolve
    /// workingDirectory and for pending-thread promotion.
    public var projectId: String?

    // MARK: - Published state

    @Published public var title: String = "Untitled"
    @Published public var messages: [AgentMessage] = []
    @Published public var state: ThreadState = .idle
    @Published public var selectedModel: String = "claude-sonnet-4-6"
    @Published public var mode: String = "code"
    @Published public var sandboxMode: String = "workspace-write"
    @Published public var executionEnv: String = "local"
    @Published public var updatedAt: Date = Date()
    @Published public var executionStartTime: Date?
    @Published public var thoughtTimeString: String?
    @Published public var hasUnread: Bool = false
    /// Whether reasoning content is expanded (for R1/DeepSeek thinking chains).
    @Published public var reasoningExpanded: Bool = false
    /// Number of user messages queued while agent is running.
    @Published public var queueCount: Int = 0
    /// Counter to throttle persistence of streaming text/thinking deltas.
    private var streamPersistCounter: Int = 0

    // MARK: - Message Pagination

    /// Whether there are more messages in the database beyond what's currently loaded.
    @Published public private(set) var hasMoreMessages: Bool = false

    /// How many messages have been skipped (loaded earlier).
    private var messageOffset: Int = 50

    /// Total message count from the database (updated on load).
    private var totalMessageCount: Int = 0

    // MARK: - Dependencies

    /// The agent session manager (shared across threads).
    private weak var agentSession: AgentSessionManager?

    /// Storage manager for persistence.
    private weak var storageManager: StorageManager?

    /// Working directory resolved from parent project via projectId.
    /// Same logic as TabContentView.currentProjectPath.
    public var workingDirectory: String {
        if let pid = projectId,
           let appVM = appViewModel,
           let project = appVM.projects.first(where: { $0.id == pid }) {
            print("[ThreadVM] workingDirectory: found project path=\(project.path) for projectId=\(pid)")
            return project.path
        }
        print("[ThreadVM] workingDirectory: FALLBACK projectId=\(projectId ?? "nil") appVM=\(appViewModel != nil ? "set" : "nil")")
        return NSHomeDirectory()
    }

    /// Back-reference to AppViewModel for resolving project path.
    weak var appViewModel: AppViewModel?

    // MARK: - Internal

    private var streamingTask: Task<Void, Never>?
    private var thoughtTimer: Timer?
    private var messageQueue: [String] = []
    /// ID of the user message that triggered the current agent run.
    /// Used in handleRunResult to correctly identify the range to replace.
    private var currentRunUserMessageID: String?

    /// Optional callbacks
    public var onStreamComplete: (() -> Void)?
    public var onFirstUserMessage: (() -> Void)?

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        agentSession: AgentSessionManager? = nil,
        storageManager: StorageManager? = nil
    ) {
        self.id = id
        self.agentSession = agentSession
        self.storageManager = storageManager
    }

    public func setAgentSession(_ session: AgentSessionManager?) {
        self.agentSession = session
    }

    /// Update from a persisted thread record.
    public func update(from thread: PersistedThread) {
        self.title = thread.title
        self.mode = thread.mode
        self.sandboxMode = thread.sandboxMode
        self.executionEnv = thread.executionEnv
        self.updatedAt = thread.updatedAt
        self.selectedModel = thread.model
        self.projectId = thread.projectId
    }

    /// Load messages from persisted records.
    public func loadMessages(from persisted: [PersistedMessage]) {
        self.messages = persisted.compactMap { pm in
            guard let role = AgentMessageRole(rawValue: pm.role) else { return nil }
            let blocks: [AgentMessageBlock]
            if let meta = pm.metadata, let decoded = [AgentMessageBlock].fromJSON(meta) {
                blocks = decoded
            } else {
                blocks = [.text(pm.content)]
            }
            return AgentMessage(
                id: pm.id,
                role: role,
                blocks: blocks,
                timestamp: pm.createdAt
            )
        }
    }

    /// Set the total message count and determine if more are available.
    public func setTotalMessageCount(_ count: Int) {
        totalMessageCount = count
        messageOffset = messages.count
        hasMoreMessages = totalMessageCount > messages.count
    }

    /// Load earlier messages from the database in a batch.
    public func loadEarlierMessages(batchSize: Int = 50) {
        guard let storage = storageManager, storage.isReady,
              hasMoreMessages else { return }

        do {
            let earlier = try storage.messageRepo.listByThread(
                threadId: id,
                limit: batchSize,
                offset: messageOffset
            )

            guard !earlier.isEmpty else {
                hasMoreMessages = false
                return
            }

            let newMessages = earlier.compactMap { pm -> AgentMessage? in
                guard let role = AgentMessageRole(rawValue: pm.role) else { return nil }
                let blocks: [AgentMessageBlock]
                if let meta = pm.metadata, let decoded = [AgentMessageBlock].fromJSON(meta) {
                    blocks = decoded
                } else {
                    blocks = [.text(pm.content)]
                }
                return AgentMessage(
                    id: pm.id,
                    role: role,
                    blocks: blocks,
                    timestamp: pm.createdAt
                )
            }

            // Prepend earlier messages
            messages = newMessages + messages
            messageOffset += earlier.count
            hasMoreMessages = messageOffset < totalMessageCount
        } catch {
            print("[ThreadViewModel] Load earlier messages failed: \(error)")
        }
    }

    // MARK: - Persistence helpers

    public var persistedState: String {
        switch state {
        case .idle: return "idle"
        case .executing: return "executing"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    public func persistState() {
        guard let storage = storageManager, storage.isReady else { return }
        do {
            try storage.threadRepo.updateState(id: id, state: persistedState)
        } catch {
            print("[ThreadViewModel] Persist state failed: \(error)")
        }
    }

    public func persistMessage(_ message: PersistedMessage) {
        guard let storage = storageManager, storage.isReady else { return }
        do {
            try storage.messageRepo.append(message)
        } catch {
            print("[ThreadViewModel] Persist message failed: \(error)")
        }
    }

    // MARK: - Send (Agent Loop)

    /// Send a user message and run the full agent loop.
    /// If the agent is already executing, queues the message for later processing.
    public func send(userText: String) {
        let debugger = AgentDebugger.shared

        guard let session = agentSession, session.isBootstrapped else {
            state = .failed("Agent session not ready")
            debugger.logError("Send failed: agent session not ready", category: .lifecycle)
            return
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If agent is running, queue this message
        guard state != .executing else {
            messageQueue.append(trimmed)
            queueCount = messageQueue.count
            print("[AgentLoop] QUEUED depth=\(queueCount) text=\"\(trimmed.truncated(to: 50))\"")
            debugger.logUI("Queued message (depth \(queueCount))", metadata: ["threadId": id])
            // Still add user message to the list so user sees it immediately
            let userMsgID = UUID().uuidString
            messages.append(AgentMessage.user(trimmed, id: userMsgID))
            let blocks: [AgentMessageBlock] = [.text(trimmed)]
            persistMessage(PersistedMessage(id: userMsgID, threadId: id, role: "user", content: trimmed, metadata: blocks.toJSONString()))
            return
        }

        print("[AgentLoop] SEND text=\"\(trimmed.truncated(to: 50))\"")
        debugger.logUI("Send: \"\(trimmed.truncated(to: 50))\"", metadata: ["threadId": id])
        startAgentRun(userText: trimmed)
    }

    /// Actually start the agent loop for the given user text.
    private func startAgentRun(userText trimmed: String) {
        guard let session = agentSession else { return }

        // Add user message
        let userMsgID = UUID().uuidString
        currentRunUserMessageID = userMsgID
        let userMessage = AgentMessage.user(trimmed, id: userMsgID)
        messages.append(userMessage)

        // Persist user message
        let userBlocks: [AgentMessageBlock] = [.text(trimmed)]
        persistMessage(PersistedMessage(
            id: userMsgID,
            threadId: id,
            role: "user",
            content: trimmed,
            metadata: userBlocks.toJSONString()
        ))

        // Promote pending thread
        onFirstUserMessage?()

        // Create assistant placeholder
        let assistantID = UUID().uuidString
        let assistantMessage = AgentMessage.assistantStreaming(id: assistantID)
        messages.append(assistantMessage)

        // Update state — defer to avoid publishing during view updates
        DispatchQueue.main.async { [self] in
            state = .executing
            executionStartTime = Date()
            reasoningExpanded = true
            startThoughtTimer()
            persistState()
        }

        // Auto-title from first message
        if title == "Untitled" || title == "New Chat" {
            let snippet = String(trimmed.prefix(60))
            title = snippet
            _ = try? storageManager?.threadRepo.updateTitle(id: id, title: snippet)
        }

        // Build conversation from current messages
        let conversation = buildConversation()

        // Find project working directory
        let workingDir = workingDirectory
        print("[ThreadVM] send() threadId=\(id) projectId=\(projectId ?? "nil") workingDir=\(workingDir)")

        // Start agent loop
        let runStartTime = CFAbsoluteTimeGetCurrent()
        print("[AgentLoop] RUN_START session.run() — input=\"\(trimmed.truncated(to: 30))\"")
        streamingTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await session.run(
                    userInput: trimmed,
                    conversation: conversation,
                    workingDirectory: workingDir,
                    onEvent: { [weak self] event in
                        Task { @MainActor [weak self] in
                            self?.handleStreamEvent(event, assistantID: assistantID)
                        }
                    }
                )

                // Agent loop completed — finalize
                let runElapsed = (CFAbsoluteTimeGetCurrent() - runStartTime) * 1000
                print("[AgentLoop] RUN_DONE elapsed=\(String(format: "%.0f", runElapsed))ms turnCount=\(result.turns.count) toolCalls=\(result.totalToolCalls)")
                print("[AgentLoop] HANDLE_RESULT starting — messages.count=\(self.messages.count)")
                await MainActor.run {
                    self.handleRunResult(result, assistantID: assistantID)
                }
            } catch {
                let runElapsed = (CFAbsoluteTimeGetCurrent() - runStartTime) * 1000
                if !Task.isCancelled {
                    print("[AgentLoop] RUN_ERROR elapsed=\(String(format: "%.0f", runElapsed))ms error=\(error.localizedDescription)")
                    await MainActor.run {
                        self.handleStreamError(assistantID: assistantID, error: error)
                    }
                } else {
                    print("[AgentLoop] RUN_CANCELLED elapsed=\(String(format: "%.0f", runElapsed))ms")
                    await MainActor.run {
                        self.handleCancellation(assistantID: assistantID)
                    }
                }
            }
        }
    }

    /// Cancel the current agent run and process the next queued message (if any).
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        agentSession?.cancel()
        stopThoughtTimer()
        reasoningExpanded = false
        state = .idle

        // Mark last assistant message as done
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[lastIndex].isStreaming = false
        }

        processNextQueued()
    }

    /// Handle cancellation — agent was interrupted mid-stream.
    private func handleCancellation(assistantID: String) {
        stopThoughtTimer()
        reasoningExpanded = false
        streamingTask = nil
        state = .idle

        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            messages[index].isStreaming = false
            persistMessageWithBlocks(messages[index])
        }

        processNextQueued()
    }

    /// Dequeue and execute the next buffered message, if any.
    private func processNextQueued() {
        guard !messageQueue.isEmpty else { return }
        let next = messageQueue.removeFirst()
        queueCount = messageQueue.count
        startAgentRun(userText: next)
    }

    // MARK: - Stream Event Handling

    private func handleStreamEvent(_ event: StreamingQueryEvent, assistantID: String) {
        let debugger = AgentDebugger.shared
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }

        switch event {
        case .textDelta(let text):
            messages[index].appendText(text)
            streamPersistCounter += 1
            if streamPersistCounter % 5 == 0 {
                persistMessageWithBlocks(messages[index])
            }

        case .thinkingDelta(let text):
            messages[index].appendThinking(text)
            streamPersistCounter += 1
            if streamPersistCounter % 5 == 0 {
                persistMessageWithBlocks(messages[index])
            }

        case .toolStarted(let toolUseID, let toolName, let inputSummary):
            print("[AgentLoop] TOOL_START \(toolName) id=\(toolUseID.prefix(8))")
            debugger.logTool("Tool started: \(toolName)", metadata: ["id": toolUseID, "summary": inputSummary ?? ""])
            messages[index].addToolUse(ToolUseBlock(
                toolUseID: toolUseID,
                toolName: toolName,
                inputSummary: inputSummary ?? toolName,
                inputDetail: "",
                status: .executing
            ))
            persistMessageWithBlocks(messages[index])

        case .toolCompleted(let toolUseID, _, let content, let isError):
            let contentPreview = (content).truncated(to: 60)
            print("[AgentLoop] TOOL_DONE \(isError ? "ERROR" : "OK") id=\(toolUseID.prefix(8)) output=\"\(contentPreview)\"")
            messages[index].updateToolUse(
                toolUseID: toolUseID,
                status: isError ? .error(content) : .completed
            )
            messages[index].addToolResult(ToolResultBlock(
                toolUseID: toolUseID,
                content: content,
                isError: isError
            ))
            persistMessageWithBlocks(messages[index])

        case .turnComplete:
            // Persist intermediate assistant state so multi-turn runs survive crash
            persistMessageWithBlocks(messages[index])

        case .assistantTextStreaming, .modelStreaming, .toolProgress:
            if case .modelStreaming = event {
                streamPersistCounter = 0
            }
            break
        }
    }


    private func handleRunResult(_ result: RunResult, assistantID: String) {
        let debugger = AgentDebugger.shared
        debugger.logLLM("Turn complete", metadata: [
            "turns": "\(result.turns.count)",
            "toolCalls": "\(result.totalToolCalls)",
            "tokensIn": "\(result.tokenUsage.inputTokens)",
            "tokensOut": "\(result.tokenUsage.outputTokens)"
        ])
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }

        // Rebuild the message list from the agent's turns to preserve
        // tool_use blocks, tool results, and thinking in correct order.
        let turnMessages = AgentMessage.fromTurns(result.turns, lastAssistantID: assistantID)
        if !turnMessages.isEmpty {
            // Find the user message that triggered this run, then remove
            // everything from there to the end (assistant placeholder +
            // any stale streaming state). Queued user messages (appended
            // after the placeholder) are NOT removed.
            if let userIdx = messages.firstIndex(where: { $0.id == currentRunUserMessageID }) {
                // Delete only messages from userIdx to end from DB, but
                // BE CAREFUL: only delete the messages that are part of
                // this agent run (user message + assistant + tool results).
                // Queued messages below the assistant have role .user and
                // should be preserved.
                //
                // Strategy: walk forward from userIdx and delete until we
                // hit a user message that is NOT the triggering one (i.e.,
                // a queued message). Then delete the range [userIdx..<cutoff).
                var cutoff = messages.count
                for i in (userIdx + 1)..<messages.count {
                    if messages[i].role == .user && messages[i].id != currentRunUserMessageID {
                        cutoff = i
                        break
                    }
                }
                for i in userIdx..<cutoff {
                    try? storageManager?.messageRepo.deleteById(messages[i].id)
                }
                messages.removeSubrange(userIdx..<cutoff)
            } else {
                try? storageManager?.messageRepo.deleteById(messages[index].id)
                messages.remove(at: index)
            }
            messages.append(contentsOf: turnMessages)

            // Persist every turn message with full block metadata
            for msg in turnMessages {
                persistMessageWithBlocks(msg)
            }
        } else {
            // No turns — just finalize the placeholder
            messages[index].finalize(tokenUsage: result.tokenUsage)
            persistMessageWithBlocks(messages[index])
        }

        state = .done
        reasoningExpanded = false
        stopThoughtTimer()
        streamingTask = nil
        persistState()

        let t0 = CFAbsoluteTimeGetCurrent()
        print("[AgentLoop] HANDLE_RESULT done — calling onStreamComplete (diff refresh)")
        onStreamComplete?()
        let t1 = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[AgentLoop] HANDLE_RESULT onStreamComplete returned in \(String(format: "%.0f", t1))ms")
        processNextQueued()
    }

    private func handleStreamError(assistantID: String, error: Error) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }

        let finalMessage = userFriendlyMessage(for: error)

        messages[index].markFailed(finalMessage)
        state = .failed(finalMessage)
        stopThoughtTimer()
        streamingTask = nil

        persistMessageWithBlocks(messages[index])
        persistState()
        processNextQueued()
    }

    /// Persist an AgentMessage with full block metadata.
    private func persistMessageWithBlocks(_ msg: AgentMessage) {
        guard let storage = storageManager, storage.isReady else { return }
        let pm = PersistedMessage(
            id: msg.id,
            threadId: id,
            role: msg.role.rawValue,
            content: msg.blocks.extractText(),
            metadata: msg.blocks.toJSONString(),
            createdAt: msg.timestamp
        )
        persistMessage(pm)
    }

    private func userFriendlyMessage(for error: Error) -> String {
        // Map URLError codes to actionable messages
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotConnectToHost:
                return "Cannot connect to DeepSeek API. Check your network connection or VPN."
            case NSURLErrorTimedOut:
                return "Request timed out. The server may be busy — try again in a moment."
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Check your network and try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost during request. Check your network stability."
            case NSURLErrorDNSLookupFailed:
                return "Cannot resolve server address. Check DNS or try a different network."
            case NSURLErrorSecureConnectionFailed:
                return "SSL connection failed. Check your system time and certificate settings."
            case NSURLErrorCannotFindHost:
                return "Server not found. Check the API endpoint in Settings."
            default:
                break
            }
        }

        // Map LLMError to user-friendly messages
        if let llmError = error as? LLMError {
            switch llmError {
            case .unauthorized:
                return "API key invalid. Update it in Settings → General."
            case .rateLimited(let retryAfter):
                if let sec = retryAfter { return "Rate limited. Retrying in \(sec)s." }
                return "Too many requests. Please wait before retrying."
            case .overloaded:
                return "Server is overloaded. Try again in a few seconds."
            case .httpError(let status, _),
                 .nonStreamingError(let status, _):
                return "Server returned error \(status). Try again later."
            case .parseError:
                return "Failed to parse server response. Try again."
            case .noData:
                return "Server returned no data. Try again."
            }
        }

        // Fallback: raw localized description
        let desc = error.localizedDescription
        return desc.isEmpty ? "An error occurred" : desc
    }

    // MARK: - Conversation Building

    /// Build a `Conversation` from the current message list.
    private func buildConversation() -> Conversation {
        let coreMessages: [Message] = messages.compactMap { agentMsg in
            let contentBlocks: [ContentBlock] = agentMsg.blocks.compactMap { block in
                switch block {
                case .text(let text):
                    return .text(text)
                case .thinking(let text, _):
                    return .thinking(text)
                case .toolUse(let toolUse):
                    // Round-trip back to ContentBlock.toolUse using stored rawInput
                    if let input = toolUse.rawInput {
                        return .toolUse(id: toolUse.toolUseID, name: toolUse.toolName, input: input)
                    }
                    // No rawInput — reconstruct from detail (best-effort fallback)
                    return .toolUse(id: toolUse.toolUseID, name: toolUse.toolName, input: .object([:]))
                case .toolResult(let result):
                    return .toolResult(
                        toolUseID: result.toolUseID,
                        content: .string(result.content),
                        isError: result.isError
                    )
                case .systemReminder(let text):
                    return .text(text)
                }
            }

            guard !contentBlocks.isEmpty else { return nil }

            let role: MessageRole
            switch agentMsg.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: role = .user
            }

            return Message(
                uuid: agentMsg.id,
                type: role,
                content: contentBlocks,
                timestamp: agentMsg.timestamp,
                usage: agentMsg.tokenUsage
            )
        }

        return Conversation(id: id, flatMessages: coreMessages)
    }

    // MARK: - Thought Timer

    private func startThoughtTimer() {
        stopThoughtTimer()
        thoughtTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateThoughtTime()
            }
        }
    }

    private func stopThoughtTimer() {
        thoughtTimer?.invalidate()
        thoughtTimer = nil
        // Keep thoughtTimeString — toggle UI needs "Thought for Xs" after completion.
    }

    private func updateThoughtTime() {
        guard let start = executionStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        thoughtTimeString = "Thought for \(elapsed)s"
    }

    /// Clean up resources.
    public func cleanup() {
        thoughtTimer?.invalidate()
        thoughtTimer = nil
        streamingTask?.cancel()
        streamingTask = nil
    }
}
