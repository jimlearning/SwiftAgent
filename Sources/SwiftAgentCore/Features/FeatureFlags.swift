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
}
