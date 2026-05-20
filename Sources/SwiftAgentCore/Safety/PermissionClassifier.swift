import Foundation

// MARK: - Classifier Protocol

/// Protocol for auto-mode permission classification.
/// In production, backed by a Haiku model call. For now, uses config-based lists
/// with an extensible architecture for future LLM integration.
public protocol PermissionClassifying: Sendable {
    /// Classify a tool use request in auto mode.
    /// Returns the classification result: allow, deny, ask, or classify (needs LLM).
    func classify(
        toolName: String,
        input: String,
        config: AutoModeConfig?
    ) async -> ClassifierDecision
}

// MARK: - Classifier Result

/// Result of auto-mode classification.
public enum ClassifierDecision: Sendable {
    /// Allow the tool execution.
    case allow(reason: String)
    /// Deny the tool execution.
    case deny(reason: String)
    /// Defer to user — ask for permission.
    case ask(reason: String)
    /// Needs LLM classification — no config rule matched.
    case classify(reason: String)
}

// MARK: - Default Classifier Implementation

/// Default auto-mode classifier using config-based allow/deny lists.
/// Matches Claude Code's auto-mode classification pipeline.
public struct PermissionClassifier: PermissionClassifying {

    public init() {}

    public func classify(
        toolName: String,
        input: String,
        config: AutoModeConfig?
    ) async -> ClassifierDecision {
        guard let config else {
            // No auto mode config — defer to user
            return .ask(reason: "auto mode not configured")
        }

        // Step 1: Check deny list (highest priority)
        if let denyList = config.deny {
            for pattern in denyList {
                if matchRule(toolName: toolName, input: input, pattern: pattern) {
                    return .deny(reason: "matching deny rule: \(pattern)")
                }
            }
        }

        // Step 2: Check softDeny list (asks user)
        if let softDenyList = config.softDeny {
            for pattern in softDenyList {
                if matchRule(toolName: toolName, input: input, pattern: pattern) {
                    return .ask(reason: "matching softDeny rule: \(pattern)")
                }
            }
        }

        // Step 3: Check allow list
        if let allowList = config.allow {
            for pattern in allowList {
                if matchRule(toolName: toolName, input: input, pattern: pattern) {
                    return .allow(reason: "matching allow rule: \(pattern)")
                }
            }
        }

        // Step 4: Simple heuristic fallback for common safe operations
        if isReadOnlyCommand(toolName: toolName, command: input) {
            return .allow(reason: "read-only heuristic: \(toolName)")
        }

        // Step 5: Needs LLM classifier (Haiku) — fall back to asking user
        return .classify(reason: "no config rule matched — needs classifier")
    }

    // MARK: - Pattern Matching

    /// Match a tool name + input against a pattern rule.
    /// Patterns can be:
    /// - "ToolName" — matches any use of the tool
    /// - "ToolName(pattern*)" — matches tool uses with input matching the wildcard
    /// - "ToolName" with wildcard content matching
    private func matchRule(toolName: String, input: String, pattern: String) -> Bool {
        // Check if pattern specifies a tool name
        if let parenIndex = pattern.firstIndex(of: "(") {
            let toolPart = String(pattern[..<parenIndex]).trimmingCharacters(in: .whitespaces)
            let contentPart = String(pattern[pattern.index(after: parenIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))

            guard toolPart == toolName else { return false }

            // Content matching with wildcard support
            if contentPart.hasSuffix("*") {
                let prefix = String(contentPart.dropLast())
                return input.hasPrefix(prefix)
            }
            return input == contentPart || input.contains(contentPart)
        }

        // Bare tool name: matches any use of the tool
        return pattern.trimmingCharacters(in: .whitespaces) == toolName
    }

    /// Heuristic: is this a read-only command?
    private func isReadOnlyCommand(toolName: String, command: String) -> Bool {
        switch toolName {
        case "Read", "Glob", "Grep":
            return true
        case "Bash":
            let readOnlyPrefixes = [
                "ls", "cat", "head", "tail", "find", "grep", "rg",
                "which", "where", "type", "echo", "print", "printf",
                "stat", "file", "du", "df", "wc", "sort", "uniq",
                "pwd", "env", "git log", "git show", "git diff",
                "git status", "git branch", "git tag",
            ]
            let trimmed = command.trimmingCharacters(in: .whitespaces).lowercased()
            return readOnlyPrefixes.contains { trimmed.hasPrefix($0) }
        default:
            return false
        }
    }
}
