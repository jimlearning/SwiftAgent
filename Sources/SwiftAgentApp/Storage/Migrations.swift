import Foundation

/// Idempotent SQLite migrations for the SwiftAgent schema.
public enum Migrations {

    /// The current schema version. Increment when adding new migrations.
    public static let currentVersion: Int = 1

    /// Run all outstanding migrations. Safe to call every launch (idempotent).
    public static func migrate(database: Database) throws {
        // Create schema version tracking table if not exists
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
        """)

        // Check current version
        let rows = try database.query(
            "SELECT MAX(version) AS version FROM schema_version"
        )
        let currentDBVersion = rows.first?["version"] as? Int64 ?? 0

        // Run migrations from current version to latest
        if Int(currentDBVersion) < 1 {
            try migrateV1(database: database)
            try database.execute(
                "INSERT INTO schema_version (version) VALUES (1)"
            )
        }
    }

    // MARK: - V1 Migration (initial schema)

    private static func migrateV1(database: Database) throws {
        // Projects table
        try database.execute("""
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                path TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)

        // Threads table
        try database.execute("""
            CREATE TABLE IF NOT EXISTS threads (
                id TEXT PRIMARY KEY,
                project_id TEXT,
                title TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'idle',
                reuse_state TEXT NOT NULL DEFAULT 'new',
                mode TEXT NOT NULL DEFAULT 'code',
                sandbox_mode TEXT NOT NULL DEFAULT 'workspace-write',
                execution_env TEXT NOT NULL DEFAULT 'local',
                model TEXT NOT NULL DEFAULT 'deepseek-chat',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
            )
        """)

        // Messages table
        try database.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                metadata TEXT,
                created_at REAL NOT NULL,
                FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
            )
        """)

        // Index on messages for fast thread-based queries
        try database.execute("""
            CREATE INDEX IF NOT EXISTS idx_messages_thread
            ON messages(thread_id, created_at)
        """)
    }
}
