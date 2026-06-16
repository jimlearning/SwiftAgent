import SwiftUI
import SwiftAgentCore

// MARK: - ThreadState

/// Thread execution state machine (§7.1).
/// Phase 2 implements: idle, executing, done, failed.
public enum ThreadState: Equatable, Sendable {
    case idle
    case executing
    case done
    case failed(String)  // error message

    public init?(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "executing": self = .executing
        case "done": self = .done
        case "failed": self = .failed("")
        default:
            if rawValue.hasPrefix("failed:") {
                self = .failed(String(rawValue.dropFirst(7)))
            } else {
                self = .idle
            }
        }
    }

    /// Whether the composer should be disabled.
    public var isComposerDisabled: Bool {
        switch self {
        case .executing: return true
        case .idle, .done, .failed: return false
        }
    }

    /// Human-readable status for display.
    public var statusText: String? {
        switch self {
        case .idle: return nil
        case .executing: return nil  // status row shows "Thought for Xs"
        case .done: return nil
        case .failed(let msg): return msg
        }
    }

    /// Whether an error state is active.
    public var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - ThreadMessage

/// A message in the thread conversation.
public struct ThreadMessage: Identifiable, Equatable {
    public let id: String
    public let role: MessageRole
    public var content: String
    /// Reasoning content (for R1 model thinking chain).
    public var reasoningContent: String?
    /// Whether this message is still being streamed.
    public var isStreaming: Bool
    /// Token count estimate.
    public var tokenCount: Int

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String = "",
        reasoningContent: String? = nil,
        isStreaming: Bool = false,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.isStreaming = isStreaming
        self.tokenCount = tokenCount
    }
}

// MARK: - ThreadReuseState

/// Cross-session reuse state (§7.2).
public enum ThreadReuseState: String, Sendable {
    case new
    case active
    case idle
    case resumed
    case paused
}

// MARK: - ThreadViewModel

/// View model for a single conversation thread.
/// Manages message list, streaming state, and interaction with the LLM provider.
@MainActor
public final class ThreadViewModel: ObservableObject, Identifiable {
    /// The thread's unique identifier.
    public let id: String

    /// Display title.
    @Published public var title: String = "Untitled"

    /// All messages in the thread.
    @Published public var messages: [ThreadMessage] = []

    /// Current thread state.
    @Published public var state: ThreadState = .idle

    /// Selected model for this thread.
    @Published public var selectedModel: DeepSeekModel = .v4Pro

    /// Reasoning strength (for display, maps to model choice for DeepSeek).
    @Published public var reasoningStrength: ReasoningStrength = .high

    /// Reuse state (§7.2).
    @Published public var reuseState: ThreadReuseState = .new

    /// Thread mode (code, plan, goal, side).
    @Published public var mode: String = "code"

    /// Sandbox mode.
    @Published public var sandboxMode: String = "workspace-write"

    /// Execution environment.
    @Published public var executionEnv: String = "local"

    /// When this thread was last updated.
    @Published public var updatedAt: Date = Date()

    /// The time when execution started (for "Thought for Xs" display).
    @Published public var executionStartTime: Date?

    /// Elapsed thought time string.
    @Published public var thoughtTimeString: String?

    /// Whether reasoning content is expanded (for R1).
    @Published public var reasoningExpanded: Bool = false

    /// Reference to the app-level LLM provider.
    private weak var llmProvider: AppLLMProvider?

    /// Reference to the storage manager for auto-persist.
    private weak var storageManager: StorageManager?

    /// Timer for updating "Thought for Xs".
    private var thoughtTimer: Timer?

    /// The current streaming task (allows cancellation).
    private var streamingTask: Task<Void, Never>?

    /// Optional callback fired when a stream finishes (whether
    /// successfully or with an error). Wired by AppViewModel to
    /// refresh the diff cache so the Review panel shows real numbers
    /// instead of `+0 -0`.
    public var onStreamComplete: (() -> Void)?

    /// Whether this thread has unread messages (purely UI concept, not persisted).
    @Published public var hasUnread: Bool = false

    public init(
        id: String = UUID().uuidString,
        llmProvider: AppLLMProvider? = nil,
        storageManager: StorageManager? = nil
    ) {
        self.id = id
        self.llmProvider = llmProvider
        self.storageManager = storageManager
    }

    /// Set the LLM provider reference.
    public func setProvider(_ provider: AppLLMProvider?) {
        self.llmProvider = provider
    }

    /// Update from a persisted thread record.
    public func update(from thread: PersistedThread) {
        self.title = thread.title
        self.state = ThreadState(rawValue: thread.state) ?? .idle
        self.reuseState = ThreadReuseState(rawValue: thread.reuseState) ?? .new
        self.mode = thread.mode
        self.sandboxMode = thread.sandboxMode
        self.executionEnv = thread.executionEnv
        self.updatedAt = thread.updatedAt
        if let model = DeepSeekModel(rawValue: thread.model) {
            self.selectedModel = model
        }
    }

    /// Load messages from persisted records.
    public func loadMessages(from persisted: [PersistedMessage]) {
        self.messages = persisted.compactMap { pm in
            guard let role = MessageRole(rawValue: pm.role) else { return nil }
            return ThreadMessage(
                id: pm.id,
                role: role,
                content: pm.content,
                isStreaming: false
            )
        }
    }

