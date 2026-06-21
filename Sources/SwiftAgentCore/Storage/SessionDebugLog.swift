import Foundation

// MARK: - Debug Log Level

/// Log level matching CC's debug log output.
public enum DebugLogLevel: String, Sendable {
    case debug = "DEBUG"
    case warn = "WARN"
    case error = "ERROR"
}

// MARK: - Session Debug Log

/// Per-session plain-text debug log.
///
/// Writes timestamped log lines to `~/.swift-agent/debug/<session-uuid>.txt`.
/// Format matches CC's debug log:
/// ```
/// YYYY-MM-DDTHH:mm:ss.sssZ [LEVEL] [category] message
/// ```
///
/// Also manages a `latest` symlink pointing to the most recent log file.
///
/// ## Thread Safety
/// All writes are serialized through a dedicated queue.
public final class SessionDebugLog: @unchecked Sendable {
    private let fileManager: FileManager
    private let writeQueue = DispatchQueue(label: "com.swiftagent.debuglog", qos: .utility)
    private let logPath: String
    private let sessionId: String
    private let dateFormatter: ISO8601DateFormatter

    /// Initialize for a specific session.
    /// - Parameter sessionId: The session UUID (used as the log filename).
    public init(sessionId: String) {
        self.fileManager = FileManager.default
        self.sessionId = sessionId
        self.logPath = SwiftAgentPaths.debugLogPath(sessionId: sessionId)

        // Ensure debug directory exists
        let debugDir = SwiftAgentPaths.debugDir()
        try? fileManager.createDirectory(atPath: debugDir, withIntermediateDirectories: true)

        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Update the 'latest' symlink
        updateLatestSymlink()
    }

    // MARK: - Logging Methods

    /// Log a debug message.
    public func debug(_ message: String, category: String = "general") {
        write(level: .debug, category: category, message: message)
    }

    /// Log a warning.
    public func warn(_ message: String, category: String = "general") {
        write(level: .warn, category: category, message: message)
    }

    /// Log an error with optional details.
    public func error(_ message: String, category: String = "general") {
        write(level: .error, category: category, message: message)
    }

    /// Log with explicit level and category.
    public func log(level: DebugLogLevel, category: String, message: String) {
        write(level: level, category: category, message: message)
    }

    // MARK: - Path

    /// Path to this session's debug log file.
    public var path: String { logPath }

    // MARK: - Private

    private func write(level: DebugLogLevel, category: String, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line: String
        if category.isEmpty {
            line = "\(timestamp) [\(level.rawValue)] \(message)\n"
        } else {
            line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"
        }

        guard let data = line.data(using: .utf8) else { return }

        writeQueue.async { [weak self] in
            guard let self else { return }
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: self.logPath)) {
                if #available(macOS 10.15.4, *) {
                    try? handle.seekToEnd()
                } else {
                    handle.seekToEndOfFile()
                }
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: self.logPath), options: .atomic)
            }
        }
    }

    private func updateLatestSymlink() {
        let latestPath = SwiftAgentPaths.debugLatestPath()
        // Remove existing symlink or file
        try? fileManager.removeItem(atPath: latestPath)
        // Create symlink: latest -> <sessionId>.txt
        try? fileManager.createSymbolicLink(
            atPath: latestPath,
            withDestinationPath: "\(sessionId).txt"
        )
    }
}
