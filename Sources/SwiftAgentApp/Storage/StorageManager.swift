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

    public init() {
        self.database = Database()
        self.projectRepo = ProjectRepository(database: database)
        self.threadRepo = ThreadRepository(database: database)
        self.messageRepo = MessageRepository(database: database)
    }

    /// Open the database and run migrations. Call once on app launch.
    public func initialize() throws {
        try database.open()
        try Migrations.migrate(database: database)
        isReady = true
    }
}