    /// The persisted state string.
    public var persistedState: String {
        switch state {
        case .idle: return "idle"
        case .executing: return "executing"
        case .done: return "done"
        case .failed: return "failed"
        }
    }

    /// Persist current state to the database.
    public func persistState() {
        guard let storage = storageManager, storage.isReady else { return }
        do {
            try storage.threadRepo.updateState(id: id, state: persistedState)
        } catch {
            print("[ThreadViewModel] Persist state failed: \(error)")
        }
    }

    /// Persist a message to the database.
    public func persistMessage(_ message: PersistedMessage) {
        guard let storage = storageManager, storage.isReady else { return }
        do {
            try storage.messageRepo.append(message)
        } catch {
            print("[ThreadViewModel] Persist message failed: \(error)")
        }
    }

    // MARK: - Send

    /// Send a user message and stream the assistant response.
    public func send(userText: String) {
        guard let provider = llmProvider, state != .executing else {
            return
        }

        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add user message
        let userMsgID = UUID().uuidString
        let userMessage = ThreadMessage(
            id: userMsgID,
            role: .user,
            content: trimmed,
            isStreaming: false
        )
        messages.append(userMessage)

        // Auto-persist user message
        let pm = PersistedMessage(
            id: userMsgID,
            threadId: id,
            role: "user",
            content: trimmed
        )
        persistMessage(pm)

        // Create assistant placeholder
        let assistantID = UUID().uuidString
        let assistantMessage = ThreadMessage(
            id: assistantID,
            role: .assistant,
            content: "",
            isStreaming: true
        )
        messages.append(assistantMessage)

        // Update state
        state = .executing
        executionStartTime = Date()
        startThoughtTimer()
        persistState()

        // Auto-set title from first message if still untitled
        if title == "Untitled" || title == "New Chat" {
            let snippet = String(trimmed.prefix(60))
            title = snippet
            _ = try? storageManager?.threadRepo.updateTitle(id: id, title: snippet)
        }

        // Build Message array for the API
        let apiMessages = buildAPIMessages()

        // Start streaming
        streamingTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = provider.streamWithReasoning(
                    messages: apiMessages,
                    model: self.selectedModel
                )

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .token(let token):
                        self.appendToken(to: assistantID, token: token)
                    case .reasoningToken(let token):
                        self.appendReasoningToken(to: assistantID, token: token)
                    case .done:
                        self.finishStream(assistantID: assistantID)
                    case .error(let error):
                        self.handleStreamError(assistantID: assistantID, error: error)
                    }
                }

                // Ensure completion if stream ends without .done
                await MainActor.run {
                    if case .executing = self.state {
                        self.finishStream(assistantID: assistantID)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.handleStreamError(assistantID: assistantID, error: error)
                    }
                }
            }
        }
    }

    /// Cancel the current streaming response.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        state = .idle
        stopThoughtTimer()

        // Mark the last assistant message as done
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[lastIndex].isStreaming = false
        }
    }

    // MARK: - Private Helpers

    private func appendToken(to id: String, token: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += token
        messages[index].tokenCount += 1
    }

    private func appendReasoningToken(to id: String, token: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].reasoningContent == nil {
            messages[index].reasoningContent = ""
        }
        messages[index].reasoningContent? += token
    }

    private func finishStream(assistantID: String) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].isStreaming = false
        state = .done
        stopThoughtTimer()
        streamingTask = nil

        // Persist assistant message
        let content = messages[index].content
        let pm = PersistedMessage(
            id: assistantID,
            threadId: id,
            role: "assistant",
            content: content
        )
        persistMessage(pm)
        persistState()

        // Refresh the diff summary on the main actor so the Review
        // panel sees up-to-date file edits.
        onStreamComplete?()
    }

    private func handleStreamError(assistantID: String, error: Error) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].isStreaming = false

        let errorMessage: String
        if let dsError = error as? DeepSeekError {
            errorMessage = dsError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }

        let finalMessage = errorMessage.isEmpty ? "An error occurred" : errorMessage
        messages[index].content = finalMessage
        state = .failed(finalMessage)
        stopThoughtTimer()
        streamingTask = nil

        // Persist error
        let pm = PersistedMessage(
            id: assistantID,
            threadId: id,
            role: "assistant",
            content: finalMessage
        )
        persistMessage(pm)
        persistState()
    }

    private func buildAPIMessages() -> [Message] {
        messages.compactMap { threadMsg in
            guard !threadMsg.isStreaming || threadMsg.role != .assistant else {
                // Don't include incomplete assistant messages
                return nil
            }
            guard !threadMsg.content.isEmpty || threadMsg.role == .user else {
                return nil
            }
            return Message(
                type: threadMsg.role,
                content: [.text(threadMsg.content)]
            )
        }
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
        thoughtTimeString = nil
    }

    private func updateThoughtTime() {
        guard let start = executionStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        thoughtTimeString = "Thought for \(elapsed)s"
    }

    /// Clean up resources. Call before the view model is deallocated.
    public func cleanup() {
        thoughtTimer?.invalidate()
        thoughtTimer = nil
        streamingTask?.cancel()
        streamingTask = nil
    }
}

// MARK: - ReasoningStrength

/// Reasoning strength for the model picker menu (per §5.7, §11.5).
public enum ReasoningStrength: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case extraHigh = "Extra High"
}
