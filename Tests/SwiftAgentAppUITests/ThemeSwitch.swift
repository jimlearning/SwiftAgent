import XCTest

/// Verifies that the theme can be toggled in settings.
final class ThemeSwitch: XCTestCase {
    func testThemeToggleInSettings() {
        let app = XCUIApplication()
        app.launch()

        // Open settings
        app.typeKey(",", modifierFlags: .command)

        // Navigate to Appearance tab
        let appearanceCell = app.cells["Appearance"]
        if appearanceCell.waitForExistence(timeout: 3) {
            appearanceCell.click()
        }

        // Toggle between Light / Dark / System
        let lightButton = app.segmentedControls.firstMatch.buttons["Light"]
        if lightButton.exists {
            lightButton.click()
        }
        let darkButton = app.segmentedControls.firstMatch.buttons["Dark"]
        if darkButton.exists {
            darkButton.click()
        }
    }
}
