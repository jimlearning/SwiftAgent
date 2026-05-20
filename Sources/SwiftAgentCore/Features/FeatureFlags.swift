import Foundation

/// Feature flag value — boolean or string for A/B testing.
public enum FeatureValue: Sendable, Equatable {
    case boolean(Bool)
    case string(String)
}

/// Manages compile-time and runtime feature flags.
/// Supports dead-code elimination via `#if SWIFT_AGENT_FEATURE_*` checks.
public struct FeatureFlags: Sendable {
    private var flags: [String: FeatureValue]

    public init(flags: [String: FeatureValue] = [:]) {
        self.flags = flags
    }

    /// Set a feature flag.
    public mutating func set(_ key: String, value: FeatureValue) {
        flags[key] = value
    }

    /// Get a feature flag value.
    public func get(_ key: String) -> FeatureValue? {
        flags[key]
    }

    /// Check if a boolean feature is enabled (default: false).
    public func isEnabled(_ key: String) -> Bool {
        if case .boolean(let v) = flags[key] { return v }
        return false
    }

    /// Get a string feature value (default: nil).
    public func stringValue(_ key: String) -> String? {
        if case .string(let v) = flags[key] { return v }
        return nil
    }

    /// Remove a feature flag.
    public mutating func remove(_ key: String) {
        flags.removeValue(forKey: key)
    }

    /// Merge another flags set, overwriting existing keys.
    public mutating func merge(_ other: FeatureFlags) {
        for (key, value) in other.flags {
            flags[key] = value
        }
    }

    /// All registered flag keys.
    public var allKeys: [String] {
        Array(flags.keys).sorted()
    }

    // MARK: - Known Flags

    public static let defaults = FeatureFlags(flags: [
        "mcp": .boolean(true),
        "worktree_isolation": .boolean(true),
        "streaming_output": .boolean(true),
        "auto_compact": .boolean(true),
        "telemetry": .boolean(false)
    ])

    // MARK: - CC-Matching Feature Flag Gating Functions

    // MARK: - CC-Matching Environment Helpers

    /// Matches CC's isEnvTruthy(): "1", "true", "yes", "on" (case-insensitive).
    /// CC: utils/envUtils.ts
    private static func isEnvTruthy(_ value: String?) -> Bool {
        guard let v = value else { return false }
        let l = v.lowercased()
        return l == "1" || l == "true" || l == "yes" || l == "on"
    }

    /// Matches CC's isEnvDefinedFalsy(): "0", "false", "no", "off" (case-insensitive,
    /// only when the variable is set). CC: utils/envUtils.ts
    private static func isEnvDefinedFalsy(_ value: String?) -> Bool {
        guard let v = value else { return false }
        let l = v.lowercased()
        return l == "0" || l == "false" || l == "no" || l == "off"
    }

    /// Matches CC's isTodoV2Enabled(): checks CLAUDE_CODE_ENABLE_TASKS env var
    /// and non-interactive session state. When true, TaskCreate/Get/List/Update
    /// are enabled and TodoWrite is disabled (they're mutually exclusive in CC).
    public static func isTodoV2Enabled() -> Bool {
        return isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_ENABLE_TASKS"])
    }

    /// Matches CC's isAgentSwarmsEnabled(): ant users always on; external users
    /// require CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env or --agent-teams flag.
    /// CC: utils/agentSwarmsEnabled.ts
    public static func isAgentSwarmsEnabled() -> Bool {
        let userType = ProcessInfo.processInfo.environment["USER_TYPE"] ?? ""
        if userType == "ant" { return true }
        if isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"]) {
            return true
        }
        // CC also checks --agent-teams CLI flag via process.argv
        if CommandLine.arguments.contains("--agent-teams") {
            return true
        }
        return false
    }

    /// Matches CC's isKairosCronEnabled(): available to ant users and when
    /// CLAUDE_CODE_ENABLE_CRON is set. Guarded by CLAUDE_CODE_DISABLE_CRON.
    public static func isKairosCronEnabled() -> Bool {
        if isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_DISABLE_CRON"]) {
            return false
        }
        let userType = ProcessInfo.processInfo.environment["USER_TYPE"] ?? ""
        if userType == "ant" { return true }
        return isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_ENABLE_CRON"])
    }

    /// Matches CC's isToolSearchEnabledOptimistic(): checks if tool search
    /// mode is active. Returns true unless ENABLE_TOOL_SEARCH is set to falsy
    /// (standard mode). CC: utils/toolSearch.ts
    public static func isToolSearchEnabled() -> Bool {
        // CC: CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS forces standard mode
        if isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"]) {
            return false
        }
        // ENABLE_TOOL_SEARCH explicitly set to falsy → standard mode
        if isEnvDefinedFalsy(ProcessInfo.processInfo.environment["ENABLE_TOOL_SEARCH"]) {
            return false
        }
        return true // CC default: tool search enabled
    }

    /// Matches CC's channels guard: EnterPlanMode/ExitPlanModeV2/AskUserQuestion
    /// are disabled when KAIROS channels are active.
    public static func isChannelsActive() -> Bool {
        return isEnvTruthy(ProcessInfo.processInfo.environment["CLAUDE_CODE_CHANNELS"])
    }

    /// Matches CC's LSP tool gate: requires ENABLE_LSP_TOOL env var.
    /// CC: isEnvTruthy(process.env.ENABLE_LSP_TOOL)
    public static func isLSPEnabled() -> Bool {
        return isEnvTruthy(ProcessInfo.processInfo.environment["ENABLE_LSP_TOOL"])
    }

    /// Matches CC's PowerShell tool gate: Windows-only.
    public static func isPowerShellToolEnabled() -> Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    /// Matches CC's Worktree mode gate.
    public static func isWorktreeModeEnabled() -> Bool {
        if let v = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENABLE_WORKTREE"] {
            return !isEnvDefinedFalsy(v)
        }
        return true // CC default: worktree available
    }
}
