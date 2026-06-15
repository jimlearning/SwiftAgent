import Foundation

/// Repository for Project CRUD operations.
/// Thread-safe: Database uses NSLock internally, access from @MainActor.
public final class ProjectRepository: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Create

    public func create(_ project: PersistedProject) throws {
        let now = Date().timeIntervalSince1970
        try db.execute("""
            INSERT INTO projects (id, name, path, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
        """, [
            project.id, project.name, project.path, project.createdAt.timeIntervalSince1970, now
        ])
    }

    // MARK: - Read

    public func get(id: String) throws -> PersistedProject? {
        let rows = try db.query("SELECT * FROM projects WHERE id = ?", [id])
        return rows.first.flatMap(PersistedProject.init)
    }

    public func listAll() throws -> [PersistedProject] {
        let rows = try db.query("SELECT * FROM projects ORDER BY updated_at DESC")
        return rows.compactMap(PersistedProject.init)
    }

    // MARK: - Update

    public func update(_ project: PersistedProject) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(
            "UPDATE projects SET name = ?, path = ?, updated_at = ? WHERE id = ?",
            [project.name, project.path, now, project.id]
        )
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        // First, set all threads in this project to nil (uncategorized)
        try db.execute("UPDATE threads SET project_id = NULL WHERE project_id = ?", [id])
        try db.execute("DELETE FROM projects WHERE id = ?", [id])
    }
}
