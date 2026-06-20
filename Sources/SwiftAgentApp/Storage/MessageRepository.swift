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
            INSERT OR REPLACE INTO messages (id, thread_id, role, content, metadata, created_at)
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

    /// List messages for a thread with pagination support.
    ///
    /// - Parameters:
    ///   - threadId: The thread to fetch messages from.
    ///   - limit: Maximum messages to return (default 50).
    ///   - offset: Number of messages to skip from the end (for "load earlier").
    ///     offset=0 returns the most recent messages.
    /// - Returns: Messages in chronological order (oldest first among the fetched batch).
    public func listByThread(threadId: String, limit: Int = 50, offset: Int = 0) throws -> [PersistedMessage] {
        let rows = try db.query("""
            SELECT * FROM (
                SELECT * FROM messages
                WHERE thread_id = ?
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
            ) ORDER BY created_at ASC
        """, [threadId, Int64(limit), Int64(offset)])
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

    // MARK: - Search

    /// Full-text search across all message content using FTS5.
    ///
    /// - Parameters:
    ///   - query: The search query (FTS5 syntax supported: `"phrase"`, `term*`, `term1 AND term2`).
    ///   - limit: Maximum number of results (default 20).
    /// - Returns: Array of matching messages with snippets, ordered by relevance.
    public func search(query: String, limit: Int = 20) throws -> [FTSearchResult] {
        // Sanitize the query for FTS5: wrap in quotes if it looks like a phrase
        let safeQuery = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !safeQuery.isEmpty else { return [] }

        let rows = try db.query("""
            SELECT
                m.id,
                m.thread_id,
                m.role,
                m.content,
                m.metadata,
                m.created_at,
                snippet(messages_fts, 2, '<b>', '</b>', '...', 64) AS snippet,
                rank
            FROM messages_fts
            JOIN messages m ON m.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """, [safeQuery, Int64(limit)])

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let threadId = row["thread_id"] as? String,
                  let role = row["role"] as? String,
                  let content = row["content"] as? String,
                  let createdAt = row["created_at"] as? Double
            else { return nil }

            return FTSearchResult(
                id: id,
                threadId: threadId,
                role: role,
                content: content,
                snippet: (row["snippet"] as? String) ?? content,
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        }
    }

    // MARK: - Delete

    public func deleteAll(threadId: String) throws {
        try db.execute("DELETE FROM messages WHERE thread_id = ?", [threadId])
    }

    public func deleteById(_ id: String) throws {
        try db.execute("DELETE FROM messages WHERE id = ?", [id])
    }
}
