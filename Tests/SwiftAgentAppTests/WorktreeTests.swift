import XCTest
@testable import SwiftAgentApp

final class WorktreeTests: XCTestCase {

    // MARK: - WorktreeEntry Tests

    func testWorktreeEntryIdentity() {
        let entry = WorktreeEntry(
            threadId: "abc-123-def",
            branch: "swiftagent/thread-abc123de",
            path: "/tmp/.swiftagent-worktrees/abc-123-def",
            createdAt: Date()
        )
        XCTAssertEqual(entry.id, "abc-123-def")
        XCTAssertEqual(entry.threadId, "abc-123-def")
        XCTAssertEqual(entry.branch, "swiftagent/thread-abc123de")
        XCTAssertTrue(entry.path.hasSuffix("abc-123-def"))
    }

    func testMergeStrategyAllCases() {
        let cases = MergeStrategy.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.merge))
        XCTAssertTrue(cases.contains(.squash))
        XCTAssertTrue(cases.contains(.rebase))
    }

    // MARK: - ExecutionEnvironment Tests

    func testExecutionEnvironmentAllCases() {
        let cases = ExecutionEnvironment.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual(cases.filter { $0.label.isEmpty }.count, 0)
    }

    func testExecutionEnvironmentLabels() {
        XCTAssertEqual(ExecutionEnvironment.local.label, "Local")
        XCTAssertEqual(ExecutionEnvironment.worktree.label, "Worktree")
    }

    // MARK: - AppWorktreeError Tests

    func testAppWorktreeErrorDescription() {
        let err = AppWorktreeError.noRepoPath
        // Error enum exists
        XCTAssertNotNil(err)
    }
}
