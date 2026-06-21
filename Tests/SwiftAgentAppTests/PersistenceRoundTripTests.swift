import XCTest
@testable import SwiftAgentApp
import SwiftAgentCore

/// Verify that threads and messages stay in their correct project
/// through the full create → persist → reload cycle.
@MainActor
final class PersistenceRoundTripTests: XCTestCase {

    var tempHome: String!

    override func setUp() {
        super.setUp()
        tempHome = NSTemporaryDirectory() + "swift-agent-test-\(UUID().uuidString)"
        SwiftAgentPaths.configHomeOverride = tempHome
        // Ensure clean state
        try? FileManager.default.removeItem(atPath: tempHome)
    }

    override func tearDown() {
        SwiftAgentPaths.configHomeOverride = nil
        if let path = tempHome {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    // MARK: - Store-level tests

    /// Verify that createSession + appendMessage writes to the correct
    /// project directory, and the sessions-index has the correct projectPath.
    func testStoreCreateAndReloadPreservesProjectPath() throws {
        let store = SwiftAgentStore()
        let projectPath = "/tmp/swiftagent_test_project"

        // 1. Create session in the project
        let result = try store.createSession(
            sessionId: "test-session-001",
            projectPath: projectPath,
            title: "Test Chat",
            cwd: projectPath
        )
        print("[test] createSession transcript=\(result.transcriptPath)")

        // 2. Verify JSONL exists in correct project dir
        let projectDir = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        let expectedTranscript = (projectDir as NSString).appendingPathComponent("test-session-001.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedTranscript),
                       "Transcript should exist at \(expectedTranscript)")
        print("[test] Verified transcript at \(expectedTranscript)")

        // 3. Append a user message
        let msg = Message(
            uuid: "msg-001",
            type: .user,
            content: [.text("Hello from test")],
            timestamp: Date()
        )
        let serialized = SerializedMessage(
            uuid: "msg-001",
            message: msg,
            cwd: projectPath,
            userType: "external",
            sessionID: "test-session-001",
            timestamp: Date(),
            version: "1.0.0",
            isSidechain: false
        )
        try store.appendMessage(serialized, sessionId: "test-session-001", projectPath: projectPath)
        print("[test] Appended message")

        // 4. Verify sessions-index has correct projectPath
        let sessions = try store.listSessions(projectPath: projectPath)
        XCTAssertEqual(sessions.count, 1, "Should find 1 session in project")
        XCTAssertEqual(sessions[0].sessionId, "test-session-001")
        XCTAssertEqual(sessions[0].projectPath, projectPath,
                       "Index entry MUST preserve the original projectPath")
        XCTAssertEqual(sessions[0].customTitle, "Test Chat")
        print("[test] Index entry projectPath=\(sessions[0].projectPath ?? "nil")")

        // 5. Verify reading messages back
        let readMessages = try store.readMessages(sessionId: "test-session-001", projectPath: projectPath)
        XCTAssertEqual(readMessages.count, 1, "Should have 1 message")
        print("[test] Read back \(readMessages.count) messages")

        // 6. Verify no cross-contamination — a different project should see nothing
        let otherPath = "/tmp/swiftagent_other_project"
        let otherSessions = try? store.listSessions(projectPath: otherPath)
        XCTAssertTrue(otherSessions?.isEmpty ?? true,
                      "Other project should have no sessions")
    }

    /// Verify that two projects with separate sessions don't leak into each other.
    func testTwoProjectsNoCrossContamination() throws {
        let store = SwiftAgentStore()
        let projectA = "/tmp/swiftagent_project_a"
        let projectB = "/tmp/swiftagent_project_b"

        // Create session in project A
        _ = try store.createSession(sessionId: "session-a", projectPath: projectA, title: "Chat A", cwd: projectA)

        // Create session in project B
        _ = try store.createSession(sessionId: "session-b", projectPath: projectB, title: "Chat B", cwd: projectB)

        // Add message to project A's session
        let msgA = SerializedMessage(
            uuid: "msg-a", message: Message(uuid: "msg-a", type: .user, content: [.text("A")], timestamp: Date()),
            cwd: projectA, userType: "external", sessionID: "session-a", timestamp: Date(), version: "1.0.0", isSidechain: false
        )
        try store.appendMessage(msgA, sessionId: "session-a", projectPath: projectA)

        // Verify project A has its session
        let sessionsA = try store.listSessions(projectPath: projectA)
        XCTAssertEqual(sessionsA.count, 1, "Project A should have 1 session")
        XCTAssertEqual(sessionsA[0].sessionId, "session-a")
        XCTAssertEqual(sessionsA[0].projectPath, projectA)

        // Verify project B has its session (NOT session-a)
        let sessionsB = try store.listSessions(projectPath: projectB)
        XCTAssertEqual(sessionsB.count, 1, "Project B should have 1 session")
        XCTAssertEqual(sessionsB[0].sessionId, "session-b")
        XCTAssertEqual(sessionsB[0].projectPath, projectB)

        // Messages from A should NOT be in B
        let messagesA = try store.readMessages(sessionId: "session-a", projectPath: projectA)
        XCTAssertEqual(messagesA.count, 1)

        let messagesB = try store.readMessages(sessionId: "session-b", projectPath: projectB)
        XCTAssertEqual(messagesB.count, 0, "Session B should have no messages — cross-contamination detected")
    }

    // MARK: - ViewModel-level tests

    /// Full round-trip: create project → create thread → "send" message →
    /// reload from disk → verify thread is in correct project with correct data.
    func testViewModelPersistenceRoundTrip() throws {
        // Use a path with hyphens so unsanitizePath(sanitizePath(...)) differs
        // from the original (lowercased, hyphens ambiguous with dir separators).
        let projectPath = "/tmp/swift-agent-vm-test"

        // ------ PHASE 1: Create and persist ------
        let appVM1 = AppViewModel()
        appVM1.initializeStorage()
        // Home project auto-created; we don't need it for this test.

        // Create the project that matters
        let project1 = appVM1.createProject(name: "TestProject", path: projectPath)
        print("[test] Phase1: created project name=\(project1.name) path=\(project1.path)")

        // Verify thread was auto-created and auto-selected
        XCTAssertEqual(project1.threads.count, 1, "createProject should create 1 thread")
        let thread1 = project1.threads[0]
        XCTAssertEqual(thread1.projectId, projectPath,
                       "Thread's projectId should match the project path")
        XCTAssertEqual(appVM1.selectedThreadID, thread1.id,
                       "New thread should be auto-selected after createProject")
        print("[test] Phase1: thread id=\(thread1.id.prefix(8)) projectId=\(thread1.projectId ?? "nil")")

        // Verify the JSONL was created in the correct project directory
        let expectedDir = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        let transcriptPath = SwiftAgentPaths.transcriptPath(sessionId: thread1.id, projectPath: projectPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptPath),
                       "Transcript should exist at \(transcriptPath)")
        print("[test] Phase1: transcript exists at \(transcriptPath)")

        // Verify sessions-index entry
        let sessions1 = try appVM1.store.listSessions(projectPath: projectPath)
        XCTAssertEqual(sessions1.count, 1)
        XCTAssertEqual(sessions1[0].sessionId, thread1.id)
        XCTAssertEqual(sessions1[0].projectPath, projectPath,
                       "Index entry projectPath MUST match original (not unsanitizePath result)")
        print("[test] Phase1: index projectPath=\(sessions1[0].projectPath ?? "nil")")

        // Simulate sending messages by appending them directly via the store
        // (can't call thread.send() without agent session)
        let testMsg = SerializedMessage(
            uuid: UUID().uuidString,
            message: Message(uuid: UUID().uuidString, type: .user, content: [.text("Test message content")], timestamp: Date()),
            cwd: projectPath, userType: "external", sessionID: thread1.id,
            timestamp: Date(), version: "1.0.0", isSidechain: false
        )
        try appVM1.store.appendMessage(testMsg, sessionId: thread1.id, projectPath: projectPath)
        print("[test] Phase1: appended test message")

        // ------ PHASE 2: Simulate restart (new AppViewModel) ------
        let appVM2 = AppViewModel()
        appVM2.initializeStorage()
        // Don't auto-create Home again — it should discover existing projects
        print("[test] Phase2: loaded \(appVM2.projects.count) projects")

        // Find the TestProject
        guard let project2 = appVM2.projects.first(where: { $0.path == projectPath }) else {
            XCTFail("TestProject should be discovered after reload — path=\(projectPath)")
            return
        }
        print("[test] Phase2: found project name=\(project2.name) path=\(project2.path)")

        // Verify thread count
        XCTAssertEqual(project2.threads.count, 1,
                       "TestProject should still have 1 thread after reload")
        let thread2 = project2.threads[0]

        // THE KEY ASSERTION: projectId must survive the round-trip
        XCTAssertEqual(thread2.projectId, projectPath,
                       "Thread projectId MUST survive reload. Got: \(thread2.projectId ?? "nil"), expected: \(projectPath)")
        print("[test] Phase2: thread id=\(thread2.id.prefix(8)) projectId=\(thread2.projectId ?? "nil")")

        // Verify that projectId is NOT the unsanitizePath result
        let unsanitized = SwiftAgentPaths.unsanitizePath(SwiftAgentPaths.sanitizePath(projectPath))
        XCTAssertNotEqual(thread2.projectId, unsanitized,
                          "projectId should NOT be the lossy unsanitizePath result (\(unsanitized))")

        // Verify the thread is NOT in the Home project.
        // Note: project names revert to path component on reload (name persistence
        // not yet implemented), so we locate Home by its path, not its name.
        let homePath = NSHomeDirectory()
        if let homeProject = appVM2.projects.first(where: { $0.path == homePath }) {
            let homeThreadIDs = homeProject.threads.map { $0.id }
            XCTAssertFalse(homeThreadIDs.contains(thread2.id),
                           "TestProject thread should NOT appear under Home project")
            print("[test] Phase2: Home project has \(homeProject.threads.count) threads — correct")
        }

        // Verify messages can be loaded
        thread2.loadMessagesFromStore()
        XCTAssertEqual(thread2.messages.count, 1,
                       "Should load 1 message after reload, got \(thread2.messages.count)")
        if let msg = thread2.messages.first {
            print("[test] Phase2: loaded message id=\(msg.id.prefix(8)) role=\(msg.role)")
        }
    }

    /// Verify that threads created in different projects don't leak into Home
    /// after reload, even when Home was the first project created.
    func testMultipleProjectsNoHomeLeakage() throws {
        let appVM1 = AppViewModel()
        appVM1.initializeStorage()

        // Create two projects
        _ = appVM1.createProject(name: "Alpha", path: "/tmp/swiftagent_alpha")
        _ = appVM1.createProject(name: "Beta", path: "/tmp/swiftagent_beta")

        // Add a message to Alpha's thread
        if let alphaProject = appVM1.projects.first(where: { $0.name == "Alpha" }),
           let alphaThread = alphaProject.threads.first {
            let msg = SerializedMessage(
                uuid: UUID().uuidString,
                message: Message(uuid: UUID().uuidString, type: .user, content: [.text("Alpha message")], timestamp: Date()),
                cwd: "/tmp/swiftagent_alpha", userType: "external", sessionID: alphaThread.id,
                timestamp: Date(), version: "1.0.0", isSidechain: false
            )
            try appVM1.store.appendMessage(msg, sessionId: alphaThread.id, projectPath: "/tmp/swiftagent_alpha")
        }

        // Add a message to Beta's thread
        if let betaProject = appVM1.projects.first(where: { $0.name == "Beta" }),
           let betaThread = betaProject.threads.first {
            let msg = SerializedMessage(
                uuid: UUID().uuidString,
                message: Message(uuid: UUID().uuidString, type: .user, content: [.text("Beta message")], timestamp: Date()),
                cwd: "/tmp/swiftagent_beta", userType: "external", sessionID: betaThread.id,
                timestamp: Date(), version: "1.0.0", isSidechain: false
            )
            try appVM1.store.appendMessage(msg, sessionId: betaThread.id, projectPath: "/tmp/swiftagent_beta")
        }

        // Reload
        let appVM2 = AppViewModel()
        appVM2.initializeStorage()

        // Verify each project has exactly its own threads and messages.
        // Project names revert to path component on reload, so look up by path.
        let alphaProject = appVM2.projects.first(where: { $0.path == "/tmp/swiftagent_alpha" })
        let betaProject = appVM2.projects.first(where: { $0.path == "/tmp/swiftagent_beta" })
        let homePath = NSHomeDirectory()
        let homeProject = appVM2.projects.first(where: { $0.path == homePath })

        XCTAssertNotNil(alphaProject)
        XCTAssertNotNil(betaProject)
        XCTAssertNotNil(homeProject)

        // Alpha
        XCTAssertEqual(alphaProject?.threads.count, 1)
        let alphaThread = alphaProject?.threads.first
        XCTAssertEqual(alphaThread?.projectId, "/tmp/swiftagent_alpha")
        alphaThread?.loadMessagesFromStore()
        XCTAssertEqual(alphaThread?.messages.count, 1)

        // Beta
        XCTAssertEqual(betaProject?.threads.count, 1)
        let betaThread = betaProject?.threads.first
        XCTAssertEqual(betaThread?.projectId, "/tmp/swiftagent_beta")
        betaThread?.loadMessagesFromStore()
        XCTAssertEqual(betaThread?.messages.count, 1)

        // Home should only have its own auto-created thread, no leaked threads
        let homeThreadCount = homeProject?.threads.count ?? 0
        XCTAssertEqual(homeThreadCount, 1, "Home project should only have its own thread, but got \(homeThreadCount)")

        // Print diagnostics
        for project in appVM2.projects {
            print("[test] Project '\(project.name)' path=\(project.path) threads=\(project.threads.count)")
            for t in project.threads {
                print("[test]   Thread id=\(t.id.prefix(8)) projectId=\(t.projectId ?? "nil") title=\(t.title)")
            }
        }
    }
}
