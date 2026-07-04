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
/// Manages the agent loop via `LanguageModelSessionImpl`, message list,
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
    @Published public var selectedModel: String = "deepseek-v4-pro"
    @Published public var mode: String = "code"
    @Published public var sandboxMode: String = "workspace-write"
    @Published public var executionEnv: String = "local"
    @Published public var updatedAt: Date = Date()
    @Published public var executionStartTime: Date?
    @Published public var thoughtTimeString: String?
    @Published public var hasUnread: Bool = false
    /// Whether reasoning content is expanded (for R1/DeepSeek thinking chains).
    @Published public var reasoningExpanded: Bool = false
    /// Whether the chat scroll position is near the bottom (controls scroll-to-bottom button visibility).
    @Published public var isNearBottom: Bool = true
    /// Number of user messages queued while agent is running.
    @Published public var queueCount: Int = 0
    /// Counter to throttle persistence of streaming text/thinking deltas.
    private var streamPersistCounter: Int = 0
    /// Timestamp when the first thinking delta arrived (for accurate thought duration).
    private var thinkingStartTime: Date?

    // MARK: - Message Pagination

    /// Whether there are more messages in the database beyond what's currently loaded.
    @Published public private(set) var hasMoreMessages: Bool = false

    /// How many messages have been skipped (loaded earlier).
    private var messageOffset: Int = 50

    /// Total message count from the database (updated on load).
    private var totalMessageCount: Int = 0

    // MARK: - Dependencies

    /// The agent runtime session (shared across threads).
    private var session: LanguageModelSessionImpl?

    /// Storage manager for persistence (file-based, CC-compatible).
    private weak var store: SwiftAgentStore?

    /// Working directory resolved from parent project via projectId.
    /// Same logic as TabContentView.currentProjectPath.
    ///
    /// Never silently falls back to NSHomeDirectory() — callers MUST ensure
    /// projectId is set before invoking any persistence path. A nil/missing
    /// projectId here is a bug, not a normal condition.
    public var workingDirectory: String {
        if let pid = projectId,
           let appVM = appViewModel,
           let project = appVM.projects.first(where: { $0.path.lowercased() == pid.lowercased() }) {
            return project.path
        }
        let fallback = NSHomeDirectory()
        print("[ThreadVM] ERROR: workingDirectory FALLBACK — projectId=\(projectId ?? "nil") appVM=\(appViewModel != nil ? "set" : "nil") → returning Home (\(fallback)). THIS IS A BUG.")
        return fallback
    }

    /// Back-reference to AppViewModel for resolving project path.
    weak var appViewModel: AppViewModel?

    // MARK: - Internal

    private var streamingTask: Task<Void, Never>?
    private var thoughtTimer: Timer?
    private var messageQueue: [String] = []
    /// Whether auto-title has already fired for this thread (once per thread lifetime).
    private var hasAutoTitled = false
    /// ID of the user message that triggered the current agent run.
    /// Used in handleRunResult to correctly identify the range to replace.
    private var currentRunUserMessageID: String?
    /// UUID of the last persisted log entry (for parentUuid chaining).
    private var lastPersistedEntryUUID: String?
    /// Git branch name for the current project (lazy, set on first persist).
    private var gitBranch: String?
    /// Current prompt ID (regenerated for each user message).
    private var currentPromptId: String?

    /// Optional callbacks
    public var onStreamComplete: (() -> Void)?
    public var onFirstUserMessage: (() -> Void)?

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        session: LanguageModelSessionImpl? = nil,
        store: SwiftAgentStore? = nil
    ) {
        self.id = id
        self.session = session
        self.store = store
    }

    public func setSession(_ session: LanguageModelSessionImpl?) {
        self.session = session
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

    /// Load earlier messages from the transcript JSONL file.
    public func loadEarlierMessages(batchSize: Int = 50) {
        guard let s = store,
              hasMoreMessages else { return }

        let cwd = projectId ?? workingDirectory
        do {
            let allMessages = try s.readMessages(sessionId: id, projectPath: cwd)
            // For now, load all messages at once (file-based storage is fast enough)
            guard !allMessages.isEmpty else {
                hasMoreMessages = false
                return
            }

            let newMessages = allMessages.compactMap { sm -> AgentMessage? in
                return AgentMessage.fromCore([sm.message]).first
            }

            // Prepend earlier messages
            messages = newMessages + messages
            hasMoreMessages = false // All messages loaded from single JSONL file
        } catch {
            print("[ThreadViewModel] Load earlier messages failed: \(error)")
        }
    }

    /// Load all messages from the JSONL transcript file (called on thread selection).
    public func loadMessagesFromStore() {
        guard let s = store else { return }
        let cwd = projectId ?? workingDirectory
        do {
            let allMessages = try s.readMessages(sessionId: id, projectPath: cwd)
            guard !allMessages.isEmpty else { return }
            let agentMessages = AgentMessage.fromCore(allMessages.map { $0.message })
            let blockSummary = agentMessages.map { am in
                let kinds = am.blocks.map { b -> String in
                    switch b {
                    case .text: return "text"
                    case .thinking: return "think"
                    case .toolUse: return "tool"
                    case .toolResult: return "result"
                    case .systemReminder: return "sys"
                    }
                }
                return "\(am.role):[\(kinds.joined(separator: ","))]"
            }.joined(separator: " | ")
            print("[ThreadVM.load] \(agentMessages.count) msgs: \(blockSummary)")
            self.messages = agentMessages
        } catch {
            print("[ThreadVM.load] FAILED: \(error)")
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
        // No-op: state is tracked in-memory for file-based storage.
    }

    public func persistMessage(_ message: PersistedMessage) {
        // No-op: message persistence handled by persistMessageWithBlocks via store.appendMessage.
    }

    // MARK: - Auto-Title

    /// Set an instant placeholder + fire-and-forget AI title generation.
    /// Matches CC's two-tier approach: regex placeholder → LLM-generated title.
    private func autoTitleFromFirstMessage(_ text: String) {
        let threadId = id
        let cwd = projectId ?? workingDirectory

        if let generator = appViewModel?.titleGenerator {
            // 1. Instant placeholder from first sentence (synchronous, no network)
            let placeholder = generator.derivePlaceholder(from: text)
            if let placeholder {
                print("[ThreadVM] autoTitle: placeholder=\"\(placeholder)\"")
                title = placeholder
                persistAiTitle(placeholder)
            }

            // 2. Fire-and-forget: AI-generated title via LLM
            Task.detached { [weak self, generator] in
                guard let aiTitle = await generator.generateTitle(from: text) else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    print("[ThreadVM] autoTitle: AI title=\"\(aiTitle)\"")
                    self.title = aiTitle
                    self.persistAiTitle(aiTitle)
                }
            }
        } else {
            // Fallback: no title generator available (API key not configured).
            print("[ThreadVM] autoTitle: titleGenerator nil — using snippet fallback")
            let snippet = String(text.prefix(60))
            title = snippet
            if let s = store {
                let entry = LogEntry.customTitle(CustomTitleEntry(sessionID: threadId, customTitle: snippet))
                Task.detached { [store = s] in
                    try? store.appendMetadata(entry, sessionId: threadId, projectPath: cwd)
                }
            }
        }
    }

    /// Persist an ai-title to JSONL + update the session index.
    private func persistAiTitle(_ value: String) {
        guard let s = store else { return }
        let threadId = id
        let cwd = projectId ?? workingDirectory
        let entry = LogEntry.aiTitle(AiTitleEntry(sessionID: threadId, aiTitle: value))
        Task.detached { [store = s] in
            try? store.appendMetadata(entry, sessionId: threadId, projectPath: cwd)
        }
    }

    // MARK: - Send (Agent Loop)

    /// Send a user message and run the full agent loop.
    /// If the agent is already executing, queues the message for later processing.
    public func send(userText: String) {
        let debugger = AgentDebugger.shared

        guard session != nil else {
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
            // Add user message to the list so user sees it immediately,
            // but don't persist yet — startAgentRun will do that when
            // the queued message is processed, avoiding a duplicate.
            let userMsgID = UUID().uuidString
            let userMessage = AgentMessage.user(trimmed, id: userMsgID)
            messages.append(userMessage)
            return
        }

        print("[AgentLoop] SEND text=\"\(trimmed.truncated(to: 50))\"")
        debugger.logUI("Send: \"\(trimmed.truncated(to: 50))\"", metadata: ["threadId": id])
        startAgentRun(userText: trimmed)
    }

    /// Actually start the agent loop for the given user text.
    /// When `reuseUserMessageID` is set (queued message path), skips
    /// creating/persisting a new user message — the queued message
    /// was already added to the UI in send()'s early return.
    private func startAgentRun(userText trimmed: String, reuseUserMessageID: String? = nil) {
        guard let session = session else { return }

        // Add user message (skip for queued messages — already in the list)
        let userMsgID: String
        let userMessage: AgentMessage?
        if let reuseID = reuseUserMessageID {
            userMsgID = reuseID
            userMessage = nil
        } else {
            let newID = UUID().uuidString
            userMsgID = newID
            let msg = AgentMessage.user(trimmed, id: newID)
            messages.append(msg)
            userMessage = msg
        }
        currentRunUserMessageID = userMsgID

        // CRITICAL: Promote pending thread BEFORE persisting the user message.
        onFirstUserMessage?()

        // Write permission-mode entry (CC writes at session start)
        if let s = store, let mode = appViewModel?.permissionMode {
            let cwd = projectId ?? workingDirectory
            let sid = id
            let permEntry = LogEntry.permissionMode(PermissionModeEntry(sessionID: sid, permissionMode: mode))
            Task.detached { [store = s] in
                try? store.appendMetadata(permEntry, sessionId: sid, projectPath: cwd)
            }
        }

        // Resolve git branch asynchronously (off MainActor) to avoid UI freeze
        // if the git process hangs.
        if gitBranch == nil {
            let c = projectId ?? workingDirectory
            Task { [weak self] in
                self?.gitBranch = await Self.resolveGitBranch(cwd: c)
            }
        }

        // Persist the user message.
        if let msg = userMessage {
            persistMessageWithBlocks(msg)
        }

        // Create assistant placeholder
        let assistantID = UUID().uuidString
        let assistantMessage = AgentMessage.assistantStreaming(id: assistantID)
        messages.append(assistantMessage)

        // Update state
        DispatchQueue.main.async { [self] in
            state = .executing
            executionStartTime = Date()
            thinkingStartTime = nil
            reasoningExpanded = true
            startThoughtTimer()
            persistState()
        }

        // Auto-title on first user message (once per thread lifetime).
        if !hasAutoTitled {
            hasAutoTitled = true
            autoTitleFromFirstMessage(trimmed)
        }

        print("[ThreadVM] send() threadId=\(id.prefix(8)) projectId=\(projectId ?? "nil") workingDir=\(workingDirectory)")
        print("[ThreadVM] send() text=\"\(trimmed.truncated(to: 50))\"")

        // Start agent loop via streamResponse
        let runStartTime = CFAbsoluteTimeGetCurrent()
        print("[AgentLoop] RUN_START streamResponse() — input=\"\(trimmed.truncated(to: 30))\"")
        streamingTask = Task { [weak self] in
            guard let self else { return }

            let stream = await session.streamResponse(to: trimmed)
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.handleSessionEvent(event, assistantID: assistantID)
                    }
                }
                let runElapsed = (CFAbsoluteTimeGetCurrent() - runStartTime) * 1000
                print("[AgentLoop] RUN_DONE elapsed=\(String(format: "%.0f", runElapsed))ms")
                await MainActor.run {
                    self.handleStreamComplete(assistantID: assistantID)
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
        // Find the user message that send()'s early return pre-added so
        // startAgentRun reuses its ID instead of creating a duplicate.
        let existingUserID = messages.last(where: {
            $0.role == .user && $0.blocks.first?.textContent == next
        })?.id
        startAgentRun(userText: next, reuseUserMessageID: existingUserID)
    }

    // MARK: - Session Event Handling

    private func handleSessionEvent(_ event: SessionEvent, assistantID: String) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }

        switch event {
        case .textDelta(let text):
            messages[index].appendText(text)

        case .thinkingDelta(let text):
            if thinkingStartTime == nil { thinkingStartTime = Date() }
            messages[index].appendThinking(text)

        case .toolCallRequested(let toolUseID, let toolName, let input):
            let inputStr = String(data: input, encoding: .utf8) ?? ""
            let summary = summarizeToolInput(toolName: toolName, input: input)
            messages[index].addToolUse(ToolUseBlock(
                toolUseID: toolUseID,
                toolName: toolName,
                inputSummary: summary,
                inputDetail: inputStr,
                rawInput: parseJSONValue(input),
                status: .executing
            ))
            // Persistence deferred to handleStreamComplete (CC only writes final entries)

        case .toolCallCompleted(let toolUseID, let output, let isError):
            let outputStr = output.stringValue
            messages[index].updateToolUse(
                toolUseID: toolUseID,
                status: isError ? .error(outputStr) : .completed
            )
            messages[index].addToolResult(ToolResultBlock(
                toolUseID: toolUseID,
                content: outputStr,
                isError: isError
            ))
            // Persistence deferred to handleStreamComplete (CC only writes final entries)

            // Write file-history-snapshot for file-editing tools
            let toolName = messages[index].blocks.compactMap { b -> String? in
                if case .toolUse(let tu) = b, tu.toolUseID == toolUseID { return tu.toolName }
                return nil
            }.first
            let fileEditTools: Set<String> = ["Bash", "Write", "Edit"]
            if let tn = toolName, fileEditTools.contains(tn), let s = store {
                let cwd = projectId ?? workingDirectory
                let snapshotEntry = LogEntry.fileHistorySnapshot(FileHistorySnapshotEntry(
                    messageID: messages[index].id,
                    isSnapshotUpdate: false
                ))
                let sid = id
                Task.detached { [store = s] in
                    try? store.appendMetadata(snapshotEntry, sessionId: sid, projectPath: cwd)
                }
            }

        case .turnCompleted(let usage, _):
            if let u = usage {
                messages[index].tokenUsage = u
            }
            // Persistence deferred to handleStreamComplete which calls finalize() first.

        case .error(let err):
            print("[AgentLoop] SESSION_ERROR: \(err.localizedDescription)")
            // Defense: update state immediately so the UI doesn't appear stuck.
            // handleStreamError handles full cleanup (persist, processNextQueued).
            state = .failed(userFriendlyMessage(for: err))
            stopThoughtTimer()
            streamingTask?.cancel()
            streamingTask = nil
        }
    }

    private func handleStreamComplete(assistantID: String) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].finalize()
        // Set thinking duration AFTER finalize so ThinkingBlockView's onChange
        // fires AFTER isMessageStreaming becomes false — otherwise it would
        // collapse the thinking block mid-stream when duration becomes non-nil
        // while isMessageStreaming is still true.
        if let start = thinkingStartTime {
            messages[index].setThinkingDuration(Date().timeIntervalSince(start))
        } else if let start = executionStartTime {
            messages[index].setThinkingDuration(Date().timeIntervalSince(start))
        }
        persistMessageWithBlocks(messages[index])

        // Write stop_hook_summary system entry (CC writes after each assistant turn)
        if let s = store {
            let cwd = projectId ?? workingDirectory
            let systemEntry = LogEntry.systemEntry(SystemEntry(
                subtype: "stop_hook_summary",
                sessionID: id,
                parentUuid: lastPersistedEntryUUID,
                cwd: cwd,
                entrypoint: "app",
                version: "0.3.0",
                gitBranch: gitBranch
            ))
            let sid = id
            Task.detached { [store = s] in
                try? store.appendMetadata(systemEntry, sessionId: sid, projectPath: cwd)
            }
        }

        state = .done
        reasoningExpanded = false
        stopThoughtTimer()
        streamingTask = nil
        persistState()

        onStreamComplete?()
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

    /// Persist an AgentMessage with full block metadata to the JSONL transcript file.
    ///
    /// CC-compatible: thinking and non-thinking blocks are persisted as separate log entries,
    /// each with a unique UUID, sharing the message.id. The parentUuid chains correctly
    /// across entries (thinking → text/tool). Model name and stop_reason are included on
    /// assistant messages.
    ///
    /// Conversion (pure computation) runs on MainActor; file I/O is dispatched to a
    /// detached task so it never blocks the main thread during streaming.
    private func persistMessageWithBlocks(_ msg: AgentMessage) {
        guard let s = store else {
            print("[ThreadVM] persistMessageWithBlocks: SKIP — store is nil. threadId=\(id.prefix(8))")
            return
        }
        let threadId = id
        let cwd = projectId ?? workingDirectory
        let resolvedPath = SwiftAgentPaths.transcriptPath(sessionId: threadId, projectPath: cwd)
        let modelName = selectedModel
        let stopReason = msg.isStreaming ? nil : "end_turn"
        let branch = gitBranch  // resolved asynchronously in startAgentRun

        // Regenerate promptId for each user message
        let isUserMsg = msg.role == .user
        if isUserMsg {
            currentPromptId = UUID().uuidString
        }
        let promptId: String? = isUserMsg ? currentPromptId : nil
        let permMode = isUserMsg ? (appViewModel?.permissionMode) : nil

        print("[ThreadVM] persistMessageWithBlocks: threadId=\(threadId.prefix(8)) projectId=\(projectId ?? "nil") cwd=\(cwd) → file=\(resolvedPath)")

        // Split blocks: thinking vs everything else (CC split)
        let thinkingBlocks: [AgentMessageBlock] = msg.blocks.filter {
            if case .thinking = $0 { return true }; return false
        }
        let otherBlocks: [AgentMessageBlock] = msg.blocks.filter {
            if case .thinking = $0 { return false }; return true
        }

        // Persist thinking as a separate entry (if any)
        if !thinkingBlocks.isEmpty {
            if let coreMsg = buildCoreMessage(msg, blocks: thinkingBlocks, model: modelName, stopReason: stopReason) {
                let entryUUID = UUID().uuidString
                let parentUuid = lastPersistedEntryUUID
                lastPersistedEntryUUID = entryUUID

                let serialized = SerializedMessage(
                    uuid: entryUUID, message: coreMsg, cwd: cwd,
                    userType: "external", entrypoint: "app",
                    sessionID: threadId, timestamp: msg.timestamp,
                    version: "0.3.0", gitBranch: branch,
                    permissionMode: permMode, parentUuid: parentUuid,
                    isSidechain: false, promptId: promptId
                )
                Task.detached { [store = s] in
                    try? store.appendMessage(serialized, sessionId: threadId, projectPath: cwd)
                }
            }
        }

        // Persist text/tool blocks as a separate entry (if any)
        if !otherBlocks.isEmpty {
            if let coreMsg = buildCoreMessage(msg, blocks: otherBlocks, model: modelName, stopReason: stopReason) {
                let entryUUID = UUID().uuidString
                let parentUuid = lastPersistedEntryUUID
                lastPersistedEntryUUID = entryUUID

                let serialized = SerializedMessage(
                    uuid: entryUUID, message: coreMsg, cwd: cwd,
                    userType: "external", entrypoint: "app",
                    sessionID: threadId, timestamp: msg.timestamp,
                    version: "0.3.0", gitBranch: branch,
                    permissionMode: permMode, parentUuid: parentUuid,
                    isSidechain: false, promptId: promptId
                )
                Task.detached { [store = s] in
                    try? store.appendMessage(serialized, sessionId: threadId, projectPath: cwd)
                }
            }
        }

        // Update lastPrompt with actual user message text (CC updates on every user message)
        if isUserMsg {
            let promptText = msg.blocks.compactMap { block -> String? in
                if case .text(let t) = block { return t }; return nil
            }.joined(separator: " ")
            let truncated = String(promptText.prefix(200))
            let lastPromptEntry = LogEntry.lastPrompt(LastPromptEntry(
                sessionID: threadId,
                lastPrompt: truncated,
                leafUuid: lastPersistedEntryUUID
            ))
            Task.detached { [store = s] in
                try? store.appendMetadata(lastPromptEntry, sessionId: threadId, projectPath: cwd)
            }
        }
    }

    /// Build a Core Message from an AgentMessage for persistence.
    private func buildCoreMessage(_ msg: AgentMessage, blocks: [AgentMessageBlock],
                                   model: String?, stopReason: String?) -> Message? {
        let contentBlocks: [ContentBlock] = blocks.compactMap { block in
            switch block {
            case .text(let text):
                return text.isEmpty ? nil : .text(text)
            case .thinking(let text, let id, _, let duration):
                return .thinking(text, signature: id, duration: duration)
            case .toolUse(let toolUse):
                if let input = toolUse.rawInput {
                    return .toolUse(id: toolUse.toolUseID, name: toolUse.toolName, input: input)
                }
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
        switch msg.role {
        case .user: role = .user
        case .assistant: role = .assistant
        case .system: role = .user
        }

        let permMode = msg.role == .user ? appViewModel?.permissionMode : nil

        return Message(
            uuid: msg.id,
            type: role,
            content: contentBlocks,
            timestamp: msg.timestamp,
            usage: msg.tokenUsage,
            model: model,
            stopReason: stopReason,
            permissionMode: permMode
        )
    }

    /// Resolve the current git branch for the working directory.
    /// Runs the git process off the calling actor to avoid blocking UI.
    private static func resolveGitBranch(cwd: String) async -> String? {
        let cwdCopy = cwd
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", cwdCopy, "rev-parse", "--abbrev-ref", "HEAD"]
            process.currentDirectoryURL = URL(fileURLWithPath: cwdCopy)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = try pipe.fileHandleForReading.readToEnd()
                return data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
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

        // Map AgentRuntimeError to user-friendly messages
        if let runtimeError = error as? AgentRuntimeError {
            switch runtimeError {
            case .unauthorized:
                return "API key invalid. Update it in Settings → General."
            case .rateLimited(let info):
                if let sec = info.retryAfter { return "Rate limited. Retrying in \(sec)s." }
                return "Too many requests. Please wait before retrying."
            case .serverError(let status, _):
                return "Server returned error \(status). Try again later."
            case .timeout:
                return "Request timed out. The server may be busy — try again in a moment."
            case .invalidResponse(let reason):
                return "Invalid response: \(reason)"
            case .contextSizeExceeded:
                return "Context size exceeded. Try a shorter message."
            default:
                break
            }
        }

        // Fallback: raw localized description
        let desc = error.localizedDescription
        return desc.isEmpty ? "An error occurred" : desc
    }

    // MARK: - Helpers

    private func summarizeToolInput(toolName: String, input: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            return toolName
        }
        switch toolName {
        case "Bash", "PowerShell":
            return (obj["command"] as? String) ?? toolName
        case "Read", "FileRead", "Write", "FileWrite", "Edit", "FileEdit":
            return (obj["file_path"] as? String) ?? toolName
        case "Grep":
            return (obj["pattern"] as? String) ?? toolName
        case "Glob":
            return (obj["pattern"] as? String) ?? toolName
        case "WebFetch":
            return (obj["url"] as? String) ?? toolName
        case "WebSearch":
            return (obj["query"] as? String) ?? toolName
        case "Task":
            return (obj["description"] as? String) ?? toolName
        default:
            return obj.first.map { "\($0.key): \($0.value)" } ?? toolName
        }
    }

    private func parseJSONValue(_ data: Data) -> JSONValue? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSONValue.fromAny(obj)
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
