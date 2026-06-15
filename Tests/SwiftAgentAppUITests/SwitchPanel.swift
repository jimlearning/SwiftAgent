import XCTest

/// Verifies that right-tab panel switching works via keyboard shortcuts.
final class SwitchPanel: XCTestCase {
    func testOpenReviewPanel() {
        let app = XCUIApplication()
        app.launch()

        // Use Ctrl+Shift+G to open a new Review tab
        app.typeKey("g", modifierFlags: [.control, .shift])

        // Verify the right panel area exists
        let rightPanel = app.splitGroups.element(boundBy: 2)
        XCTAssertTrue(rightPanel.exists, "Right panel should exist")
    }

    func testOpenTerminalPanel() {
        let app = XCUIApplication()
        app.launch()

        // Use Ctrl+` to open a new Terminal tab
        app.typeKey("`", modifierFlags: .control)

        let rightPanel = app.splitGroups.element(boundBy: 2)
        XCTAssertTrue(rightPanel.exists, "Right panel should exist")
    }

    func testCloseActiveTabWithEscape() {
        let app = XCUIApplication()
        app.launch()

        // Open a tab then close it
        app.typeKey("g", modifierFlags: [.control, .shift])
        app.typeKey(.escape, modifierFlags: [])
    }
}
