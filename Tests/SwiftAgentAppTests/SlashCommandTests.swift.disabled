import XCTest
@testable import SwiftAgentApp

final class SlashCommandTests: XCTestCase {

    func testAllCommandsCount() {
        // There should be exactly 10 slash commands
        XCTAssertEqual(SlashCommand.all.count, 10)
    }

    func testCommandNamesStartWithSlash() {
        for cmd in SlashCommand.all {
            XCTAssertTrue(cmd.command.hasPrefix("/"), "\(cmd.command) should start with '/'")
        }
    }

    func testCommandIdsAreUnique() {
        let ids = SlashCommand.all.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testFindHelpCommand() {
        let help = SlashCommand.all.first { $0.command == "/help" }
        XCTAssertNotNil(help)
        XCTAssertEqual(help?.description, "Show all available commands")
    }

    func testFindStatusCommand() {
        let status = SlashCommand.all.first { $0.command == "/status" }
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.category, .thread)
    }

    func testFilterCommandsByPartialMatch() {
        let query = "status"
        let matches = SlashCommand.all.filter {
            $0.command.lowercased().contains(query)
            || $0.description.lowercased().contains(query)
        }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.command, "/status")
    }

    func testAllCategoriesPresent() {
        let categories = Set(SlashCommand.all.map { $0.category })
        XCTAssertTrue(categories.contains(.general))
        XCTAssertTrue(categories.contains(.thread))
        XCTAssertTrue(categories.contains(.mode))
        XCTAssertTrue(categories.contains(.session))
    }
}
