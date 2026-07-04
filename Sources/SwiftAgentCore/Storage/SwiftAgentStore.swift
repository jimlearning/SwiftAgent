import Foundation

// MARK: - SwiftAgent Store

/// Central facade for all file-based persistence.
///
/// Combines `ProjectDiscoverer`, `SessionIndexStore`, and `TranscriptStore`
/// into a single entry point for the App and CLI layers.
///
/// All data is stored under `~/.swift-agent/projects/` in CC-compatible format.
///
/// ## Usage
/// ```swift
/// let store = SwiftAgentStore()
///
/// // Discover all projects
/// let projects = store.discoverProjects()
///
/// // List sessions for a project
/// let sessions = try store.listSessions(projectPath: "/Users/jim/SwiftAgent")
///
/// // Append a message to a session
/// try store.appendMessage(message, sessionId: "...", projectPath: "...")
/// ```
public final class SwiftAgentStore: @unchecked Sendable {
    public let projectDiscoverer: ProjectDiscoverer
    public let sessionIndex: SessionIndexStore
    public let transcripts: TranscriptStore

    public init() {
        self.projectDiscoverer = ProjectDiscoverer()
        self.sessionIndex = SessionIndexStore()
        self.transcripts = TranscriptStore()
    }

    // MARK: - Projects

    /// Discover all projects from disk.
    public func discoverProjects() -> [DiscoveredProject] {
        projectDiscoverer.discoverAll()
    }

    /// Create a new project directory on disk.
    @discardableResult
    public func createProject(projectPath: String) throws -> String {
        try projectDiscoverer.createProject(projectPath: projectPath)
    }

    /// Delete a project and all its sessions.
    public func deleteProject(projectPath: String) throws {
        try projectDiscoverer.deleteProject(projectPath: projectPath)
    }

    // MARK: - Sessions (list)

    /// List all sessions for a project, most recent first.
    public func listSessions(projectPath: String) throws -> [SessionIndexEntry] {
        try sessionIndex.list(projectPath: projectPath)
    }

    /// Get session metadata by ID.
    public func getSession(sessionId: String, projectPath: String) throws -> SessionIndexEntry? {
        try sessionIndex.get(sessionId: sessionId, projectPath: projectPath)
    }

    // MARK: - Session (create)

    /// Create a new session: writes initial metadata entries + adds to index.
    /// - Parameters:
    ///   - sessionId: UUID for the session.
    ///   - projectPath: Original (unsanitized) project path.
    ///   - title: Optional custom title.
    ///   - cwd: Working directory for the session.
    ///   - version: App version string.
    ///   - gitBranch: Current git branch.
    public func createSession(
        sessionId: String = UUID().uuidString,
        projectPath: String,
        title: String? = nil,
        cwd: String,
        version: String = "1.0.0",
        gitBranch: String? = nil
    ) throws -> (sessionId: String, transcriptPath: String) {
        // Ensure project directory exists
        try projectDiscoverer.createProject(projectPath: projectPath)

        let isoNow = ISO8601DateFormatter().string(from: Date())

        // Write custom title if provided
        if let title = title {
            let titleEntry = LogEntry.customTitle(CustomTitleEntry(
                sessionID: sessionId,
                customTitle: title
            ))
            try transcripts.append(titleEntry, sessionId: sessionId, projectPath: projectPath)
        }

        // Add to session index
        let transcriptPath = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        let indexEntry = SessionIndexEntry(
            sessionId: sessionId,
            fullPath: transcriptPath,
            firstPrompt: title,
            customTitle: title,
            messageCount: 0,
            created: isoNow,
            modified: isoNow,
            gitBranch: gitBranch,
            projectPath: projectPath,
            isSidechain: false
        )
        try sessionIndex.upsert(indexEntry, projectPath: projectPath)

        return (sessionId, transcriptPath)
    }

    // MARK: - Session (delete)

    /// Delete a session (transcript file + session dir + index entry).
    public func deleteSession(sessionId: String, projectPath: String) throws {
        try transcripts.delete(sessionId: sessionId, projectPath: projectPath)
        try sessionIndex.remove(sessionId: sessionId, projectPath: projectPath)
    }

    // MARK: - Messages

    /// Append a serialized message to the session transcript.
    /// Also updates the session index (message count, modified time, last prompt).
    public func appendMessage(
        _ message: SerializedMessage,
        sessionId: String,
        projectPath: String
    ) throws {
        let entry = LogEntry.transcript(message)
        try transcripts.append(entry, sessionId: sessionId, projectPath: projectPath)

        // Update index: increment message count, update modified time
        if var indexEntry = try sessionIndex.get(sessionId: sessionId, projectPath: projectPath) {
            indexEntry.messageCount += 1
            indexEntry.modified = ISO8601DateFormatter().string(from: Date())
            // Update first prompt if this is the first user message
            if indexEntry.firstPrompt == nil,
               message.message.type == .user,
               case .text(let text) = message.message.content.first {
                indexEntry.firstPrompt = text
            }
            try sessionIndex.upsert(indexEntry, projectPath: projectPath)
        }
    }

    /// Append a metadata entry (title, summary, tag, etc.) to the session transcript.
    public func appendMetadata(
        _ entry: LogEntry,
        sessionId: String,
        projectPath: String
    ) throws {
        try transcripts.append(entry, sessionId: sessionId, projectPath: projectPath)

        // Update index with metadata changes
        if var indexEntry = try sessionIndex.get(sessionId: sessionId, projectPath: projectPath) {
            switch entry {
            case .customTitle(let e):
                indexEntry.customTitle = e.customTitle
            case .aiTitle(let e):
                indexEntry.customTitle = e.aiTitle
            case .summary(let e):
                indexEntry.summary = e.summary
            case .tag(let e):
                indexEntry.tag = e.tag
            case .mode(let e):
                indexEntry.mode = e.mode.rawValue
            case .agentName(let e):
                indexEntry.agentName = e.agentName
            case .agentColor(let e):
                indexEntry.agentColor = e.agentColor
            default:
                break
            }
            indexEntry.modified = ISO8601DateFormatter().string(from: Date())
            try sessionIndex.upsert(indexEntry, projectPath: projectPath)
        }
    }

    /// Read all messages from a session transcript.
    public func readMessages(sessionId: String, projectPath: String) throws -> [SerializedMessage] {
        try transcripts.readMessages(sessionId: sessionId, projectPath: projectPath)
    }

    /// Read all entries (messages + metadata) from a session transcript.
    public func readAllEntries(sessionId: String, projectPath: String) throws -> [LogEntry] {
        try transcripts.readAll(sessionId: sessionId, projectPath: projectPath)
    }

    // MARK: - Index Rebuild

    /// Rebuild the session index for a project by scanning all JSONL files.
    /// Useful after manual file operations or corruption.
    public func rebuildIndex(projectPath: String) throws {
        try sessionIndex.rebuild(projectPath: projectPath, transcriptStore: transcripts)
    }
}
