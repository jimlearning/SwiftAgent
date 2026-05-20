import Foundation

// MARK: - System Message Level

/// Severity level for system informational messages. Matches CC's SystemMessageLevel.
public enum SystemMessageLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

// MARK: - System Message Discriminated Union

/// Complete SystemMessage discriminated union matching Claude Code's 15 subtypes.
/// CC discriminates by the `subtype` field. Swift represents this as an enum with associated values.
public enum SystemMessageSubtype: Sendable {
    /// subtype: "informational"
    case informational(content: String, level: SystemMessageLevel, isMeta: Bool, preventContinuation: Bool?)

    /// subtype: "permission_retry"
    case permissionRetry(content: String, commands: [String])

    /// subtype: "bridge_status"
    case bridgeStatus(content: String, url: String, upgradeNudge: String?)

    /// subtype: "scheduled_task_fire"
    case scheduledTaskFire(content: String)

    /// subtype: "stop_hook_summary"
    case stopHookSummary(
        hookCount: Int,
        hookInfos: [StopHookInfo],
        hookErrors: [String],
        preventedContinuation: Bool,
        stopReason: String?,
        hasOutput: Bool,
        level: SystemMessageLevel,
        toolUseID: String?,
        hookLabel: String?,
        totalDurationMs: Int?
    )

    /// subtype: "turn_duration"
    case turnDuration(
        durationMs: Int,
        budgetTokens: Int?,
        budgetLimit: Int?,
        budgetNudges: Int?,
        messageCount: Int?
    )

    /// subtype: "away_summary"
    case awaySummary(content: String)

    /// subtype: "memory_saved"
    case memorySaved(writtenPaths: [String])

    /// subtype: "agents_killed" — empty signal message
    case agentsKilled

    /// subtype: "api_metrics"
    case apiMetrics(
        ttftMs: Int,
        otps: Double,
        isP50: Bool?,
        hookDurationMs: Int?,
        turnDurationMs: Int?,
        toolDurationMs: Int?,
        classifierDurationMs: Int?,
        toolCount: Int?,
        hookCount: Int?,
        classifierCount: Int?,
        configWriteCount: Int?
    )

    /// subtype: "local_command"
    case localCommand(content: String)

    /// subtype: "compact_boundary"
    case compactBoundary(content: String, level: SystemMessageLevel, compactMetadata: CompactMetadata, logicalParentUuid: String?)

    /// subtype: "microcompact_boundary"
    case microcompactBoundary(content: String, level: SystemMessageLevel, microcompactMetadata: MicrocompactMetadata)

    /// subtype: "api_error"
    case apiError(level: SystemMessageLevel, errorMessage: String, retryInMs: Int, retryAttempt: Int, maxRetries: Int, cause: String?)

    /// subtype: "file_snapshot"
    case fileSnapshot(content: String, level: SystemMessageLevel, snapshotFiles: [SnapshotFileEntry])
}

// MARK: - Subtype Literal

extension SystemMessageSubtype {
    /// The CC subtype literal string.
    public var subtypeLiteral: String {
        switch self {
        case .informational: return "informational"
        case .permissionRetry: return "permission_retry"
        case .bridgeStatus: return "bridge_status"
        case .scheduledTaskFire: return "scheduled_task_fire"
        case .stopHookSummary: return "stop_hook_summary"
        case .turnDuration: return "turn_duration"
        case .awaySummary: return "away_summary"
        case .memorySaved: return "memory_saved"
        case .agentsKilled: return "agents_killed"
        case .apiMetrics: return "api_metrics"
        case .localCommand: return "local_command"
        case .compactBoundary: return "compact_boundary"
        case .microcompactBoundary: return "microcompact_boundary"
        case .apiError: return "api_error"
        case .fileSnapshot: return "file_snapshot"
        }
    }
}

// MARK: - Supporting Types

/// Stop hook info for stop_hook_summary messages. Matches CC's StopHookInfo.
public struct StopHookInfo: Codable, Sendable {
    public let name: String
    public let durationMs: Int
    public let hasOutput: Bool
    public let outputType: String?  // "sync" | "async"

    public init(name: String, durationMs: Int, hasOutput: Bool, outputType: String? = nil) {
        self.name = name
        self.durationMs = durationMs
        self.hasOutput = hasOutput
        self.outputType = outputType
    }
}

/// Metadata for compact_boundary messages. Matches CC's CompactMetadata.
public struct CompactMetadata: Codable, Sendable {
    public let trigger: CompactTrigger
    public let preTokens: Int
    public let userContext: String?
    public let messagesSummarized: Int?
    public let preservedSegment: CompactPreservedSegment?

    public init(
        trigger: CompactTrigger,
        preTokens: Int,
        userContext: String? = nil,
        messagesSummarized: Int? = nil,
        preservedSegment: CompactPreservedSegment? = nil
    ) {
        self.trigger = trigger
        self.preTokens = preTokens
        self.userContext = userContext
        self.messagesSummarized = messagesSummarized
        self.preservedSegment = preservedSegment
    }
}

/// Preserved message segment for compaction boundary. Matches CC.
public struct CompactPreservedSegment: Codable, Sendable {
    public let headUuid: String
    public let anchorUuid: String
    public let tailUuid: String

    public init(headUuid: String, anchorUuid: String, tailUuid: String) {
        self.headUuid = headUuid
        self.anchorUuid = anchorUuid
        self.tailUuid = tailUuid
    }
}

/// Metadata for microcompact_boundary messages. Matches CC's microcompact metadata.
public struct MicrocompactMetadata: Codable, Sendable {
    public let trigger: CompactTrigger  // always "auto" for microcompact
    public let preTokens: Int
    public let tokensSaved: Int
    public let compactedToolIds: [String]
    public let clearedAttachmentUUIDs: [String]

    public init(
        trigger: CompactTrigger = .auto,
        preTokens: Int,
        tokensSaved: Int,
        compactedToolIds: [String] = [],
        clearedAttachmentUUIDs: [String] = []
    ) {
        self.trigger = trigger
        self.preTokens = preTokens
        self.tokensSaved = tokensSaved
        self.compactedToolIds = compactedToolIds
        self.clearedAttachmentUUIDs = clearedAttachmentUUIDs
    }
}

/// File snapshot entry for file_snapshot messages. Matches CC.
public struct SnapshotFileEntry: Codable, Sendable {
    public let key: String
    public let path: String
    public let content: String

    public init(key: String, path: String, content: String) {
        self.key = key
        self.path = path
        self.content = content
    }
}

// MARK: - SystemMessage Container

/// Full system message combining base fields with a discriminated subtype.
/// Matches CC's SystemMessage = { type: 'system', uuid, timestamp, ...subtype-specific fields }.
public struct SystemMessage: Sendable, Identifiable {
    /// UUID matching CC's uuid.
    public let uuid: String
    /// ISO 8601 timestamp matching CC's timestamp.
    public let timestamp: Date
    /// The discriminated subtype with type-specific data.
    public let subtype: SystemMessageSubtype

    public var id: String { uuid }

    public init(uuid: String = UUID().uuidString, timestamp: Date = Date(), subtype: SystemMessageSubtype) {
        self.uuid = uuid
        self.timestamp = timestamp
        self.subtype = subtype
    }
}
