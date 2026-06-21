import Foundation

// MARK: - Session Index Entry

/// A single entry in the sessions-index.json file.
/// Matches CC's LogOption metadata for fast sidebar listing.
public struct SessionIndexEntry: Sendable, Codable, Identifiable {
    public var id: String { sessionId }

    public var sessionId: String
    public var fullPath: String?
    public var fileMtime: Double?
    public var firstPrompt: String?
    public var summary: String?
    public var customTitle: String?
    public var messageCount: Int
    public var created: String   // ISO 8601 date string
    public var modified: String  // ISO 8601 date string
    public var gitBranch: String?
    public var projectPath: String?
    public var isSidechain: Bool
    public var isLite: Bool?
    public var tag: String?
    public var mode: String?
    public var agentName: String?
    public var agentColor: String?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case fullPath
        case fileMtime
        case firstPrompt
        case summary
        case customTitle
        case messageCount
        case created
        case modified
        case gitBranch
        case projectPath
        case isSidechain
        case isLite
        case tag
        case mode
        case agentName
        case agentColor
    }

    public init(
        sessionId: String,
        fullPath: String? = nil,
        fileMtime: Double? = nil,
        firstPrompt: String? = nil,
        summary: String? = nil,
        customTitle: String? = nil,
        messageCount: Int = 0,
        created: String = ISO8601DateFormatter().string(from: Date()),
        modified: String = ISO8601DateFormatter().string(from: Date()),
        gitBranch: String? = nil,
        projectPath: String? = nil,
        isSidechain: Bool = false,
        isLite: Bool? = nil,
        tag: String? = nil,
        mode: String? = nil,
        agentName: String? = nil,
        agentColor: String? = nil
    ) {
        self.sessionId = sessionId
        self.fullPath = fullPath
        self.fileMtime = fileMtime
        self.firstPrompt = firstPrompt
        self.summary = summary
        self.customTitle = customTitle
        self.messageCount = messageCount
        self.created = created
        self.modified = modified
        self.gitBranch = gitBranch
        self.projectPath = projectPath
        self.isSidechain = isSidechain
        self.isLite = isLite
        self.tag = tag
        self.mode = mode
        self.agentName = agentName
        self.agentColor = agentColor
    }
}

// MARK: - Session Index Store

