import Foundation

/// Log/transcript entry types matching CC's types/logs.ts Entry discriminated union.
/// These represent the various entry types that can appear in a session transcript.

/// A message serialized for log/transcript storage with metadata.
/// Matches CC's TranscriptMessage (which extends SerializedMessage with parent tracking fields).
public struct SerializedMessage: Sendable, Codable {
    /// Unique identifier for this serialized entry (for parent/child tracking).
    /// Matches CC's TranscriptMessage.uuid.
    public var uuid: String
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

    enum CodingKeys: String, CodingKey {
        case uuid
        case message
        case cwd
        case userType
        case entrypoint
        case sessionID = "sessionId"
        case timestamp
        case version
        case gitBranch
        case slug
        case parentUuid
        case logicalParentUuid
        case isSidechain
        case agentId
        case teamName
        case agentName
        case agentColor
        case promptId
    }

    public init(
        uuid: String = UUID().uuidString,
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
        self.uuid = uuid
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

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case customTitle
    }

    public init(type: String = "custom-title", sessionID: String, customTitle: String) {
        self.type = type
        self.sessionID = sessionID
        self.customTitle = customTitle
    }
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
    public let leafUuid: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case lastPrompt
        case leafUuid
    }

    public init(type: String = "last-prompt", sessionID: String, lastPrompt: String, leafUuid: String? = nil) {
        self.type = type
        self.sessionID = sessionID
        self.lastPrompt = lastPrompt
        self.leafUuid = leafUuid
    }
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
///
/// ## JSON Format (CC-compatible flat type-discriminator)
/// Each entry is a flat JSON object with a `"type"` field discriminator,
/// plus the fields of the associated value merged at the top level.
/// e.g. `{"type":"transcript","message":{...},"cwd":"...","sessionId":"..."}`
///
/// Serialization is handled by `TranscriptStore` via `JSONSerialization`
/// to ensure CC-compatible flat format. Standard `Codable` is auto-synthesized
/// for Swift-native encoding (used in tests, etc.).
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
    /// Unknown/unsupported entry type — preserved as raw JSON data for round-tripping.
    case unknown(type: String, rawJSON: Data)

    // MARK: - Type Discriminator

    public var typeName: String {
        switch self {
        case .transcript: return "transcript"
        case .summary: return "summary"
        case .customTitle: return "custom-title"
        case .aiTitle: return "ai-title"
        case .lastPrompt: return "last-prompt"
        case .taskSummary: return "task-summary"
        case .tag: return "tag"
        case .agentName: return "agent-name"
        case .agentColor: return "agent-color"
        case .agentSetting: return "agent-setting"
        case .prLink: return "pr-link"
        case .fileHistorySnapshot: return "file-history-snapshot"
        case .attributionSnapshot: return "attribution-snapshot"
        case .queueOperation: return "queue-operation"
        case .speculationAccept: return "speculation-accept"
        case .mode: return "mode"
        case .worktreeState: return "worktree-state"
        case .contentReplacement: return "content-replacement"
        case .contextCollapseCommit: return "marble-origami-commit"
        case .contextCollapseSnapshot: return "marble-origami-snapshot"
        case .unknown(let type, _): return type
        }
    }
}

// MARK: - CC-compatible flat JSON serialization

