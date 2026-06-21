import Foundation

/// Central path resolution for SwiftAgent's data directories.
/// All paths rooted at ~/.swift-agent/ (independent namespace from Claude Code's ~/.claude/).
/// Layout, file naming, and data format mirror CC exactly.
public enum SwiftAgentPaths {

    // MARK: - Config Home

    /// Runtime override for config home (set by tests to isolate from real data).
    /// When non-nil, all path resolution uses this directory instead of the
    /// normal env-var / ~/.swift-agent resolution.
    /// Not concurrency-safe by design — set once before any path access.
    nonisolated(unsafe) public static var configHomeOverride: String?

    /// Resolve the SwiftAgent config home directory.
    /// Uses SWIFT_AGENT_CONFIG_DIR env var if set, otherwise ~/.swift-agent.
    public static func configHomeDir() -> String {
        if let override = configHomeOverride {
            return override
        }
        if let envDir = ProcessInfo.processInfo.environment["SWIFT_AGENT_CONFIG_DIR"] {
            return (envDir as NSString).standardizingPath
        }
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".swift-agent")
    }

    // MARK: - Projects

    /// ~/.swift-agent/projects/
    public static func projectsDir() -> String {
        (configHomeDir() as NSString).appendingPathComponent("projects")
    }

    /// ~/.swift-agent/projects/<sanitized-path>/
    public static func projectDir(forProjectPath path: String) -> String {
        let sanitized = sanitizePath(path)
        return (projectsDir() as NSString).appendingPathComponent(sanitized)
    }

    // MARK: - Sessions (JSONL transcripts)

    /// ~/.swift-agent/projects/<sanitized-path>/<uuid>.jsonl
    public static func transcriptPath(sessionId: String, projectPath: String) -> String {
        let dir = projectDir(forProjectPath: projectPath)
        return (dir as NSString).appendingPathComponent("\(sessionId).jsonl")
    }

    /// ~/.swift-agent/projects/<sanitized-path>/<uuid>/
    public static func sessionDir(sessionId: String, projectPath: String) -> String {
        let dir = projectDir(forProjectPath: projectPath)
        return (dir as NSString).appendingPathComponent(sessionId)
    }

    /// ~/.swift-agent/projects/<sanitized-path>/<uuid>/subagents/
    public static func subagentsDir(sessionId: String, projectPath: String) -> String {
        (sessionDir(sessionId: sessionId, projectPath: projectPath) as NSString)
            .appendingPathComponent("subagents")
    }

    /// ~/.swift-agent/projects/<sanitized-path>/<uuid>/tool-results/
    public static func toolResultsDir(sessionId: String, projectPath: String) -> String {
        (sessionDir(sessionId: sessionId, projectPath: projectPath) as NSString)
            .appendingPathComponent("tool-results")
    }

    // MARK: - Session Index

    /// ~/.swift-agent/projects/<sanitized-path>/sessions-index.json
    public static func sessionsIndexPath(forProjectPath path: String) -> String {
        let dir = projectDir(forProjectPath: path)
        return (dir as NSString).appendingPathComponent("sessions-index.json")
    }

    // MARK: - Debug Logs

    /// ~/.swift-agent/debug/
    public static func debugDir() -> String {
        (configHomeDir() as NSString).appendingPathComponent("debug")
    }

    /// ~/.swift-agent/debug/<session-uuid>.txt
    public static func debugLogPath(sessionId: String) -> String {
        (debugDir() as NSString).appendingPathComponent("\(sessionId).txt")
    }

    /// ~/.swift-agent/debug/latest
    public static func debugLatestPath() -> String {
        (debugDir() as NSString).appendingPathComponent("latest")
    }

    // MARK: - Legacy (for migration awareness)

    /// ~/.swift-agent/logs/ (old debug log location — to be removed)
    public static func legacyLogsDir() -> String {
        (configHomeDir() as NSString).appendingPathComponent("logs")
    }

    /// ~/.swift-agent/sessions/ (old session store location — to be removed)
    public static func legacySessionsDir() -> String {
        (configHomeDir() as NSString).appendingPathComponent("sessions")
    }

    // MARK: - Path Sanitization

    /// Sanitize a project path for use as a directory name.
    /// Matches CC's sanitizePath: remove leading /, replace / with -, replace spaces with _.
    /// Always treats the path as absolute to avoid resolving relative paths against cwd.
    public static func sanitizePath(_ path: String) -> String {
        // Ensure path is treated as absolute
        let absolute = path.hasPrefix("/") ? path : "/\(path)"
        let resolved = URL(fileURLWithPath: absolute).standardized.path
        var sanitized = resolved.hasPrefix("/") ? String(resolved.dropFirst()) : resolved
        sanitized = sanitized.replacingOccurrences(of: "/", with: "-")
        sanitized = sanitized.replacingOccurrences(of: " ", with: "_")
        return sanitized.lowercased()
    }

    /// Reverse a sanitized directory name back to a plausible original path.
    /// Best-effort: replaces - with / and prepends /. May not be exact for paths with hyphens.
    public static func unsanitizePath(_ sanitized: String) -> String {
        "/" + sanitized.replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Directory Creation

    /// Ensure a directory exists at the given path, creating intermediates as needed.
    @discardableResult
    public static func ensureDir(at path: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
