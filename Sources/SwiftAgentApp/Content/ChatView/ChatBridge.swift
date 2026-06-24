import SwiftUI
import SwiftAgentCore
import ObjectiveC

/// Per-window observable bridge between chat views and the app-layer view models.
///
/// Wraps `AppViewModel` + `ThreadViewModel` to provide the same interface
/// ClarcChatKit views expect: `messages`, `isStreaming`, `isThinking`,
/// `send()`, `cancelStreaming()`, etc.
@Observable
@MainActor
final class ChatBridge {

    // MARK: - Dependencies

    private weak var appViewModel: AppViewModel?

    /// The currently selected thread. Set by the owning view.
    var selectedThread: ThreadViewModel? {
        didSet { refreshFromThread() }
    }

    // MARK: - AppViewModel-derived Properties (avoid @EnvironmentObject cascade)

    var focusMode: Bool = false
    var currentSessionId: String?
    var inspectorFile: PreviewFile? {
        get { _inspectorFile }
        set {
            _inspectorFile = newValue
            appViewModel?.inspectorFile = newValue
        }
    }
    private var _inspectorFile: PreviewFile?

    /// Call after AppViewModel state changes to keep bridged properties in sync.
    func syncWithAppViewModel() {
        guard let appVM = appViewModel else { return }
        currentSessionId = appVM.selectedThreadID
        focusMode = appVM.focusMode
    }

    // MARK: - Streaming State (derived from selectedThread)

    var messages: [ChatDisplayMessage] = []
    var isStreaming: Bool = false
    var isThinking: Bool = false
    var streamingStartDate: Date?
    var lastTurnContextUsedPercentage: Double?
    var modelDisplayName: String = "DeepSeek"
    var sessionStats = ChatSessionStats()
    var autoPreviewSettings = AttachmentAutoPreviewSettings()

    // MARK: - Init

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    // MARK: - Refresh from thread

    func refreshFromThread() {
        let refreshStart = Date()
        guard let thread = selectedThread else {
            messages = []
            isStreaming = false
            isThinking = false
            streamingStartDate = nil
            return
        }
        let threadState = thread.state
        isStreaming = threadState == .executing

        let sourceMessages = thread.messages
        let previousCount = messages.count
        ChatPerfLogger.refreshBegin(msgCount: sourceMessages.count)

        // Full rebuild when count changes or streaming just stopped
        let fullRebuild = sourceMessages.count != previousCount || !isStreaming
        if fullRebuild {
            messages = sourceMessages.map { msg in
                let msgStart = Date()
                var cm = ChatDisplayMessage(source: msg)
                cm.threadState = threadState
                ChatPerfLogger.messageInitSlow(
                    msgId: msg.id, blockCount: msg.blocks.count,
                    elapsedMs: Date().timeIntervalSince(msgStart) * 1000
                )
                return cm
            }
        } else if isStreaming, let lastSource = sourceMessages.last {
            let msgStart = Date()
            var cm = ChatDisplayMessage(source: lastSource)
            cm.threadState = threadState
            ChatPerfLogger.messageInitSlow(
                msgId: lastSource.id, blockCount: lastSource.blocks.count,
                elapsedMs: Date().timeIntervalSince(msgStart) * 1000
            )
            messages[messages.count - 1] = cm
        }

        if let start = thread.executionStartTime {
            streamingStartDate = start
        }
        isThinking = sourceMessages.last?.blocks.contains { block in
            if case .thinking = block { return true }
            return false
        } ?? false
        if let model = thread.selectedModel.nilIfEmpty {
            modelDisplayName = model
        }

        ChatPerfLogger.refreshEnd(
            fullRebuild: fullRebuild,
            previousCount: previousCount,
            newCount: messages.count,
            elapsedMs: Date().timeIntervalSince(refreshStart) * 1000
        )
    }

    // MARK: - Action Methods (delegate to ThreadViewModel)

    func send() async {
        guard let thread = selectedThread, let appVM = appViewModel else { return }
        let text = appVM.inputText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !appVM.pendingAttachments.isEmpty
        guard !trimmed.isEmpty || hasAttachments else { return }

        var messageText = trimmed
        for att in appVM.pendingAttachments {
            if let path = att.path {
                messageText += "\n[File: \(path)]"
            }
        }
        appVM.inputText = ""
        appVM.pendingAttachments = []

        thread.send(userText: messageText)
    }

