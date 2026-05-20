import Foundation

/// Log/transcript entry types matching CC's types/logs.ts Entry discriminated union.
/// These represent the various entry types that can appear in a session transcript.

/// A message serialized for log/transcript storage with metadata.
/// Matches CC's TranscriptMessage (which extends SerializedMessage with parent tracking fields).
public struct SerializedMessage: Sendable, Codable {
    public var message: Message
    public var cwd: String
    public var userType: String
    public var entrypoint: String?
    public var sessionID: String
    public var timestamp: Date
    public var version: String
    public var gitBranch: String?
    public var slug: String?

    // TranscriptMessage fields (CC's Message & extras for parent/sidechain tracking)
    public var parentUuid: String?
    public var logicalParentUuid: String?
    public var isSidechain: Bool
    public var agentId: String?
    public var teamName: String?
    public var agentName: String?
    public var agentColor: String?
    public var promptId: String?

    public init(
        message: Message,
        cwd: String,
        userType: String,
        entrypoint: String? = nil,
        sessionID: String,
        timestamp: Date = Date(),
        version: String,
        gitBranch: String? = nil,
        slug: String? = nil,
        parentUuid: String? = nil,
        logicalParentUuid: String? = nil,
        isSidechain: Bool = false,
        agentId: String? = nil,
        teamName: String? = nil,
        agentName: String? = nil,
        agentColor: String? = nil,
        promptId: String? = nil
    ) {
        self.message = message
        self.cwd = cwd
        self.userType = userType
        self.entrypoint = entrypoint
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.version = version
        self.gitBranch = gitBranch
        self.slug = slug
        self.parentUuid = parentUuid
        self.logicalParentUuid = logicalParentUuid
        self.isSidechain = isSidechain
        self.agentId = agentId
        self.teamName = teamName
        self.agentName = agentName
        self.agentColor = agentColor
        self.promptId = promptId
    }
}

/// Session log option matching CC's LogOption.
public struct LogOption: Sendable, Codable {
    public var date: String
    public var messages: [SerializedMessage]
    public var fullPath: String?
    public var value: Double
    public var created: Date
    public var modified: Date
    public var firstPrompt: String
    public var messageCount: Int
    public var fileSize: Int?
    public var isSidechain: Bool
    public var isLite: Bool?
    public var sessionID: String?
    public var teamName: String?
    public var agentName: String?
    public var agentColor: String?
    public var agentSetting: String?
    public var isTeammate: Bool?
    public var summary: String?
    public var customTitle: String?
    public var tag: String?
    public var gitBranch: String?
    public var projectPath: String?
    public var prNumber: Int?
    public var prUrl: String?
    public var prRepository: String?
    public var mode: SessionMode?

    // Additional CC fields not previously in SA
    public var leafUuid: String?
    public var fileHistorySnapshots: [FileHistorySnapshot]?
    public var attributionSnapshots: [AttributionSnapshotEntry]?
    public var contextCollapseCommits: [ContextCollapseCommitEntry]?
    public var contextCollapseSnapshot: ContextCollapseSnapshotEntry?
    public var worktreeSession: PersistedWorktreeSession?
    public var contentReplacements: [ContentReplacementRecord]?

    public enum SessionMode: String, Sendable, Codable {
        case coordinator
        case normal
    }
}

/// Summary message entry. Matches CC's SummaryMessage.
public struct SummaryEntry: Sendable, Codable {
    public let type: String  // "summary"
    public let leafUuid: String
    public let summary: String
}

/// Custom title entry. Matches CC's CustomTitleMessage.
public struct CustomTitleEntry: Sendable, Codable {
    public let type: String  // "custom-title"
    public let sessionID: String
    public let customTitle: String
}

/// AI-generated title entry. Matches CC's AiTitleMessage.
public struct AiTitleEntry: Sendable, Codable {
    public let type: String  // "ai-title"
    public let sessionID: String
    public let aiTitle: String
}

/// Last prompt entry. Matches CC's LastPromptMessage.
public struct LastPromptEntry: Sendable, Codable {
    public let type: String  // "last-prompt"
    public let sessionID: String
    public let lastPrompt: String
}

/// Task summary entry. Matches CC's TaskSummaryMessage.
public struct TaskSummaryEntry: Sendable, Codable {
    public let type: String  // "task-summary"
    public let sessionID: String
    public let summary: String
    public let timestamp: Date
}

/// Tag entry. Matches CC's TagMessage.
public struct TagEntry: Sendable, Codable {
    public let type: String  // "tag"
    public let sessionID: String
    public let tag: String
}

/// Agent name entry. Matches CC's AgentNameMessage.
public struct AgentNameEntry: Sendable, Codable {
    public let type: String  // "agent-name"
    public let sessionID: String
    public let agentName: String
}

/// Agent color entry. Matches CC's AgentColorMessage.
public struct AgentColorEntry: Sendable, Codable {
    public let type: String  // "agent-color"
    public let sessionID: String
    public let agentColor: String
}

/// Agent setting entry. Matches CC's AgentSettingMessage.
public struct AgentSettingEntry: Sendable, Codable {
    public let type: String  // "agent-setting"
    public let sessionID: String
    public let agentSetting: String
}

/// PR link entry. Matches CC's PRLinkMessage.
public struct PRLinkEntry: Sendable, Codable {
    public let type: String  // "pr-link"
    public let sessionID: String
    public let prNumber: Int
    public let prUrl: String
    public let prRepository: String
    public let timestamp: Date
}

/// File history snapshot entry. Matches CC's FileHistorySnapshotMessage.
public struct FileHistorySnapshotEntry: Sendable, Codable {
    public let type: String  // "file-history-snapshot"
    public let messageID: String
    public let isSnapshotUpdate: Bool
}

