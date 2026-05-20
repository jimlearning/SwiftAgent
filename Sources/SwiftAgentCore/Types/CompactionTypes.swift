import Foundation

// MARK: - CompactProgressEvent

/// Progress event emitted during compaction phases.
/// Matches Claude Code's CompactProgressEvent in Tool.ts.
public enum CompactProgressEvent: Sendable {
    /// Hook execution phase started.
    case hooksStart(hookType: CompactHookType)
    /// LLM-based compaction started.
    case compactStart
    /// LLM-based compaction completed.
    case compactEnd
}

/// Hook type for compaction progress events.
/// Matches CC's hookType: 'pre_compact' | 'post_compact' | 'session_start'.
public enum CompactHookType: String, Sendable {
    case preCompact = "pre_compact"
    case postCompact = "post_compact"
    case sessionStart = "session_start"
}

// MARK: - CompactionResult

/// Result of LLM-based conversation compaction.
/// Matches Claude Code's CompactionResult in services/compact/compact.ts.
public struct CompactionResult: Sendable {
    /// The compact_boundary system message marking the compaction point.
    public let boundaryMarker: SystemMessage
    /// LLM-generated summary messages (isCompactSummary: true).
    public let summaryMessages: [Message]
    /// Re-injected file attachments, plans, skills.
    public let attachments: [Message]
    /// Session start hook results.
    public let hookResults: [Message]
    /// Preserved messages (partial/reactive/session-memory compact only).
    public let messagesToKeep: [Message]?
    /// Message to show in UI.
    public let userDisplayMessage: String?
    /// Token estimate BEFORE compaction.
    public let preCompactTokenCount: Int?
    /// Compact API call's total usage (for event continuity).
    public let postCompactTokenCount: Int?
    /// Estimated size of resulting context.
    public let truePostCompactTokenCount: Int?
    /// API usage metrics from the compaction call.
    public let compactionUsage: Usage?

    public init(
        boundaryMarker: SystemMessage,
        summaryMessages: [Message],
        attachments: [Message],
        hookResults: [Message],
        messagesToKeep: [Message]? = nil,
        userDisplayMessage: String? = nil,
        preCompactTokenCount: Int? = nil,
        postCompactTokenCount: Int? = nil,
        truePostCompactTokenCount: Int? = nil,
        compactionUsage: Usage? = nil
    ) {
        self.boundaryMarker = boundaryMarker
        self.summaryMessages = summaryMessages
        self.attachments = attachments
        self.hookResults = hookResults
        self.messagesToKeep = messagesToKeep
        self.userDisplayMessage = userDisplayMessage
        self.preCompactTokenCount = preCompactTokenCount
        self.postCompactTokenCount = postCompactTokenCount
        self.truePostCompactTokenCount = truePostCompactTokenCount
        self.compactionUsage = compactionUsage
    }
}

// MARK: - RecompactionInfo

/// Information about recompaction (compaction of already-compacted context).
/// Matches Claude Code's RecompactionInfo in services/compact/compact.ts.
public struct RecompactionInfo: Sendable {
    /// Whether this is a re-compaction in a chain.
    public var isRecompactionInChain: Bool
    /// Number of turns since the previous compact.
    public var turnsSincePreviousCompact: Int
    /// UUID of the turn that triggered the last compact.
    public var previousCompactTurnId: String?
    /// Token threshold for autocompact.
    public var autoCompactThreshold: Int
    /// What triggered the query.
    public var querySource: QuerySource?

    public init(
        isRecompactionInChain: Bool = false,
        turnsSincePreviousCompact: Int = 0,
        previousCompactTurnId: String? = nil,
        autoCompactThreshold: Int = 0,
        querySource: QuerySource? = nil
    ) {
        self.isRecompactionInChain = isRecompactionInChain
        self.turnsSincePreviousCompact = turnsSincePreviousCompact
        self.previousCompactTurnId = previousCompactTurnId
        self.autoCompactThreshold = autoCompactThreshold
        self.querySource = querySource
    }
}

// MARK: - AutoCompactTrackingState

/// Tracks autocompact state across turns.
/// Matches Claude Code's AutoCompactTrackingState in services/compact/autoCompact.ts.
public struct AutoCompactTrackingState: Sendable {
    /// Whether compaction just occurred.
    public var compacted: Bool
    /// Turn counter since last compact.
    public var turnCounter: Int
    /// The turn ID that triggered autocompact.
    public var turnId: String
    /// Consecutive autocompact failures.
    public var consecutiveFailures: Int?

