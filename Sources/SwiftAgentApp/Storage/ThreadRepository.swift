import Foundation

/// Repository for Thread CRUD operations.
/// Thread-safe: Database uses NSLock internally, and access is from @MainActor.
public final class ThreadRepository: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Create

    public func create(_ thread: PersistedThread) throws {
        let now = Date().timeIntervalSince1970
        try db.execute("""
            INSERT INTO threads (id, project_id, title, state, reuse_state, mode,
                                 sandbox_mode, execution_env, model, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            thread.id,
            thread.projectId as Any,
            thread.title,
            thread.state,
            thread.reuseState,
            thread.mode,
            thread.sandboxMode,
            thread.executionEnv,
            thread.model,
            thread.createdAt.timeIntervalSince1970,
            now
        ])
    }

    // MARK: - Read

    public func get(id: String) throws -> PersistedThread? {
        let rows = try db.query("SELECT * FROM threads WHERE id = ?", [id])
        return rows.first.flatMap(PersistedThread.init)
    }

    public func listByProject(projectId: String?) throws -> [PersistedThread] {
        if let pid = projectId {
            let rows = try db.query(
                "SELECT * FROM threads WHERE project_id = ? ORDER BY updated_at DESC",
                [pid]
            )
            return rows.compactMap(PersistedThread.init)
        } else {
            let rows = try db.query(
                "SELECT * FROM threads WHERE project_id IS NULL ORDER BY updated_at DESC"
            )
            return rows.compactMap(PersistedThread.init)
        }
    }

    public func listAll() throws -> [PersistedThread] {
        let rows = try db.query("SELECT * FROM threads ORDER BY updated_at DESC")
        return rows.compactMap(PersistedThread.init)
    }

    // MARK: - Update

    public func update(_ thread: PersistedThread) throws {
        let now = Date().timeIntervalSince1970
        try db.execute("""
            UPDATE threads SET project_id = ?, title = ?, state = ?, reuse_state = ?,
                               mode = ?, sandbox_mode = ?, execution_env = ?, model = ?,
                               updated_at = ?
            WHERE id = ?
        """, [
            thread.projectId as Any,
            thread.title,
            thread.state,
            thread.reuseState,
            thread.mode,
            thread.sandboxMode,
            thread.executionEnv,
            thread.model,
            now,
            thread.id
        ])
    }

    /// Update just the state field.
    public func updateState(id: String, state: String) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(
            "UPDATE threads SET state = ?, updated_at = ? WHERE id = ?",
            [state, now, id]
        )
    }

    /// Update just the title.
    public func updateTitle(id: String, title: String) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(
            "UPDATE threads SET title = ?, updated_at = ? WHERE id = ?",
            [title, now, id]
        )
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        try db.execute("DELETE FROM threads WHERE id = ?", [id])
    }
}
