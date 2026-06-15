import Foundation
import SQLite3

// MARK: - Database Error

public enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Database open failed: \(msg)"
        case .prepareFailed(let msg): return "Statement preparation failed: \(msg)"
        case .stepFailed(let msg): return "Statement step failed: \(msg)"
        case .bindFailed(let msg): return "Parameter binding failed: \(msg)"
        case .notFound: return "Record not found"
        }
    }
}

// MARK: - Database

/// SQLite database wrapper with WAL mode.
/// Thread-safe: all access is serialized via NSLock.
/// Designed to be used from @MainActor via StorageManager.
public final class Database: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    /// Path to the database file.
    public let path: String

    /// Whether the database is open and ready.
    public private(set) var isOpen: Bool = false

    /// Initialize with a custom path. Defaults to Application Support.
    public init(path: String? = nil) {
        if let path {
            self.path = path
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("SwiftAgent")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.path = dir.appendingPathComponent("threads.db").path
        }
    }

    /// Open the database and enable WAL mode.
    public func open() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isOpen else { return }

        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw DatabaseError.openFailed(msg)
        }

        // Enable WAL mode
        try executeLocked("PRAGMA journal_mode=WAL")
        // Enable foreign keys
        try executeLocked("PRAGMA foreign_keys=ON")

        isOpen = true
    }

    /// Close the database.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let db, isOpen else { return }
        sqlite3_close(db)
        self.db = nil
        isOpen = false
    }

    // MARK: - Raw Execution

    /// Execute a SQL statement that returns no rows (INSERT, UPDATE, DELETE, DDL).
    @discardableResult
    public func execute(_ sql: String, _ params: [Any] = []) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return try executeLocked(sql, params)
    }

    /// Query rows as dictionaries.
    public func query(_ sql: String, _ params: [Any] = []) throws -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return try queryLocked(sql, params)
    }

    // MARK: - Transaction

    public func transaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try executeLocked("BEGIN TRANSACTION")
        do {
            let result = try block()
            try executeLocked("COMMIT")
            return result
        } catch {
            _ = try? executeLocked("ROLLBACK")
            throw error
        }
    }

    // MARK: - Private Locked Methods

    @discardableResult
    private func executeLocked(_ sql: String, _ params: [Any] = []) throws -> Int64 {
        guard let db else { throw DatabaseError.openFailed("Database not open") }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindLocked(stmt, params)

        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func queryLocked(_ sql: String, _ params: [Any] = []) throws -> [[String: Any]] {
        guard let db else { throw DatabaseError.openFailed("Database not open") }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindLocked(stmt, params)

        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL:
                    row[name] = Optional<Int64>.none as Any
                default:
                    row[name] = Optional<Int64>.none as Any
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func bindLocked(_ stmt: OpaquePointer, _ params: [Any]) throws {
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            let rc: Int32
            switch param {
            case let text as String:
                rc = sqlite3_bind_text(stmt, idx, (text as NSString).utf8String, -1, nil)
            case let int as Int64:
                rc = sqlite3_bind_int64(stmt, idx, int)
            case let int as Int:
                rc = sqlite3_bind_int64(stmt, idx, Int64(int))
            case let double as Double:
                rc = sqlite3_bind_double(stmt, idx, double)
            case let bool as Bool:
                rc = sqlite3_bind_int(stmt, idx, bool ? 1 : 0)
            case is NSNull:
                rc = sqlite3_bind_null(stmt, idx)
            default:
                let str = "\(param)"
                rc = sqlite3_bind_text(stmt, idx, (str as NSString).utf8String, -1, nil)
            }
            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed("Failed to bind parameter \(index): \(param)")
            }
        }
    }
}