    func cancelStreaming() async {
        selectedThread?.cancel()
    }

    func sendSlashCommand(_ command: String) async {
        guard let thread = selectedThread else { return }
        thread.send(userText: command)
    }

    func runTerminalCommand(_ command: String) async {
        guard let thread = selectedThread else { return }
        thread.send(userText: command)
    }

    func editAndResend(messageId: String, newContent: String) async {
        guard let thread = selectedThread else { return }
        if let idx = thread.messages.firstIndex(where: { $0.id == messageId }) {
            thread.messages.removeSubrange(idx...)
        }
        thread.send(userText: newContent)
    }

    func forkFromHere(messageId: String) async {
        guard let appVM = appViewModel, let thread = selectedThread else { return }
        let newThread = appVM.createThread(
            title: thread.title + " (fork)",
            projectId: thread.projectId
        )
        if let idx = thread.messages.firstIndex(where: { $0.id == messageId }) {
            newThread.messages = Array(thread.messages.prefix(through: idx))
        }
        appVM.selectThread(newThread)
    }

    func fetchRateLimit() async -> RateLimitUsage? {
        nil
    }
}

// MARK: - AppViewModel extensions for InputBarView compatibility

extension AppViewModel {
    var inputText: String {
        get { objc_getAssociatedObject(self, &inputTextKey) as? String ?? "" }
        set { objc_setAssociatedObject(self, &inputTextKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var messageQueue: [QueuedMessage] {
        get { objc_getAssociatedObject(self, &msgQueueKey) as? [QueuedMessage] ?? [] }
        set { objc_setAssociatedObject(self, &msgQueueKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    func enqueueMessage(text: String, attachments: [Attachment]) {
        messageQueue.append(QueuedMessage(text: text, attachments: attachments))
    }

    func dequeueMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    func dequeueNext() -> QueuedMessage? {
        guard !messageQueue.isEmpty else { return nil }
        return messageQueue.removeFirst()
    }

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]

    var attachments: [Attachment] {
        pendingAttachments.compactMap { ca in
            guard let path = ca.path else { return nil }
            let ext = (path as NSString).pathExtension.lowercased()
            let isImage = Self.imageExts.contains(ext)
            return Attachment(type: isImage ? .image : .file, name: ca.displayName, path: path)
        }
    }

    var requestInputFocus: Bool {
        get { objc_getAssociatedObject(self, &focusKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &focusKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var currentSessionId: String? { selectedThreadID }

    var selectedProject: ProjectViewModel? {
        guard let thread = selectedThread,
              let pid = thread.projectId else { return nil }
        return projects.first(where: { $0.path.lowercased() == pid.lowercased() })
    }

    var inspectorFile: PreviewFile? {
        get { objc_getAssociatedObject(self, &inspectorKey) as? PreviewFile }
        set { objc_setAssociatedObject(self, &inspectorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var diffFile: PreviewFile? {
        get { objc_getAssociatedObject(self, &diffFileKey) as? PreviewFile }
        set { objc_setAssociatedObject(self, &diffFileKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var selectedPermissionMode: PermissionModeOption {
        get { objc_getAssociatedObject(self, &permModeKey) as? PermissionModeOption ?? .default }
        set { objc_setAssociatedObject(self, &permModeKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var selectedModel: String {
        get { objc_getAssociatedObject(self, &modelKey) as? String ?? "auto" }
        set { objc_setAssociatedObject(self, &modelKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

// Associated-object keys — immutable after init, used only on MainActor.
nonisolated(unsafe) private var inputTextKey: UInt8 = 0
nonisolated(unsafe) private var msgQueueKey: UInt8 = 0
nonisolated(unsafe) private var focusKey: UInt8 = 0
nonisolated(unsafe) private var inspectorKey: UInt8 = 0
nonisolated(unsafe) private var diffFileKey: UInt8 = 0
nonisolated(unsafe) private var permModeKey: UInt8 = 0
nonisolated(unsafe) private var modelKey: UInt8 = 0

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
