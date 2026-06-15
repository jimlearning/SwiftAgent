import XCTest
@testable import SwiftAgentApp

final class ThreadRepositoryTests: XCTestCase {
    var db: Database!
    var repo: ThreadRepository!
    var tempPath: String!

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "test-threads-\(UUID().uuidString).db"
        db = Database(path: tempPath)
        try! db.open()
        // Create tables needed
        try! db.execute("""
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
                updated_at REAL NOT NULL
            )
        """)
        repo = ThreadRepository(database: db)
    }

    override func tearDown() {
        db?.close()
        if let path = tempPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    // MARK: - Create

    func testCreateThread() throws {
        let thread = PersistedThread(title: "Test Thread")
        try repo.create(thread)

        let fetched = try repo.get(id: thread.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Thread")
        XCTAssertEqual(fetched?.state, "idle")
    }

    // MARK: - Read

    func testGetNonexistentThread() throws {
        let fetched = try repo.get(id: "nonexistent-id")
        XCTAssertNil(fetched)
    }

    func testListAllThreads() throws {
        let t1 = PersistedThread(title: "Thread A")
        let t2 = PersistedThread(title: "Thread B")
        try repo.create(t1)
        try repo.create(t2)

        let all = try repo.listAll()
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Update

    func testUpdateThreadState() throws {
        let thread = PersistedThread(title: "State Test")
        try repo.create(thread)

        try repo.updateState(id: thread.id, state: "executing")
        let fetched = try repo.get(id: thread.id)
        XCTAssertEqual(fetched?.state, "executing")
    }

    func testUpdateThreadTitle() throws {
        let thread = PersistedThread(title: "Old Title")
        try repo.create(thread)

        try repo.updateTitle(id: thread.id, title: "New Title")
        let fetched = try repo.get(id: thread.id)
        XCTAssertEqual(fetched?.title, "New Title")
    }

    // MARK: - Delete

    func testDeleteThread() throws {
        let thread = PersistedThread(title: "To Delete")
        try repo.create(thread)

        try repo.delete(id: thread.id)
        let fetched = try repo.get(id: thread.id)
        XCTAssertNil(fetched)
    }
}
