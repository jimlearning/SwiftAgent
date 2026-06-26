import Foundation
import SQLite3

/// Persistent SessionMemoryStore backend using system SQLite3.
///
/// Actor-based to serialize all database access through a single thread
/// (SQLite3 in serialized mode). Implements all 6 SessionMemoryStore
/// protocol methods with schema-versioned migrations and parameterized
/// queries (zero string interpolation into SQL).
///
/// This is the post-migration provider. The legacy MemoryStore (Storage/MemoryStore.swift)
/// path is deprecated and will be removed in a future phase.
public actor SQLiteMemoryStore: SessionMemoryStore {

    // MARK: - Database Handle (Sendable wrapper for non-Sendable C type)

    /// Wraps a non-Sendable `OpaquePointer?` so the actor can store it
    /// without triggering Swift 6 data-race safety diagnostics in deinit.
    /// The handle is closed automatically when this wrapper is deallocated.
    private final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer?
        init(_ pointer: OpaquePointer?) { self.pointer = pointer }
        deinit {
            if let p = pointer { sqlite3_close(p) }
        }
    }

    // MARK: - Private State

    private let dbHandle: Handle
    private let dbPath: String

    /// Convenience accessor for the raw SQLite handle.
    private var db: OpaquePointer? { dbHandle.pointer }

    // MARK: - Initialization

    /// Create or open a SQLite database at the given path.
    ///
    /// - Parameter location: Filesystem path to the `.db` file.
    ///   Defaults to `~/.swift-agent/memory.db`.
    public init(location: String? = nil) throws {
        if let location = location {
            self.dbPath = location
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let swiftAgentDir = home.appendingPathComponent(".swift-agent")
            // Ensure directory exists — surface failure instead of silently ignoring
            do {
                try FileManager.default.createDirectory(
                    at: swiftAgentDir,
                    withIntermediateDirectories: true
                )
            } catch {
                throw AgentRuntimeError.storageFull(availableBytes: 0)
            }
            self.dbPath = swiftAgentDir.appendingPathComponent("memory.db").path
        }

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            dbPath,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        guard rc == SQLITE_OK, let handle = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 returned \(rc) with nil handle"
            if let h = handle { sqlite3_close(h) }
            throw AgentRuntimeError.invalidResponse(reason: "Failed to open SQLite database at \(dbPath): \(msg)")
        }
        self.dbHandle = Handle(handle)

        // Configure pragmas (nonisolated helpers accept db handle)
        try Self.executeNonIsolated(db: handle, "PRAGMA journal_mode=WAL")
        try Self.executeNonIsolated(db: handle, "PRAGMA foreign_keys=ON")

        // Run schema migration
        try Self.migrateNonIsolated(db: handle)
    }

    // MARK: - Schema Migration (Non-isolated, for use during init)

    /// Apply sequential schema migrations within transactions.
    /// Non-isolated so it can be called from init.
    private static func migrateNonIsolated(db: OpaquePointer) throws {
        // Migration 1: schema_version table (must exist first so we can track versions)
        var hasSchemaVersionTable = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                hasSchemaVersionTable = true
            }
            sqlite3_finalize(stmt)
        }

        if !hasSchemaVersionTable {
            try executeNonIsolated(db: db, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)")
            try executeNonIsolated(db: db, "INSERT INTO schema_version (version) VALUES (1)")
        }

        let currentVersion = try Self.currentSchemaVersionNonIsolated(db: db)

        // Define migrations: (version: Int, sql: String)
        let migrations: [(version: Int, sql: String)] = [
            (1, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)"),
            (2, """
                CREATE TABLE IF NOT EXISTS memory_entries (
                    key TEXT NOT NULL,
                    namespace TEXT NOT NULL,
                    value BLOB,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    PRIMARY KEY (key, namespace)
                )
                """),
            (3, "CREATE INDEX IF NOT EXISTS idx_memory_namespace ON memory_entries(namespace)"),
            (4, "CREATE INDEX IF NOT EXISTS idx_memory_updated ON memory_entries(updated_at)"),
        ]

        for (version, sql) in migrations where version > currentVersion {
            try executeNonIsolated(db: db, "BEGIN IMMEDIATE")
            do {
                try executeNonIsolated(db: db, sql)
                try executeNonIsolated(db: db, "INSERT INTO schema_version (version) VALUES (?)",
                            bindings: [.int(Int64(version))])
                try executeNonIsolated(db: db, "COMMIT")
            } catch {
                _ = try? executeNonIsolated(db: db, "ROLLBACK")
                throw AgentRuntimeError.migrationFailed(
                    fromVersion: currentVersion,
                    toVersion: version,
                    reason: "Migration \(version) failed"
                )
            }
        }
    }

    /// Read the current maximum schema version. Non-isolated.
    private static func currentSchemaVersionNonIsolated(db: OpaquePointer) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(version) AS max_version FROM schema_version", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let maxVer = sqlite3_column_int64(stmt, 0)
            return Int(maxVer)
        }
        return 0
    }

    // MARK: - SessionMemoryStore Conformance

    /// Store a Codable value at a key within a namespace.
    ///
    /// Encodes the value as JSON Data and stores it as a BLOB.
    /// Uses INSERT OR REPLACE so existing keys are overwritten.
    public func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws {
        let data = try JSONEncoder().encode(value)
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT OR REPLACE INTO memory_entries \
            (key, namespace, value, created_at, updated_at, metadata) \
            VALUES (?, ?, ?, COALESCE((SELECT created_at FROM memory_entries WHERE key=? AND namespace=?), ?), ?, '{}')
            """
        try execute(sql, bindings: [
            .text(key),
            .text(namespace),
            .blob(data),
            .text(key),
            .text(namespace),
            .real(now),
            .real(now),
        ])
    }

    /// Retrieve a Codable value by key and namespace.
    ///
    /// Returns `nil` if no entry exists for the given key+namespace pair.
    public func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T? {
        let sql = "SELECT value FROM memory_entries WHERE key=? AND namespace=?"
        let rows = try queryRows(sql, bindings: [.text(key), .text(namespace)])
        guard let row = rows.first else { return nil }

        guard let blob = row["value"] as? Data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: blob)
        } catch {
            throw AgentRuntimeError.invalidResponse(
                reason: "Failed to decode stored value for key '\(key)': \(error)"
            )
        }
    }

    /// Search for entries matching a query within a namespace.
    ///
    /// Uses LIKE-based case-insensitive search on both key and value columns.
    public func search(query: String, namespace: String) async throws -> [SessionMemoryEntry] {
        let sql = """
            SELECT key, namespace, value, created_at, updated_at, metadata \
            FROM memory_entries \
            WHERE namespace=? AND (key LIKE ? OR CAST(value AS TEXT) LIKE ?)
            """
        let pattern = "%\(query)%"
        let rows = try queryRows(sql, bindings: [
            .text(namespace),
            .text(pattern),
            .text(pattern),
        ])
        return rows.compactMap { row -> SessionMemoryEntry? in
            guard let key = row["key"] as? String,
                  let ns = row["namespace"] as? String else { return nil }
            let value = row["value"] as? Data ?? Data()
            let createdAt = Date(timeIntervalSince1970: (row["created_at"] as? Double) ?? 0)
            let updatedAt = Date(timeIntervalSince1970: (row["updated_at"] as? Double) ?? 0)
            let metadata: [String: String]
            if let metaText = row["metadata"] as? String,
               let metaData = metaText.data(using: .utf8),
               let parsed = try? JSONDecoder().decode([String: String].self, from: metaData) {
                metadata = parsed
            } else {
                metadata = [:]
            }
            return SessionMemoryEntry(
                key: key,
                namespace: ns,
                value: value,
                createdAt: createdAt,
                updatedAt: updatedAt,
                metadata: metadata
            )
        }
    }

    /// Generate a summary string for all entries in a namespace.
    public func summarize(namespace: String) async throws -> String {
        let sql = """
            SELECT COUNT(*) AS cnt, GROUP_CONCAT(key, ', ') AS key_list \
            FROM memory_entries WHERE namespace=?
            """
        let rows = try queryRows(sql, bindings: [.text(namespace)])
        guard let row = rows.first else {
            return "namespace '\(namespace)': 0 entries. Database at \(dbPath)."
        }
        let count = (row["cnt"] as? Int64) ?? 0
        let keyList = (row["key_list"] as? String) ?? ""
        return "namespace '\(namespace)': \(count) entries. Keys: \(keyList). Database at \(dbPath)."
    }

    /// Remove an entry by key and namespace. Idempotent.
    public func forget(key: String, namespace: String) async throws {
        let sql = "DELETE FROM memory_entries WHERE key=? AND namespace=?"
        try execute(sql, bindings: [.text(key), .text(namespace)])
    }

    /// List all distinct namespace identifiers.
    public func listNamespaces() async throws -> [String] {
        let sql = "SELECT DISTINCT namespace FROM memory_entries"
        let rows = try queryRows(sql)
        return rows.compactMap { $0["namespace"] as? String }
    }

    // MARK: - SQLite Execution Helpers (Non-isolated)

    /// Represents a bindable SQLite parameter value.
    private enum SQLiteBindable {
        case text(String)
        case int(Int64)
        case real(Double)
        case blob(Data)
        case null
    }

    /// Execute a SQL statement that returns no rows. Non-isolated.
    @discardableResult
    private static func executeNonIsolated(db: OpaquePointer, _ sql: String, bindings: [SQLiteBindable] = []) throws -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AgentRuntimeError.invalidResponse(reason: "SQL prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        try bindParametersNonIsolated(db: db, stmt: stmt, bindings)

        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AgentRuntimeError.invalidResponse(reason: "SQL step failed: \(msg)")
        }

        return sqlite3_last_insert_rowid(db)
    }

    /// Execute a SQL statement (actor-isolated wrapper calling nonisolated helper).
    @discardableResult
    private func execute(_ sql: String, bindings: [SQLiteBindable] = []) throws -> Int64 {
        guard let db = db else {
            throw AgentRuntimeError.storageFull(availableBytes: 0)
        }
        return try Self.executeNonIsolated(db: db, sql, bindings: bindings)
    }

    /// Query rows as dictionaries. Actor-isolated.
    private func queryRows(_ sql: String, bindings: [SQLiteBindable] = []) throws -> [[String: Any]] {
        guard let db = db else {
            throw AgentRuntimeError.storageFull(availableBytes: 0)
        }
        return try Self.queryRowsNonIsolated(db: db, sql, bindings: bindings)
    }

    /// Query rows as dictionaries. Non-isolated.
    private static func queryRowsNonIsolated(db: OpaquePointer, _ sql: String, bindings: [SQLiteBindable] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AgentRuntimeError.invalidResponse(reason: "SQL prepare failed: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        try bindParametersNonIsolated(db: db, stmt: stmt, bindings)

        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let colCount = sqlite3_column_count(stmt)
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    if let blobPtr = sqlite3_column_blob(stmt, i) {
                        let byteCount = Int(sqlite3_column_bytes(stmt, i))
                        row[name] = Data(bytes: blobPtr, count: byteCount)
                    } else {
                        row[name] = Data()
                    }
                case SQLITE_NULL:
                    row[name] = nil as Any?
                default:
                    row[name] = nil as Any?
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Bind parameters to a prepared statement. Non-isolated.
    private static func bindParametersNonIsolated(db: OpaquePointer, stmt: OpaquePointer, _ bindings: [SQLiteBindable]) throws {
        for (index, param) in bindings.enumerated() {
            let idx = Int32(index + 1)
            let rc: Int32
            switch param {
            case .text(let text):
                rc = sqlite3_bind_text(stmt, idx, (text as NSString).utf8String, -1, nil)
            case .int(let int):
                rc = sqlite3_bind_int64(stmt, idx, int)
            case .real(let double):
                rc = sqlite3_bind_double(stmt, idx, double)
            case .blob(let data):
                // SQLITE_TRANSIENT tells SQLite3 to make its own copy.
                // The withUnsafeBytes pointer is only valid within the closure.
                rc = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, idx, bytes.baseAddress, Int32(data.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .null:
                rc = sqlite3_bind_null(stmt, idx)
            }
            guard rc == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw AgentRuntimeError.invalidResponse(reason: "Bind failed for param \(index): \(msg)")
            }
        }
    }
}