/// Reads and writes `sessions-index.json` for a project directory.
///
/// Each project directory at `~/.swift-agent/projects/<sanitized-path>/`
/// contains a `sessions-index.json` file listing all sessions with
/// lightweight metadata (first prompt, summary, message count, timestamps).
/// This enables fast sidebar listing without scanning entire JSONL files.
///
/// Format matches CC's sessions-index.json:
/// ```json
/// {
///   "version": 1,
///   "entries": [
///     {
///       "sessionId": "...",
///       "fullPath": "...",
///       "firstPrompt": "...",
///       "summary": "...",
///       "messageCount": 29,
///       "created": "2025-12-28T03:25:01.880Z",
///       "modified": "2025-12-28T13:57:48.011Z",
///       ...
///     }
///   ]
/// }
/// ```
public final class SessionIndexStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        self.fileManager = FileManager.default
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.decoder = JSONDecoder()
    }

    // MARK: - Read

    /// List all sessions for a project, most recent first.
    public func list(projectPath: String) throws -> [SessionIndexEntry] {
        let index = try readIndex(projectPath: projectPath)
        return index.entries.sorted { $0.modified > $1.modified }
    }

    /// Get a single session entry by ID.
    public func get(sessionId: String, projectPath: String) throws -> SessionIndexEntry? {
        let entries = try list(projectPath: projectPath)
        return entries.first { $0.sessionId == sessionId }
    }

    // MARK: - Write

    /// Upsert a session entry (insert or update).
    /// Updates the `modified` timestamp and increments `messageCount` if the entry exists.
    public func upsert(_ entry: SessionIndexEntry, projectPath: String) throws {
        var index = (try? readIndex(projectPath: projectPath)) ?? SessionIndex(entries: [])

        if let existingIdx = index.entries.firstIndex(where: { $0.sessionId == entry.sessionId }) {
            // Update existing entry, preserving fields not set in the incoming entry
            var updated = index.entries[existingIdx]
            updated.fullPath = entry.fullPath ?? updated.fullPath
            updated.firstPrompt = entry.firstPrompt ?? updated.firstPrompt
            updated.summary = entry.summary ?? updated.summary
            updated.customTitle = entry.customTitle ?? updated.customTitle
            updated.messageCount = entry.messageCount > 0 ? entry.messageCount : updated.messageCount
            updated.modified = entry.modified
            updated.gitBranch = entry.gitBranch ?? updated.gitBranch
            updated.projectPath = entry.projectPath ?? updated.projectPath
            updated.tag = entry.tag ?? updated.tag
            updated.mode = entry.mode ?? updated.mode
            updated.agentName = entry.agentName ?? updated.agentName
            updated.agentColor = entry.agentColor ?? updated.agentColor
            if let mtime = entry.fileMtime { updated.fileMtime = mtime }
            let modDate = Date()
            let attrs = try? fileManager.attributesOfItem(atPath: entry.fullPath ?? "")
            updated.fileMtime = attrs?[.modificationDate] as? Double
                ?? modDate.timeIntervalSince1970 * 1000
            index.entries[existingIdx] = updated
        } else {
            var newEntry = entry
            if newEntry.fullPath != nil {
                let attrs = try? fileManager.attributesOfItem(atPath: newEntry.fullPath!)
                if let modDate = attrs?[.modificationDate] as? Date {
                    newEntry.fileMtime = modDate.timeIntervalSince1970 * 1000
                }
            }
            index.entries.append(newEntry)
        }

        try writeIndex(index, projectPath: projectPath)
    }

    /// Remove a session from the index.
    public func remove(sessionId: String, projectPath: String) throws {
        var index = (try? readIndex(projectPath: projectPath)) ?? SessionIndex(entries: [])
        index.entries.removeAll { $0.sessionId == sessionId }
        try writeIndex(index, projectPath: projectPath)
    }

    /// Rebuild the entire index by scanning all JSONL files in the project directory.
    /// Used after data migration or corruption recovery.
    public func rebuild(projectPath: String, transcriptStore: TranscriptStore) throws {
        let dir = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { return }

        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") && !$0.contains("subagents") }

        var entries: [SessionIndexEntry] = []
        for file in jsonlFiles {
            let sessionId = (file as NSString).deletingPathExtension
            let fullPath = (dir as NSString).appendingPathComponent(file)

            let metadata = try transcriptStore.readMetadata(sessionId: sessionId, projectPath: projectPath)
            let attrs = try? fileManager.attributesOfItem(atPath: fullPath)

            let created: String
            let modified: String
            if let creationDate = attrs?[.creationDate] as? Date {
                created = ISO8601DateFormatter().string(from: creationDate)
                modified = ISO8601DateFormatter().string(
                    from: (attrs?[.modificationDate] as? Date) ?? creationDate
                )
            } else {
                let now = ISO8601DateFormatter().string(from: Date())
                created = now
                modified = now
            }

            let messageCount = transcriptStore.lineCount(sessionId: sessionId, projectPath: projectPath)

            entries.append(SessionIndexEntry(
                sessionId: sessionId,
                fullPath: fullPath,
                fileMtime: (attrs?[.modificationDate] as? Date).flatMap { $0.timeIntervalSince1970 * 1000 },
                firstPrompt: metadata.firstPrompt,
                summary: metadata.summary,
                customTitle: metadata.customTitle ?? metadata.aiTitle,
                messageCount: messageCount,
                created: created,
                modified: modified,
                gitBranch: nil,
                projectPath: projectPath,
                isSidechain: false,
                tag: metadata.tag,
                mode: metadata.mode,
                agentName: metadata.agentName,
                agentColor: metadata.agentColor
            ))
        }

        try writeIndex(SessionIndex(entries: entries), projectPath: projectPath)
    }

    // MARK: - Private

    private func indexPath(projectPath: String) -> String {
        SwiftAgentPaths.sessionsIndexPath(forProjectPath: projectPath)
    }

    private func readIndex(projectPath: String) throws -> SessionIndex {
        let path = indexPath(projectPath: projectPath)
        guard fileManager.fileExists(atPath: path) else {
            return SessionIndex(entries: [])
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(SessionIndex.self, from: data)
    }

    private func writeIndex(_ index: SessionIndex, projectPath: String) throws {
        let path = indexPath(projectPath: projectPath)
        let dir = (path as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(index)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

// MARK: - Session Index Container

/// Top-level container for sessions-index.json.
private struct SessionIndex: Codable {
    let version: Int
    var entries: [SessionIndexEntry]

    init(version: Int = 1, entries: [SessionIndexEntry] = []) {
        self.version = version
        self.entries = entries
    }
}
