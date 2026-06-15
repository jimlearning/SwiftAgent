import XCTest
@testable import SwiftAgentApp

final class SkillRoutingTests: XCTestCase {

    // MARK: - SkillScope Tests

    func testSkillScopePriority() {
        XCTAssertTrue(SkillScope.project < SkillScope.user)
        XCTAssertTrue(SkillScope.user < SkillScope.system)
        XCTAssertEqual(SkillScope.priority(.project), 0)
        XCTAssertEqual(SkillScope.priority(.user), 1)
        XCTAssertEqual(SkillScope.priority(.system), 2)
    }

    func testSkillScopeBadgeColor() {
        XCTAssertFalse(SkillScope.project.badgeColor.isEmpty)
        XCTAssertFalse(SkillScope.user.badgeColor.isEmpty)
        XCTAssertFalse(SkillScope.system.badgeColor.isEmpty)
    }

    // MARK: - SkillEntry

    func testSkillEntryEquality() {
        let entry1 = SkillEntry(
            name: "test-skill",
            description: "A test skill",
            scope: .user,
            markdownBody: "# Hello",
            sourcePath: "/tmp/test/SKILL.md"
        )
        let entry2 = SkillEntry(
            name: "test-skill",
            description: "Different description",
            scope: .project,
            markdownBody: nil,
            sourcePath: "/other/path"
        )
        // Same name = same id = considered the same entry
        XCTAssertEqual(entry1.id, entry2.id)
    }

    func testSkillEntryProperties() {
        let entry = SkillEntry(
            name: "refactor",
            description: "Refactors Swift code for clarity",
            scope: .project,
            markdownBody: "# Refactor\n## When to use\n- When code needs cleanup",
            sourcePath: "/project/.swiftagent/skills/refactor/SKILL.md"
        )
        XCTAssertEqual(entry.name, "refactor")
        XCTAssertEqual(entry.description, "Refactors Swift code for clarity")
        XCTAssertEqual(entry.scope, .project)
        XCTAssertNotNil(entry.markdownBody)
        XCTAssertTrue(entry.sourcePath.hasSuffix(".md"))
    }
}