    public init(
        compacted: Bool = false,
        turnCounter: Int = 0,
        turnId: String = "",
        consecutiveFailures: Int? = nil
    ) {
        self.compacted = compacted
        self.turnCounter = turnCounter
        self.turnId = turnId
        self.consecutiveFailures = consecutiveFailures
    }
}

// NOTE: CompactTrigger is defined in HookJSONTypes.swift
// NOTE: CompactMetadata and CompactPreservedSegment are defined in SystemMessage.swift

// MARK: - MicrocompactResult

/// Result of microcompact (tool-result clearing without LLM).
/// Matches Claude Code's MicrocompactResult in services/compact/microCompact.ts.
public struct MicrocompactResult: Sendable {
    /// Messages after microcompact.
    public var messages: [Message]
    /// Optional compaction info (pending cache edits).
    public var compactionInfo: MicrocompactCompactionInfo?

    public init(
        messages: [Message],
        compactionInfo: MicrocompactCompactionInfo? = nil
    ) {
        self.messages = messages
        self.compactionInfo = compactionInfo
    }
}

/// CompactionInfo within MicrocompactResult.
public struct MicrocompactCompactionInfo: Sendable {
    public var pendingCacheEdits: PendingCacheEdits?

    public init(pendingCacheEdits: PendingCacheEdits? = nil) {
        self.pendingCacheEdits = pendingCacheEdits
    }
}

// MARK: - PendingCacheEdits

/// Pending cache_edits block for cached microcompact.
/// Matches Claude Code's PendingCacheEdits in services/compact/microCompact.ts.
public struct PendingCacheEdits: Sendable {
    public var trigger: String  // "auto"
    public var deletedToolIds: [String]
    public var baselineCacheDeletedTokens: Int

    public init(
        trigger: String = "auto",
        deletedToolIds: [String] = [],
        baselineCacheDeletedTokens: Int = 0
    ) {
        self.trigger = trigger
        self.deletedToolIds = deletedToolIds
        self.baselineCacheDeletedTokens = baselineCacheDeletedTokens
    }
}

// MARK: - TokenWarningState

/// Token usage warning/threshold state returned by calculateTokenWarningState.
/// Matches CC's return type in services/compact/autoCompact.ts:93.
public struct TokenWarningState: Sendable {
    public var percentLeft: Double
    public var isAboveWarningThreshold: Bool
    public var isAboveErrorThreshold: Bool
    public var isAboveAutoCompactThreshold: Bool
    public var isAtBlockingLimit: Bool

    public init(
        percentLeft: Double = 100,
        isAboveWarningThreshold: Bool = false,
        isAboveErrorThreshold: Bool = false,
        isAboveAutoCompactThreshold: Bool = false,
        isAtBlockingLimit: Bool = false
    ) {
        self.percentLeft = percentLeft
        self.isAboveWarningThreshold = isAboveWarningThreshold
        self.isAboveErrorThreshold = isAboveErrorThreshold
        self.isAboveAutoCompactThreshold = isAboveAutoCompactThreshold
        self.isAtBlockingLimit = isAtBlockingLimit
    }
}

// MARK: - AutoCompact Constants

/// Token budget constants matching CC's compaction thresholds.
public enum CompactionConstants {
    /// Buffer tokens added for autocompact threshold calculation.
    public static let autocompactBufferTokens = 13_000
    /// Buffer for warning threshold.
    public static let warningThresholdBufferTokens = 20_000
    /// Buffer for error threshold.
    public static let errorThresholdBufferTokens = 20_000
    /// Buffer for manual compact threshold.
    public static let manualCompactBufferTokens = 3_000
    /// Max consecutive autocompact failures before circuit breaker.
    public static let maxConsecutiveAutocompactFailures = 3
    /// Max output tokens for compaction summary LLM call.
    public static let maxOutputTokensForSummary = 20_000
    /// Max files to restore after compaction.
    public static let postCompactMaxFilesToRestore = 5
    /// Token budget for post-compact restoration.
    public static let postCompactTokenBudget = 50_000
    /// Max tokens per restored file.
    public static let postCompactMaxTokensPerFile = 5_000
    /// Max tokens per restored skill.
    public static let postCompactMaxTokensPerSkill = 5_000
    /// Token budget for post-compact skills.
    public static let postCompactSkillsTokenBudget = 25_000
}
