import Foundation

// MARK: - Permission Mode

/// Permission mode determining how tool execution is authorized.
/// Matches Claude Code's PermissionMode.
public enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case `default`
    case plan
    case acceptEdits
    case bypassPermissions
    case dontAsk
    case auto
    case bubble
}

// MARK: - Permission Behavior & Rules

/// Permission behavior — allow, deny, or ask.
/// Matches Claude Code's PermissionBehavior.
public enum PermissionBehavior: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

/// The value of a permission rule — which tool and optional content.
/// Matches Claude Code's PermissionRuleValue.
public struct PermissionRuleValue: Codable, Sendable, Equatable {
    public let toolName: String
    public let ruleContent: String?

    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }

    /// Check if a content string matches this rule's content pattern.
    /// Supports wildcard patterns: "git *" matches "git push", "git commit", etc.
    public func matchesContent(_ content: String) -> Bool {
        guard let ruleContent = ruleContent, !ruleContent.isEmpty else { return false }
        // Wildcard match: "git *" matches "git push", "git commit", etc.
        if ruleContent.hasSuffix("*") {
            let prefix = String(ruleContent.dropLast())
            return content.hasPrefix(prefix)
        }
        // Exact match
        return content == ruleContent
    }
}

/// A permission rule with its source and behavior.
/// Matches Claude Code's PermissionRule: { source, ruleBehavior, ruleValue }.
public struct PermissionRule: Codable, Sendable, Identifiable {
    public let source: PermissionRuleSource
    public let ruleBehavior: PermissionBehavior
    public let ruleValue: PermissionRuleValue

    public var id: String { "\(source.rawValue):\(ruleValue.toolName):\(ruleValue.ruleContent ?? "")" }

    public init(
        source: PermissionRuleSource = .userSettings,
        ruleBehavior: PermissionBehavior = .ask,
        ruleValue: PermissionRuleValue
    ) {
        self.source = source
        self.ruleBehavior = ruleBehavior
        self.ruleValue = ruleValue
    }
}

/// Simple permission decision enum (used by PermissionVerdict).
/// Matches Claude Code's basic allow/deny/ask.
public enum PermissionDecision: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

/// Where a permission rule originated from.
/// Matches Claude Code's PermissionRuleSource (union of SettingSource values + extras).
public enum PermissionRuleSource: String, Codable, Sendable, CaseIterable, Hashable {
    case userSettings
    case projectSettings
    case localSettings
    case flagSettings
    case policySettings
    case cliArg
    case command
    case session
}

/// Where a permission update should be saved.
/// Matches Claude Code's PermissionUpdateDestination.
public enum PermissionUpdateDestination: String, Codable, Sendable {
    case userSettings
    case projectSettings
    case localSettings
    case session
    case cliArg
}

// MARK: - Permission Verdict

/// Lightweight permission verdict for simple checks.
public struct PermissionVerdict: Sendable {
    public let decision: PermissionDecision
    public let reason: String?
    public let matchedRule: PermissionRule?

    public init(decision: PermissionDecision, reason: String? = nil, matchedRule: PermissionRule? = nil) {
        self.decision = decision
        self.reason = reason
        self.matchedRule = matchedRule
    }
}

// MARK: - Permission Updates

/// A permission update — add, replace, remove rules; set mode; add/remove directories.
/// Matches Claude Code's PermissionUpdate discriminated union.
public enum PermissionUpdate: Sendable {
    case addRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case replaceRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case removeRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case setMode(mode: PermissionMode, destination: PermissionUpdateDestination)
    case addDirectories(directories: [String], destination: PermissionUpdateDestination)
    case removeDirectories(directories: [String], destination: PermissionUpdateDestination)
}

// MARK: - Permission Decision Reasons

