import Foundation
import SwiftUI

/// Central storage manager that owns the database and repositories.
/// Created once at app launch.
@MainActor
public final class StorageManager: ObservableObject {
    public let database: Database
    public let projectRepo: ProjectRepository
    public let threadRepo: ThreadRepository
    public let messageRepo: MessageRepository

    public private(set) var isReady: Bool = false

    /// Migration-related errors surfaced during initialization.
    public private(set) var initializationError: Error?

    public init() {
        self.database = Database()
        self.projectRepo = ProjectRepository(database: database)
        self.threadRepo = ThreadRepository(database: database)
        self.messageRepo = MessageRepository(database: database)
    }

    /// Open the database, configure WAL pragmas, and run migrations.
    ///
    /// Call once on app launch. If migration fails, `initializationError`
    /// is set and `isReady` remains `false` — the caller should present
    /// the error to the user and offer recovery options.
    public func initialize() throws {
        try database.open()

        // Configure WAL optimizations early
        try database.configure([
            "PRAGMA busy_timeout = 5000",        // Wait up to 5s on lock
            "PRAGMA synchronous = NORMAL",        // Safe in WAL mode
            "PRAGMA cache_size = -8000",          // 8 MB page cache
            "PRAGMA mmap_size = 268435456",       // 256 MB memory-mapped I/O
            "PRAGMA temp_store = MEMORY",         // Temp tables in memory
            "PRAGMA journal_size_limit = 67108864", // 64 MB WAL size limit
        ])

        do {
            try Migrations.migrate(database: database)
        } catch {
            initializationError = error
            throw error
        }

        isReady = true
    }
}
