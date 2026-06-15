import XCTest
@testable import SwiftAgentApp

final class RightTabTypeTests: XCTestCase {

    func testHasFiveCases() {
        XCTAssertEqual(RightTabType.allCases.count, 5)
    }

    func testReviewTitle() {
        XCTAssertEqual(RightTabType.review.title, "Review")
    }

    func testTerminalTitle() {
        XCTAssertEqual(RightTabType.terminal.title, "Terminal")
    }

    func testBrowserTitle() {
        XCTAssertEqual(RightTabType.browser.title, "Browser")
    }

    func testFilesTitle() {
        XCTAssertEqual(RightTabType.files.title, "Files")
    }

    func testSideChatTitle() {
        XCTAssertEqual(RightTabType.sideChat.title, "Side chat")
    }

    func testReviewIcon() {
        XCTAssertEqual(RightTabType.review.icon, "checklist")
    }

    func testTerminalIcon() {
        XCTAssertEqual(RightTabType.terminal.icon, "terminal")
    }

    func testBrowserIcon() {
        XCTAssertEqual(RightTabType.browser.icon, "globe")
    }

    func testFilesIcon() {
        XCTAssertEqual(RightTabType.files.icon, "folder")
    }

    func testSideChatIcon() {
        XCTAssertEqual(RightTabType.sideChat.icon, "plus.circle")
    }

    func testReviewShortcut() {
        XCTAssertEqual(RightTabType.review.shortcut, "\u{2303}\u{21E7}G")
    }

    func testTerminalShortcut() {
        XCTAssertEqual(RightTabType.terminal.shortcut, "\u{2303}`")
    }

    func testBrowserShortcut() {
        XCTAssertEqual(RightTabType.browser.shortcut, "\u{2318}T")
    }

    func testFilesShortcut() {
        XCTAssertEqual(RightTabType.files.shortcut, "\u{2318}P")
    }

    func testSideChatShortcut() {
        XCTAssertEqual(RightTabType.sideChat.shortcut, "\u{2325}\u{2318}S")
    }

    func testAllCasesUnique() {
        let ids = RightTabType.allCases.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for type in RightTabType.allCases {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(RightTabType.self, from: data)
            XCTAssertEqual(type, decoded)
        }
    }
}
