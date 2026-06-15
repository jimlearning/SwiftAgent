import XCTest
@testable import SwiftAgentApp

@MainActor
final class RightTabsStoreTests: XCTestCase {

    func testInitialStateEmpty() {
        let store = RightTabsStore()
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertNil(store.activeTabID)
        XCTAssertNil(store.activeTab)
    }

    func testOpenTabAddsTab() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs.first?.type, .review)
    }

    func testOpenTabSetsActiveTabID() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        XCTAssertEqual(store.activeTabID, store.tabs.first?.id)
        XCTAssertNotNil(store.activeTab)
    }

    func testOpenMultipleTabsOfSameType() {
        let store = RightTabsStore()
        store.openTab(type: .terminal)
        store.openTab(type: .terminal)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs[0].type, .terminal)
        XCTAssertEqual(store.tabs[1].type, .terminal)
    }

    func testCloseTabRemovesIt() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        let id = store.tabs.first!.id
        store.close(id)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    func testCloseActiveTabFallsBackToLast() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        let firstID = store.tabs.first!.id
        store.openTab(type: .terminal)
        let secondID = store.tabs.last!.id
        XCTAssertEqual(store.activeTabID, secondID)

        store.close(secondID)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabID, firstID)
    }

    func testCloseLastTabClearsActive() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        let id = store.tabs.first!.id
        store.close(id)
        XCTAssertNil(store.activeTabID)
        XCTAssertNil(store.activeTab)
    }

    func testActivateSetsActiveTabID() {
        let store = RightTabsStore()
        store.openTab(type: .review)
        let firstID = store.tabs.first!.id
        store.openTab(type: .terminal)
        store.activate(firstID)
        XCTAssertEqual(store.activeTabID, firstID)
    }

    func testOpenMultipleTypes() {
        let store = RightTabsStore()
        for type in RightTabType.allCases {
            store.openTab(type: type)
        }
        XCTAssertEqual(store.tabs.count, 5)
        let types = store.tabs.map { $0.type }
        XCTAssertEqual(Set(types).count, 5)
    }
}
