import Foundation

/// Repository for Message persistence.
/// Thread-safe: Database uses NSLock internally, access from @MainActor.
public final class MessageRepository: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Create

    public func append(_ message: PersistedMessage) throws {
        try db.execute("""
            INSERT INTO messages (id, thread_id, role, content, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, [
            message.id,
            message.threadId,
            message.role,
            message.content,
            message.metadata as Any,
            message.createdAt.timeIntervalSince1970
        ])
    }

    // MARK: - Read

    /// List messages for a thread, ordered by creation time ascending.
    /// Returns the most recent `limit` messages.
    public func listByThread(threadId: String, limit: Int = 50) throws -> [PersistedMessage] {
        let rows = try db.query("""
            SELECT * FROM (
                SELECT * FROM messages
                WHERE thread_id = ?
                ORDER BY created_at DESC
                LIMIT ?
            ) ORDER BY created_at ASC
        """, [threadId, Int64(limit)])
        return rows.compactMap(PersistedMessage.init)
    }

    /// Count messages for a thread.
    public func count(threadId: String) throws -> Int {
        let rows = try db.query(
            "SELECT COUNT(*) AS cnt FROM messages WHERE thread_id = ?",
            [threadId]
        )
        return rows.first?["cnt"] as? Int ?? 0
    }

    // MARK: - Delete

    public func deleteAll(threadId: String) throws {
        try db.execute("DELETE FROM messages WHERE thread_id = ?", [threadId])
    }
}
