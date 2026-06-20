import Foundation

// MARK: - Migration Error

/// Errors that can occur during schema migration.
enum MigrationError: LocalizedError {
    /// The database schema version is newer than the app supports (downgrade detected).
    case databaseTooNew(databaseVersion: Int, appVersion: Int)
    /// A migration failed to apply.
    case migrationFailed(version: Int, name: String, underlying: Error)
    /// Schema version table is corrupt or unreadable.
    case versionTableCorrupt(underlying: Error)
    /// Integrity check failed before migration.
    case integrityCheckFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .databaseTooNew(let dbVer, let appVer):
            return "Database schema version (\(dbVer)) is newer than this app supports (\(appVer)). Downgrade is not supported."
        case .migrationFailed(let version, let name, let error):
            return "Migration v\(version) \"\(name)\" failed: \(error.localizedDescription)"
        case .versionTableCorrupt(let error):
            return "Schema version table is corrupt: \(error.localizedDescription)"
        case .integrityCheckFailed(let detail):
            return "Database integrity check failed before migration: \(detail)"
        }
    }
}

// MARK: - Migration Descriptor

/// A single forward-only schema migration.
struct Migration {
    /// Monotonically increasing version number (1-based).
    let version: Int
    /// Human-readable description of what this migration does.
    let name: String
    /// The SQL statements to execute. Runs inside a transaction.
    let sql: [String]
}

// MARK: - Migration Registry

/// Versioned, forward-only, transactional SQLite migration system.
///
/// ## Design
/// - **Forward-only**: refuses to run if the database is newer than the app.
/// - **Transactional**: each `Migration` runs in its own `BEGIN`/`COMMIT`.
/// - **Idempotent**: migrations are skipped if already applied (checked per version).
/// - **Pre-flight integrity**: runs `PRAGMA integrity_check` before applying any migration.
///
/// To add a new migration, append a `Migration` to the `all` array and bump `currentVersion`.
public enum Migrations {

    // MARK: - Version

    /// The maximum schema version this build of the app understands.
    public static let currentVersion: Int = 2

    // MARK: - Registry

    /// All migrations in version order. Append new entries at the end.
    private static let all: [Migration] = [
        Migration(
            version: 1,
            name: "Initial schema — projects, threads, messages",
            sql: [
                // Projects
                """
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    path TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )
                """,
                // Threads
                """
                CREATE TABLE IF NOT EXISTS threads (
                    id TEXT PRIMARY KEY,
                    project_id TEXT,
                    title TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT 'idle',
                    reuse_state TEXT NOT NULL DEFAULT 'new',
                    mode TEXT NOT NULL DEFAULT 'code',
                    sandbox_mode TEXT NOT NULL DEFAULT 'workspace-write',
                    execution_env TEXT NOT NULL DEFAULT 'local',
                    model TEXT NOT NULL DEFAULT 'deepseek-v4-pro',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
                )
                """,
                // Messages
                """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    metadata TEXT,
                    created_at REAL NOT NULL,
                    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
                )
                """,
                // Index
                """
                CREATE INDEX IF NOT EXISTS idx_messages_thread
                ON messages(thread_id, created_at)
                """,
            ]
        ),
        Migration(
            version: 2,
            name: "FTS5 full-text search on message content",
            sql: [
                // FTS5 virtual table for message content
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                    content,
                    tokenize='porter unicode61'
                )
                """,
                // Populate FTS with existing messages
                """
                INSERT INTO messages_fts(rowid, content)
                SELECT rowid, content FROM messages
                """,
                // Trigger: after INSERT on messages — add to FTS
                """
                CREATE TRIGGER IF NOT EXISTS messages_fts_ai AFTER INSERT ON messages BEGIN
                    INSERT INTO messages_fts(rowid, content) VALUES (new.rowid, new.content);
                END
                """,
                // Trigger: after DELETE on messages — remove from FTS
                """
                CREATE TRIGGER IF NOT EXISTS messages_fts_ad AFTER DELETE ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                END
                """,
                // Trigger: after UPDATE on messages — replace in FTS
                """
                CREATE TRIGGER IF NOT EXISTS messages_fts_au AFTER UPDATE ON messages BEGIN
                    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                    INSERT INTO messages_fts(rowid, content) VALUES (new.rowid, new.content);
                END
                """,
            ]
        ),
    ]

    // MARK: - Migration Runner

    /// Run all outstanding migrations against `database`.
    ///
    /// Safe to call every launch — already-applied migrations are skipped.
    /// Throws `MigrationError` on failure; the caller should present the error
    /// and offer recovery options (restore from backup, reset database, etc.).
    public static func migrate(database: Database) throws {
        // 1. Ensure the schema version tracking table exists
        try database.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at REAL NOT NULL
            )
        """)

        // 2. Read the current database version
        let dbVersion = try currentDatabaseVersion(database)

        // 3. Forward-only guard
        if dbVersion > currentVersion {
            throw MigrationError.databaseTooNew(
                databaseVersion: dbVersion,
                appVersion: currentVersion
            )
        }

        // 4. Pre-flight integrity check (skip for empty/fresh databases)
        if dbVersion > 0 {
            try checkIntegrity(database)
        }

        // 5. Apply outstanding migrations in order
        for migration in all where migration.version > dbVersion {
            try apply(migration, database: database)
        }
    }

    // MARK: - Private

    /// Query the highest applied migration version.
    private static func currentDatabaseVersion(_ database: Database) throws -> Int {
        let rows: [[String: Any]]
        do {
            rows = try database.query(
                "SELECT MAX(version) AS version FROM schema_version"
            )
        } catch {
            throw MigrationError.versionTableCorrupt(underlying: error)
        }
        guard let first = rows.first,
              let version = first["version"] as? Int64 else {
            return 0
        }
        return Int(version)
    }

    /// Run `PRAGMA integrity_check` and throw if it fails.
    private static func checkIntegrity(_ database: Database) throws {
        let rows = try database.query("PRAGMA integrity_check")
        guard let first = rows.first,
              let result = first["integrity_check"] as? String,
              result == "ok" else {
            let detail = rows.first?["integrity_check"] as? String ?? "unknown"
            throw MigrationError.integrityCheckFailed(detail: detail)
        }
    }

    /// Apply a single migration inside a transaction.
    private static func apply(_ migration: Migration, database: Database) throws {
        do {
            try database.transaction {
                for statement in migration.sql {
                    try database.execute(statement)
                }
                // Record the applied migration
                try database.execute(
                    "INSERT INTO schema_version (version, name, applied_at) VALUES (?, ?, ?)",
                    [migration.version, migration.name, Date().timeIntervalSince1970]
                )
            }
        } catch {
            throw MigrationError.migrationFailed(
                version: migration.version,
                name: migration.name,
                underlying: error
            )
        }
    }
}