/// Explanation of why a permission decision was made.
/// Matches Claude Code's PermissionDecisionReason discriminated union.
public enum PermissionDecisionReason: Sendable {
    /// Decision derived from a specific permission rule.
    case rule(PermissionRule)
    /// Decision derived from the current permission mode.
    case mode(PermissionMode)
    /// Decision derived from subcommand results (compound commands).
    case subcommandResults(reasons: [String: PermissionResultBehavior])
    /// Decision set by a permission prompt tool.
    case permissionPromptTool(permissionPromptToolName: String, toolResult: JSONValue)
    /// Decision derived from a hook.
    /// CC carries hookName (the hook matcher key) and optional hookSource/reason metadata.
    case hook(hookName: String, hookSource: String? = nil, reason: String? = nil)
    /// Decision derived from an async agent.
    case asyncAgent(reason: String)
    /// Decision derived from sandbox override.
    case sandboxOverride(reason: SandboxOverrideReason)
    /// Decision derived from a classifier.
    case classifier(classifier: String, reason: String)
    /// Decision derived from working directory rules.
    case workingDir(reason: String)
    /// Decision derived from a safety check.
    case safetyCheck(reason: String, classifierApprovable: Bool)
    /// Decision with no specific categorization.
    case other(reason: String)
}

/// Reason for sandbox override permission decisions.
/// Matches Claude Code's sandboxOverride reason union: 'excludedCommand' | 'dangerouslyDisableSandbox'.
public enum SandboxOverrideReason: String, Sendable {
    case excludedCommand
    case dangerouslyDisableSandbox
}

/// Simple behavior result for subcommand aggregation.
public enum PermissionResultBehavior: String, Sendable {
    case allow
    case deny
    case ask
    case passthrough
}

// MARK: - Permission Results

/// Permission metadata for UI display. Matches CC's PermissionMetadata.
/// Metadata for a permission command (tool invocation context).
/// Matches Claude Code's PermissionCommandMetadata: { name, description?, [key: unknown] }.
public struct PermissionCommandMetadata: Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// Metadata attached to permission decisions for UI/shell context.
/// Matches Claude Code's PermissionMetadata: { command: PermissionCommandMetadata } | undefined.
public struct PermissionMetadata: Sendable {
    public let command: PermissionCommandMetadata?

    public init(command: PermissionCommandMetadata? = nil) {
        self.command = command
    }
}

/// Pending classifier check for async auto-mode evaluation.
/// Matches Claude Code's PendingClassifierCheck: { command: string, cwd: string, descriptions: string[] }.
public struct PendingClassifierCheck: Sendable {
    public let command: String
    public let cwd: String
    public let descriptions: [String]

    public init(
        command: String,
        cwd: String,
        descriptions: [String] = []
    ) {
        self.command = command
        self.cwd = cwd
        self.descriptions = descriptions
    }
}

/// Full permission decision — allow with optional input modifications.
/// Matches Claude Code's PermissionAllowDecision.
public struct PermissionAllowDecision: Sendable {
    public let behavior: PermissionBehavior  // always .allow
    public let updatedInput: [String: JSONValue]?
    public let decisionReason: PermissionDecisionReason?
    public let toolUseID: String?
    /// Whether the user modified the tool input before approving.
    /// Matches CC's userModified field.
    public let userModified: Bool
    /// Feedback string from user approval dialog.
    /// Matches CC's acceptFeedback field.
    public let acceptFeedback: String?
    /// Content blocks to render with the permission result.
    /// Matches CC's contentBlocks field.
    public let contentBlocks: [ContentBlock]?

    public init(
        updatedInput: [String: JSONValue]? = nil,
        decisionReason: PermissionDecisionReason? = nil,
        toolUseID: String? = nil,
        userModified: Bool = false,
        acceptFeedback: String? = nil,
        contentBlocks: [ContentBlock]? = nil
    ) {
        self.behavior = .allow
        self.updatedInput = updatedInput
        self.decisionReason = decisionReason
        self.toolUseID = toolUseID
        self.userModified = userModified
        self.acceptFeedback = acceptFeedback
        self.contentBlocks = contentBlocks
    }
}

/// Full permission ask decision — prompt the user.
/// Matches Claude Code's PermissionAskDecision.
public struct PermissionAskDecision: Sendable {
    public let behavior: PermissionBehavior  // always .ask
    public let message: String
    public let updatedInput: [String: JSONValue]?
    public let decisionReason: PermissionDecisionReason?
    public let suggestions: [PermissionUpdate]?
    /// Blocked file/directory path for display.
    /// Matches CC's blockedPath field.
    public let blockedPath: String?
    /// Metadata for permission prompt UI.
    /// Matches CC's metadata field.
    public let metadata: PermissionMetadata?
    /// Pending classifier check for auto-mode.
    /// Matches CC's pendingClassifierCheck field.
    public let pendingClassifierCheck: PendingClassifierCheck?
    /// Content blocks for the permission prompt.
    /// Matches CC's contentBlocks field.
    public let contentBlocks: [ContentBlock]?
    /// Whether this is a Bash security check for command misparsing.
    /// Matches CC's isBashSecurityCheckForMisparsing field.
    public let isBashSecurityCheckForMisparsing: Bool

