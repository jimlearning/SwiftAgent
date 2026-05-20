import Foundation

/// Global application state, managed as a single actor.
public actor AppState {
    public var currentSession: Session
    public var sessionHistory: ConversationHistory
    public var settings: Settings
    public var permissionMode: PermissionMode
    public var isProcessing: Bool = false
    public var currentToolCalls: [String] = []
    public var streamingOutput: String = ""
    public var statusMessage: String = ""
    public var tokenUsage: Usage = Usage(inputTokens: 0, outputTokens: 0)
    public var contextWindowSize: Int { settings.maxTokens }
    public var isPlanModeActive: Bool = false
    public var isAutoModeActive: Bool { permissionMode == .bypassPermissions }
    /// Tracks autocompact state across turns. Matches CC's AutoCompactTrackingState.
    public var compactionTracking: AutoCompactTrackingState = AutoCompactTrackingState()

    public init(
        session: Session = Session(),
        history: ConversationHistory = ConversationHistory(),
        settings: Settings = Settings(),
        permissionMode: PermissionMode = .default
    ) {
        self.currentSession = session
        self.sessionHistory = history
        self.settings = settings
        self.permissionMode = permissionMode
    }

    public func startProcessing() { isProcessing = true }
    public func stopProcessing() { isProcessing = false; currentToolCalls.removeAll() }
    public func appendStreamingOutput(_ text: String) { streamingOutput += text }
    public func resetStreamingOutput() { streamingOutput = "" }

    public func addTokenUsage(input: Int, output: Int) {
        tokenUsage = Usage(inputTokens: tokenUsage.inputTokens + input, outputTokens: tokenUsage.outputTokens + output)
    }

    public func updateSession(_ session: Session) {
        currentSession = session
        sessionHistory.addSession(session)
    }

    public func updateSettings(_ newSettings: Settings) {
        settings = newSettings
        permissionMode = newSettings.permissionMode
    }

    public func setPlanMode(_ active: Bool) {
        isPlanModeActive = active
        if active { permissionMode = .plan }
    }

    public func addToolCall(_ toolID: String) { currentToolCalls.append(toolID) }
    public func removeToolCall(_ toolID: String) { currentToolCalls.removeAll { $0 == toolID } }

    /// Update autocompact tracking state. Matches CC's autocompact state management.
    public func setCompactionTracking(_ tracking: AutoCompactTrackingState) {
        compactionTracking = tracking
    }

    /// Produce an immutable snapshot for UI observation.
    public func getSnapshot() -> AppStateSnapshot {
        AppStateSnapshot(
            isProcessing: isProcessing,
            streamingOutput: streamingOutput,
            statusMessage: statusMessage,
            isPlanModeActive: isPlanModeActive,
            isAutoModeActive: isAutoModeActive,
            tokenUsage: tokenUsage,
            sessionTitle: currentSession.title
        )
    }
}
