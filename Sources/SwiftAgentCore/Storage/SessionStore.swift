import Foundation

/// Persists and loads conversation sessions to/from disk.
public struct SessionStore: Sendable {
    private let directory: URL

    public init(directory: URL = defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Save a session to disk.
    public func save(_ session: Session) throws {
        var s = session
        s.updatedAt = Date()
        let data = try JSONEncoder().encode(s)
        try data.write(to: fileURL(for: session.id))
    }

    /// Load a session by ID.
    public func load(_ id: String) throws -> Session? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Delete a session.
    public func delete(_ id: String) throws {
        let url = fileURL(for: id)
        try FileManager.default.removeItem(at: url)
    }

    /// List all saved sessions, most recent first.
    public func listRecent(limit: Int = 20) throws -> [SessionMetadata] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionMetadata? in
                guard let data = try? Data(contentsOf: url),
                      let session = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
                return SessionMetadata(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    messageCount: session.conversation.turns.count,
                    tags: session.tags
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    public static func defaultDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".swift-agent/sessions")
    }
}
