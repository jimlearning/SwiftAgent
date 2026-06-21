import Foundation

// MARK: - Transcript Store

/// Reads and writes session transcripts as JSONL files.
///
/// Each session is stored at `~/.swift-agent/projects/<sanitized-path>/<uuid>.jsonl`.
/// Every line is a JSON-encoded `LogEntry` in CC's flat type-discriminator format.
///
/// ## File Format
/// ```
/// {"type":"last-prompt","leafUuid":"...","sessionId":"..."}
/// {"type":"custom-title","sessionId":"...","customTitle":"Fixing the login bug"}
/// {"parentUuid":null,"isSidechain":false,...,"type":"transcript","uuid":"...","sessionId":"...","cwd":"...","version":"...","message":{...}}
/// ```
///
/// ## Thread Safety
/// Writes are serialized through a dedicated serial queue. Reads are synchronous
/// (callers should dispatch to a background queue for large files).
public final class TranscriptStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let writeQueue = DispatchQueue(label: "com.swiftagent.transcriptstore", qos: .utility)

    public init() {
        self.fileManager = FileManager.default
    }

    // MARK: - Writing

    /// Append a single LogEntry as a JSON line to the transcript file.
    /// Creates the file and parent directories if they don't exist.
    public func append(_ entry: LogEntry, sessionId: String, projectPath: String) throws {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        let dir = (path as NSString).deletingLastPathComponent

        // Ensure project directory exists
        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let dict = try entry.toFlatDict()
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
        let line = data + [10] // newline byte

        // Use a serial queue for thread-safe appends
        writeQueue.sync {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                if #available(macOS 10.15.4, *) {
                    try? handle.seekToEnd()
                } else {
                    handle.seekToEndOfFile()
                }
                try? handle.write(contentsOf: line)
                try? handle.close()
            } else {
                try? line.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }

    /// Append multiple LogEntries as a batch (single file open/close).
    public func appendBatch(_ entries: [LogEntry], sessionId: String, projectPath: String) throws {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        let dir = (path as NSString).deletingLastPathComponent

        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let lines = try entries.map { entry -> Data in
            let dict = try entry.toFlatDict()
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
            return data + [10]
        }

        writeQueue.sync {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                if #available(macOS 10.15.4, *) {
                    try? handle.seekToEnd()
                } else {
                    handle.seekToEndOfFile()
                }
                for line in lines {
                    try? handle.write(contentsOf: line)
                }
                try? handle.close()
            } else {
                let combined = lines.reduce(into: Data()) { $0.append($1) }
                try? combined.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }

    // MARK: - Reading

    /// Read all LogEntry lines from a transcript file.
    /// Returns an empty array if the file doesn't exist.
    public func readAll(sessionId: String, projectPath: String) throws -> [LogEntry] {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        guard fileManager.fileExists(atPath: path) else { return [] }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return lines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return LogEntry.fromFlatDict(dict)
        }
    }

    /// Read only transcript (message) entries from the file, excluding metadata entries
    /// like last-prompt, custom-title, summary, etc.
    ///
    /// Streaming deltas write the same message UUID multiple times as content accumulates
    /// (every ~5 text deltas, every tool event). On read, we deduplicate by keeping only
    /// the LAST occurrence of each UUID — that snapshot has the most complete content.
    public func readMessages(sessionId: String, projectPath: String) throws -> [SerializedMessage] {
        let entries = try readAll(sessionId: sessionId, projectPath: projectPath)
        let messages = entries.compactMap { entry -> SerializedMessage? in
            if case .transcript(let msg) = entry { return msg }
            return nil
        }
        // Deduplicate: keep last occurrence of each UUID (latest streaming snapshot)
        var seen = [String: Int]()  // uuid → index
        for (i, msg) in messages.enumerated() {
            seen[msg.uuid] = i
        }
        let deduplicated = seen.values.sorted().map { messages[$0] }
        return deduplicated
    }

    /// Read only metadata entries (non-transcript) from the file.
    /// Used for fast sidebar listing without parsing full message bodies.
    public func readMetadata(sessionId: String, projectPath: String) throws -> SessionFileMetadata {
        let entries = try readAll(sessionId: sessionId, projectPath: projectPath)

        var result = SessionFileMetadata()
        for entry in entries {
            switch entry {
            case .lastPrompt(let e):
                result.lastPrompt = e.lastPrompt
                result.leafUuid = e.leafUuid
            case .customTitle(let e):
                result.customTitle = e.customTitle
            case .aiTitle(let e):
                result.aiTitle = e.aiTitle
            case .summary(let e):
                result.summary = e.summary
            case .tag(let e):
                result.tag = e.tag
            case .mode(let e):
                result.mode = e.mode.rawValue
            case .agentName(let e):
                result.agentName = e.agentName
            case .agentColor(let e):
                result.agentColor = e.agentColor
            case .transcript(let msg):
                if result.firstPrompt == nil,
                   msg.message.type == .user,
                   case .text(let text) = msg.message.content.first {
                    result.firstPrompt = text
                }
            default:
                break
            }
        }
        return result
    }

    // MARK: - File Management

    /// Check if a transcript file exists for the given session.
    public func exists(sessionId: String, projectPath: String) -> Bool {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        return fileManager.fileExists(atPath: path)
    }

    /// Delete a transcript file. Also removes the session subdirectory (tool-results, subagents).
    public func delete(sessionId: String, projectPath: String) throws {
        let transcriptPath = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        if fileManager.fileExists(atPath: transcriptPath) {
            try fileManager.removeItem(atPath: transcriptPath)
        }
        let sessionDir = SwiftAgentPaths.sessionDir(sessionId: sessionId, projectPath: projectPath)
        if fileManager.fileExists(atPath: sessionDir) {
            try fileManager.removeItem(atPath: sessionDir)
        }
    }

    /// Get file modification date (for cache invalidation).
    public func modificationDate(sessionId: String, projectPath: String) -> Date? {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// Count lines in the transcript file (approximate message count).
    public func lineCount(sessionId: String, projectPath: String) -> Int {
        let path = SwiftAgentPaths.transcriptPath(sessionId: sessionId, projectPath: projectPath)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}

// MARK: - Session File Metadata

/// Lightweight metadata extracted from a transcript file's non-message entries.
/// Used for sidebar listings without parsing full message bodies.
public struct SessionFileMetadata: Sendable {
    public var firstPrompt: String?
    public var lastPrompt: String?
    public var leafUuid: String?
    public var customTitle: String?
    public var aiTitle: String?
    public var summary: String?
    public var tag: String?
    public var mode: String?
    public var agentName: String?
    public var agentColor: String?

    /// The best available display title.
    public var displayTitle: String {
        customTitle ?? aiTitle ?? firstPrompt.map { $0.prefix(80).description } ?? "Untitled"
    }

    public init() {}
}