/// Mode entry. Matches CC's ModeEntry.
public struct ModeEntry: Sendable, Codable {
    public let type: String  // "mode"
    public let sessionID: String
    public let mode: LogOption.SessionMode
}

/// Specification accept entry. Matches CC's SpeculationAcceptMessage.
public struct SpeculationAcceptEntry: Sendable, Codable {
    public let type: String  // "speculation-accept"
    public let timestamp: Date
    public let timeSavedMs: Int
}

// MARK: - Missing CC Entry Types (added for parity)

/// Queue operation type matching CC's QueueOperation.
/// Derived from CC's messageQueueManager.ts:30-36 logOperation() usage.
public enum QueueOperation: String, Sendable, Codable {
    case enqueue = "enqueue"
    case dequeue = "dequeue"
    case skip = "skip"
    case flush = "flush"
}

/// Queue operation log entry. Matches CC's QueueOperationMessage.
public struct QueueOperationEntry: Sendable, Codable {
    public let type: String  // "queue-operation"
    public let operation: QueueOperation
    public let timestamp: Date
    public let sessionID: String
    public let content: String?
}

/// Per-file attribution state tracking Claude's character contributions.
/// Matches CC's FileAttributionState.
public struct FileAttributionState: Sendable, Codable {
    public let contentHash: String
    public let claudeContribution: Int
    public let mtime: Int
}

/// Attribution snapshot entry. Matches CC's AttributionSnapshotMessage.
public struct AttributionSnapshotEntry: Sendable, Codable {
    public let type: String  // "attribution-snapshot"
    public let messageId: UUID
    public let surface: String
    public let fileStates: [String: FileAttributionState]
    public let promptCount: Int?
    public let promptCountAtLastCommit: Int?
    public let permissionPromptCount: Int?
    public let permissionPromptCountAtLastCommit: Int?
    public let escapeCount: Int?
    public let escapeCountAtLastCommit: Int?
}

/// Content replacement record for tool result persistence.
/// Matches CC's ContentReplacementRecord.
public struct ContentReplacementRecord: Sendable, Codable {
    public let kind: String  // "tool-result"
    public let toolUseId: String
    public let replacement: String
}

/// Content replacement entry. Matches CC's ContentReplacementEntry.
public struct ContentReplacementEntry: Sendable, Codable {
    public let type: String  // "content-replacement"
    public let sessionID: String
    public let agentId: String?
    public let replacements: [ContentReplacementRecord]
}

/// Persisted worktree session state for resume.
/// Matches CC's PersistedWorktreeSession.
public struct PersistedWorktreeSession: Sendable, Codable {
    public let originalCwd: String
    public let worktreePath: String
    public let worktreeName: String
    public let worktreeBranch: String?
    public let originalBranch: String?
    public let originalHeadCommit: String?
    public let sessionId: String
    public let tmuxSessionName: String?
    public let hookBased: Bool?
}

/// Worktree state entry (last-wins: enter writes session, exit writes null).
/// Matches CC's WorktreeStateEntry.
public struct WorktreeStateEntry: Sendable, Codable {
    public let type: String  // "worktree-state"
    public let sessionID: String
    public let worktreeSession: PersistedWorktreeSession?
}

/// Context collapse commit entry. Matches CC's ContextCollapseCommitEntry.
public struct ContextCollapseCommitEntry: Sendable, Codable {
    public let type: String  // "marble-origami-commit"
    public let sessionID: String
    public let collapseId: String
    public let summaryUuid: String
    public let summaryContent: String
    public let summary: String
    public let firstArchivedUuid: String
    public let lastArchivedUuid: String
}

/// Staged span within a context collapse snapshot.
public struct ContextCollapseStagedSpan: Sendable, Codable {
    public let startUuid: String
    public let endUuid: String
    public let summary: String
    public let risk: Int
    public let stagedAt: Int
}

/// Context collapse snapshot entry (last-wins).
/// Matches CC's ContextCollapseSnapshotEntry.
public struct ContextCollapseSnapshotEntry: Sendable, Codable {
    public let type: String  // "marble-origami-snapshot"
    public let sessionID: String
    public let staged: [ContextCollapseStagedSpan]
    public let armed: Bool
    public let lastSpawnTokens: Int
}

/// Full file history snapshot (referenced in LogOption).
/// Matches CC's FileHistorySnapshot.
public struct FileHistorySnapshot: Sendable, Codable {
    public let files: [FileHistorySnapshotItem]
    public let timestamp: Date
}

/// Individual file state in a history snapshot.
public struct FileHistorySnapshotItem: Sendable, Codable {
    public let path: String
    public let content: String
    public let mtime: Int
}

/// The full Entry discriminated union matching CC's types/logs.ts:Entry.
/// 20 variants matching all CC Entry union members.
public enum LogEntry: Sendable, Codable {
    case transcript(SerializedMessage)
    case summary(SummaryEntry)
    case customTitle(CustomTitleEntry)
    case aiTitle(AiTitleEntry)
    case lastPrompt(LastPromptEntry)
    case taskSummary(TaskSummaryEntry)
    case tag(TagEntry)
    case agentName(AgentNameEntry)
    case agentColor(AgentColorEntry)
    case agentSetting(AgentSettingEntry)
    case prLink(PRLinkEntry)
    case fileHistorySnapshot(FileHistorySnapshotEntry)
    case attributionSnapshot(AttributionSnapshotEntry)
    case queueOperation(QueueOperationEntry)
    case speculationAccept(SpeculationAcceptEntry)
    case mode(ModeEntry)
    case worktreeState(WorktreeStateEntry)
    case contentReplacement(ContentReplacementEntry)
    case contextCollapseCommit(ContextCollapseCommitEntry)
    case contextCollapseSnapshot(ContextCollapseSnapshotEntry)
}