    public init(
        message: String,
        updatedInput: [String: JSONValue]? = nil,
        decisionReason: PermissionDecisionReason? = nil,
        suggestions: [PermissionUpdate]? = nil,
        blockedPath: String? = nil,
        metadata: PermissionMetadata? = nil,
        pendingClassifierCheck: PendingClassifierCheck? = nil,
        contentBlocks: [ContentBlock]? = nil,
        isBashSecurityCheckForMisparsing: Bool = false
    ) {
        self.behavior = .ask
        self.message = message
        self.updatedInput = updatedInput
        self.decisionReason = decisionReason
        self.suggestions = suggestions
        self.blockedPath = blockedPath
        self.metadata = metadata
        self.pendingClassifierCheck = pendingClassifierCheck
        self.contentBlocks = contentBlocks
        self.isBashSecurityCheckForMisparsing = isBashSecurityCheckForMisparsing
    }
}

/// Full permission deny decision.
/// Matches Claude Code's PermissionDenyDecision.
public struct PermissionDenyDecision: Sendable {
    public let behavior: PermissionBehavior  // always .deny
    public let message: String
    public let decisionReason: PermissionDecisionReason
    public let toolUseID: String?

    public init(
        message: String,
        decisionReason: PermissionDecisionReason,
        toolUseID: String? = nil
    ) {
        self.behavior = .deny
        self.message = message
        self.decisionReason = decisionReason
        self.toolUseID = toolUseID
    }
}

/// Response to a permission prompt (user-facing ask decision).
/// Matches CC's user response to permission dialogs.
public enum PermissionPromptResponse: Sendable {
    case allow
    case deny(reason: String)
}

/// Callback invoked when a tool requests interactive permission (ask).
/// The caller presents a UI prompt and returns the user's decision.
/// Matches CC's permission prompt flow in the TUI layer.
public typealias PermissionPromptHandler = @Sendable (
    _ toolName: String,
    _ toolUseID: String,
    _ decision: PermissionAskDecision
) async -> PermissionPromptResponse

/// The full permission result with passthrough support.
/// Matches Claude Code's PermissionResult.
public enum PermissionResult: Sendable {
    case allow(PermissionAllowDecision)
    case ask(PermissionAskDecision)
    case deny(PermissionDenyDecision)
    /// Passthrough — no decision made, let the caller handle it.
    /// Matches CC's non-decision PermissionResult variant with all fields.
    case passthrough(
        message: String,
        decisionReason: PermissionDecisionReason?,
        suggestions: [PermissionUpdate]?,
        blockedPath: String?,
        pendingClassifierCheck: PendingClassifierCheck?
    )
}

// MARK: - Denial Tracking

/// Tracks permission denials for rate limiting.
/// Matches Claude Code's denial tracking system.
public struct DenialTrackingState: Sendable {
    public var consecutiveDenials: Int = 0
    public var totalDenials: Int = 0
    public var lastDenialTime: Date?
    public var isAutoModeBlocked: Bool = false

    public init() {}

    /// Record a denial and update tracking state.
    public mutating func recordDenial() {
        consecutiveDenials += 1
        totalDenials += 1
        lastDenialTime = Date()
        if consecutiveDenials >= 3 {
            isAutoModeBlocked = true
        }
    }

    /// Record a successful permission grant.
    public mutating func recordSuccess() {
        consecutiveDenials = 0
        isAutoModeBlocked = false
    }

    /// Check if the model should fall back to prompting based on denial history.
    public func shouldFallbackToPrompting() -> Bool {
        consecutiveDenials >= 3
    }

    /// Denial limits matching Claude Code.
    public enum Limits {
        public static let maxConsecutiveDenials = 3
        public static let maxTotal = 20
        public static let autoModeBlockThreshold = 3
    }
}

// MARK: - Additional Working Directory

/// An additional directory included in permission scope.
/// Matches Claude Code's AdditionalWorkingDirectory.
public struct AdditionalWorkingDirectory: Sendable, Codable {
    public let path: String
    public let source: PermissionRuleSource

    public init(path: String, source: PermissionRuleSource) {
        self.path = path
        self.source = source
    }
}
