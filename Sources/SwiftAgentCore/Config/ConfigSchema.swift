import Foundation

/// Schema-based config validation.
/// Provides validation and migration utilities for settings.
public struct ConfigSchema: Sendable {
    public init() {}

    /// Validate settings and return a list of issues.
    public func validate(_ settings: Settings) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []

        // Validate maxTokens
        if settings.maxTokens < 1000 {
            issues.append(ConfigIssue(severity: .error, path: "maxTokens", message: "maxTokens must be >= 1000"))
        }
        if settings.maxTokens > 2_000_000 {
            issues.append(ConfigIssue(severity: .warning, path: "maxTokens", message: "maxTokens is very large"))
        }

        // Validate model
        let registry = ModelRegistry.shared
        if registry.info(for: settings.model.modelID) == nil {
            issues.append(ConfigIssue(severity: .warning, path: "model.modelID", message: "Unknown model: \(settings.model.modelID)"))
        }

        return issues
    }

    /// Check if settings are valid (no errors).
    public func isValid(_ settings: Settings) -> Bool {
        !validate(settings).contains { $0.severity == .error }
    }

    /// Migrate settings from an older version.
    public func migrate(_ settings: Settings, fromVersion: String) -> Settings {
        // Future: handle version-specific migrations
        _ = fromVersion
        return settings
    }
}

public struct ConfigIssue: Sendable {
    public let severity: ConfigIssueSeverity
    public let path: String
    public let message: String
}

public enum ConfigIssueSeverity: String, Sendable {
    case error
    case warning
    case info
}
