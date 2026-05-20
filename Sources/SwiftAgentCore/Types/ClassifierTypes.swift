import Foundation

// MARK: - Confidence

/// Confidence level for classifier results.
/// Matches Claude Code's `'high' | 'medium' | 'low'` string literal union in types/permissions.ts.
public enum Confidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
}

// MARK: - RiskLevel

/// Risk level for permission explanations.
/// Matches Claude Code's RiskLevel: `'LOW' | 'MEDIUM' | 'HIGH'` in types/permissions.ts:403.
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
}

// MARK: - ClassifierUsage

/// Token usage from a classifier API call.
/// Matches Claude Code's ClassifierUsage in types/permissions.ts:339-344.
public struct ClassifierUsage: Codable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }
}

// MARK: - ClassifierResult

/// Result from the permission classifier.
/// Matches Claude Code's ClassifierResult in types/permissions.ts:330-335.
public struct ClassifierResult: Codable, Sendable {
    public var matches: Bool
    public var matchedDescription: String?
    public var confidence: Confidence
    public var reason: String

    public init(
        matches: Bool,
        matchedDescription: String? = nil,
        confidence: Confidence = .low,
        reason: String = ""
    ) {
        self.matches = matches
        self.matchedDescription = matchedDescription
        self.confidence = confidence
        self.reason = reason
    }
}

// MARK: - ClassifierStage

/// Which classifier stage produced the final decision (2-stage XML classifier only).
/// Matches CC's `'fast' | 'thinking'` union.
public enum ClassifierStage: String, Codable, Sendable, CaseIterable {
    case fast
    case thinking
}

// MARK: - PromptLengths

/// Character lengths of prompt components sent to the classifier.
/// Matches CC's promptLengths in YoloClassifierResult.
public struct PromptLengths: Codable, Sendable {
    public var systemPrompt: Int
    public var toolCalls: Int
    public var userPrompts: Int

    public init(
        systemPrompt: Int = 0,
        toolCalls: Int = 0,
        userPrompts: Int = 0
    ) {
        self.systemPrompt = systemPrompt
        self.toolCalls = toolCalls
        self.userPrompts = userPrompts
    }
}

// MARK: - YoloClassifierResult

/// Full result from the YOLO (auto-mode) classifier model.
/// Matches Claude Code's YoloClassifierResult in types/permissions.ts:346-397.
public struct YoloClassifierResult: Codable, Sendable {
    public var thinking: String?
    public var shouldBlock: Bool
    public var reason: String
    public var unavailable: Bool?
    /// API returned "prompt is too long" — deterministic error, fall back to normal prompting.
    public var transcriptTooLong: Bool?
    public var model: String
    public var usage: ClassifierUsage?
    public var durationMs: Int?
    public var promptLengths: PromptLengths?
    public var errorDumpPath: String?
    public var stage: ClassifierStage?
    public var stage1Usage: ClassifierUsage?
    public var stage1DurationMs: Int?
    public var stage1RequestId: String?
    public var stage1MsgId: String?
    public var stage2Usage: ClassifierUsage?
    public var stage2DurationMs: Int?
    public var stage2RequestId: String?
    public var stage2MsgId: String?

    public init(
        thinking: String? = nil,
        shouldBlock: Bool = false,
        reason: String = "",
        unavailable: Bool? = nil,
        transcriptTooLong: Bool? = nil,
        model: String = "",
        usage: ClassifierUsage? = nil,
        durationMs: Int? = nil,
        promptLengths: PromptLengths? = nil,
        errorDumpPath: String? = nil,
        stage: ClassifierStage? = nil,
        stage1Usage: ClassifierUsage? = nil,
        stage1DurationMs: Int? = nil,
        stage1RequestId: String? = nil,
        stage1MsgId: String? = nil,
        stage2Usage: ClassifierUsage? = nil,
        stage2DurationMs: Int? = nil,
        stage2RequestId: String? = nil,
        stage2MsgId: String? = nil
    ) {
        self.thinking = thinking
        self.shouldBlock = shouldBlock
        self.reason = reason
        self.unavailable = unavailable
        self.transcriptTooLong = transcriptTooLong
        self.model = model
        self.usage = usage
        self.durationMs = durationMs
        self.promptLengths = promptLengths
        self.errorDumpPath = errorDumpPath
        self.stage = stage
        self.stage1Usage = stage1Usage
        self.stage1DurationMs = stage1DurationMs
        self.stage1RequestId = stage1RequestId
        self.stage1MsgId = stage1MsgId
        self.stage2Usage = stage2Usage
        self.stage2DurationMs = stage2DurationMs
        self.stage2RequestId = stage2RequestId
        self.stage2MsgId = stage2MsgId
    }
}

// MARK: - PermissionExplanation

/// Explanation attached to permission decisions.
/// Matches Claude Code's PermissionExplanation in types/permissions.ts:405-410.
public struct PermissionExplanation: Codable, Sendable {
    public var riskLevel: RiskLevel
    public var explanation: String
    public var reasoning: String
    public var risk: String

    public init(
        riskLevel: RiskLevel = .low,
        explanation: String = "",
        reasoning: String = "",
        risk: String = ""
    ) {
        self.riskLevel = riskLevel
        self.explanation = explanation
        self.reasoning = reasoning
        self.risk = risk
    }
}
