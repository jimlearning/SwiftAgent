import Foundation

// MARK: - DebugEntry

/// A single debug log entry.
public struct DebugEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: DebugCategory
    public let severity: DebugSeverity
    public let subsystem: String
    public let message: String
    /// Optional structured metadata (e.g. tool count, model name).
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: DebugCategory,
        severity: DebugSeverity = .info,
        subsystem: String = "general",
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.severity = severity
        self.subsystem = subsystem
        self.message = message
        self.metadata = metadata
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - DebugCategory

public enum DebugCategory: String, CaseIterable, Sendable {
    case lifecycle = "Lifecycle"
    case llm = "LLM"
    case tool = "Tool"
    case mcp = "MCP"
    case skill = "Skill"
    case hook = "Hook"
    case permission = "Permission"
    case streaming = "Streaming"
    case ui = "UI"
    case general = "General"

    public var icon: String {
        switch self {
        case .lifecycle: return "arrow.triangle.branch"
        case .llm: return "brain"
        case .tool: return "wrench"
        case .mcp: return "network"
        case .skill: return "wand.and.stars"
        case .hook: return "link"
        case .permission: return "lock.shield"
        case .streaming: return "waveform"
        case .ui: return "rectangle.3.group"
        case .general: return "info.circle"
        }
    }
}

// MARK: - DebugSeverity

public enum DebugSeverity: String, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    public var color: String {
        switch self {
        case .debug: return "secondary"
        case .info: return "primary"
        case .warn: return "warning"
        case .error: return "danger"
        }
    }
}

// MARK: - DebugLog

/// Thread-safe ring buffer for debug entries with JSONL file persistence.
/// Writes to `~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl` so the next
/// AI session can read and analyze prior debug output automatically.
/// Exposes `entries` as a `@Published` array for SwiftUI binding.
@MainActor
public final class DebugLog: ObservableObject {
    public static let shared = DebugLog()

    @Published public private(set) var entries: [DebugEntry] = []
    public var maxEntries: Int = 5000

    private let lock = NSLock()

    // MARK: - File persistence

    /// URL of the current session's JSONL log file.
    public let logFileURL: URL

    /// Queue for serializing file writes (avoids blocking main actor).
    private let writeQueue = DispatchQueue(label: "com.swiftagent.debuglog", qos: .utility)

    /// Human-readable path for display in Settings.
    public var logFilePath: String { logFileURL.path }

    private init() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        self.logFileURL = logDir.appendingPathComponent("debug-\(timestamp).jsonl")
    }

    /// Filtered view of entries (set by UI).
    @Published public var activeCategories: Set<DebugCategory> = Set(DebugCategory.allCases)

    public var filteredEntries: [DebugEntry] {
        entries.filter { activeCategories.contains($0.category) }
    }

    public func log(
        _ message: String,
        category: DebugCategory = .general,
        severity: DebugSeverity = .info,
        subsystem: String = "general",
        metadata: [String: String] = [:]
    ) {
        let entry = DebugEntry(
            category: category,
            severity: severity,
            subsystem: subsystem,
            message: message,
            metadata: metadata
        )
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        // Print to console
        if severity == .error || severity == .warn {
            print("[\(severity.rawValue)][\(category.rawValue)][\(subsystem)] \(message)")
        }

        // Persist to JSONL file
        appendToFile(entry)
    }

    // MARK: - File writing

    private func appendToFile(_ entry: DebugEntry) {
        let dict: [String: Any] = [
            "seq": entries.count,
            "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
            "category": entry.category.rawValue,
            "severity": entry.severity.rawValue,
            "subsystem": entry.subsystem,
            "message": entry.message,
            "metadata": entry.metadata
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        let line = data + [10] // newline
        writeQueue.async { [weak self] in
            guard let self else { return }
            if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                _ = try? handle.seekToEndCompat()
                try? handle.write(contentsOf: line)
                try? handle.close()
            } else {
                try? line.write(to: self.logFileURL, options: .atomic)
            }
        }
    }

    // MARK: - Convenience helpers

    public func info(_ message: String, category: DebugCategory = .general, subsystem: String = "general", metadata: [String: String] = [:]) {
        log(message, category: category, severity: .info, subsystem: subsystem, metadata: metadata)
    }

    public func warn(_ message: String, category: DebugCategory = .general, subsystem: String = "general", metadata: [String: String] = [:]) {
        log(message, category: category, severity: .warn, subsystem: subsystem, metadata: metadata)
    }

    public func error(_ message: String, category: DebugCategory = .general, subsystem: String = "general", metadata: [String: String] = [:]) {
        log(message, category: category, severity: .error, subsystem: subsystem, metadata: metadata)
    }

    public func debug(_ message: String, category: DebugCategory = .general, subsystem: String = "general", metadata: [String: String] = [:]) {
        log(message, category: category, severity: .debug, subsystem: subsystem, metadata: metadata)
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

// MARK: - FileHandle seekToEnd compatibility

extension FileHandle {
    func seekToEndCompat() throws {
        if #available(macOS 10.15.4, *) {
            try seekToEnd()
        } else {
            seekToEndOfFile()
        }
    }
}