extension LogEntry {
    /// Encode to a CC-compatible flat JSON dict (injecting "type" field).
    public func toFlatDict() throws -> [String: Any] {
        let encoder = JSONEncoder()
        switch self {
        case .transcript(let msg):
            var dict = try Self.encodeStruct(msg, with: encoder)
            dict["type"] = "transcript"
            return dict
        case .summary(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "summary"
            return dict
        case .customTitle(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "custom-title"
            return dict
        case .aiTitle(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "ai-title"
            return dict
        case .lastPrompt(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "last-prompt"
            return dict
        case .taskSummary(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "task-summary"
            return dict
        case .tag(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "tag"
            return dict
        case .agentName(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "agent-name"
            return dict
        case .agentColor(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "agent-color"
            return dict
        case .agentSetting(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "agent-setting"
            return dict
        case .prLink(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "pr-link"
            return dict
        case .fileHistorySnapshot(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "file-history-snapshot"
            return dict
        case .attributionSnapshot(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "attribution-snapshot"
            return dict
        case .queueOperation(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "queue-operation"
            return dict
        case .speculationAccept(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "speculation-accept"
            return dict
        case .mode(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "mode"
            return dict
        case .worktreeState(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "worktree-state"
            return dict
        case .contentReplacement(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "content-replacement"
            return dict
        case .contextCollapseCommit(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "marble-origami-commit"
            return dict
        case .contextCollapseSnapshot(let e):
            var dict = try Self.encodeStruct(e, with: encoder)
            dict["type"] = "marble-origami-snapshot"
            return dict
        case .unknown(_, let rawJSON):
            return (try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any]) ?? [:]
        }
    }

    /// Decode from a CC-compatible flat JSON dict (reading "type" field).
    public static func fromFlatDict(_ dict: [String: Any]) -> LogEntry {
        guard let typeStr = dict["type"] as? String else {
            let fallbackData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            return .unknown(type: "unknown", rawJSON: fallbackData)
        }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        let decoder = JSONDecoder()
        switch typeStr {
        case "transcript":
            if let msg = try? decoder.decode(SerializedMessage.self, from: data) {
                return .transcript(msg)
            }
        case "summary":
            if let e = try? decoder.decode(SummaryEntry.self, from: data) {
                return .summary(e)
            }
        case "custom-title":
            if let e = try? decoder.decode(CustomTitleEntry.self, from: data) {
                return .customTitle(e)
            }
        case "ai-title":
            if let e = try? decoder.decode(AiTitleEntry.self, from: data) {
                return .aiTitle(e)
            }
        case "last-prompt":
            if let e = try? decoder.decode(LastPromptEntry.self, from: data) {
                return .lastPrompt(e)
            }
        case "task-summary":
            if let e = try? decoder.decode(TaskSummaryEntry.self, from: data) {
                return .taskSummary(e)
            }
        case "tag":
            if let e = try? decoder.decode(TagEntry.self, from: data) {
                return .tag(e)
            }
        case "agent-name":
            if let e = try? decoder.decode(AgentNameEntry.self, from: data) {
                return .agentName(e)
            }
        case "agent-color":
            if let e = try? decoder.decode(AgentColorEntry.self, from: data) {
                return .agentColor(e)
            }
        case "agent-setting":
            if let e = try? decoder.decode(AgentSettingEntry.self, from: data) {
                return .agentSetting(e)
            }
        case "pr-link":
            if let e = try? decoder.decode(PRLinkEntry.self, from: data) {
                return .prLink(e)
            }
        case "file-history-snapshot":
            if let e = try? decoder.decode(FileHistorySnapshotEntry.self, from: data) {
                return .fileHistorySnapshot(e)
            }
        case "attribution-snapshot":
            if let e = try? decoder.decode(AttributionSnapshotEntry.self, from: data) {
                return .attributionSnapshot(e)
            }
        case "queue-operation":
            if let e = try? decoder.decode(QueueOperationEntry.self, from: data) {
                return .queueOperation(e)
            }
        case "speculation-accept":
            if let e = try? decoder.decode(SpeculationAcceptEntry.self, from: data) {
                return .speculationAccept(e)
            }
        case "mode":
            if let e = try? decoder.decode(ModeEntry.self, from: data) {
                return .mode(e)
            }
        case "worktree-state":
            if let e = try? decoder.decode(WorktreeStateEntry.self, from: data) {
                return .worktreeState(e)
            }
        case "content-replacement":
            if let e = try? decoder.decode(ContentReplacementEntry.self, from: data) {
                return .contentReplacement(e)
            }
        case "marble-origami-commit":
            if let e = try? decoder.decode(ContextCollapseCommitEntry.self, from: data) {
                return .contextCollapseCommit(e)
            }
        case "marble-origami-snapshot":
            if let e = try? decoder.decode(ContextCollapseSnapshotEntry.self, from: data) {
                return .contextCollapseSnapshot(e)
            }
        default:
            break
        }
        return .unknown(type: typeStr, rawJSON: data)
    }

    private static func encodeStruct<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
