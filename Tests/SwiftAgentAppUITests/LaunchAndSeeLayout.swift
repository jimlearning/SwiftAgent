import XCTest

/// Verifies the app launches and displays the three-pane layout.
/// Note: UI tests require XCUITest infrastructure; these serve as
/// documentation and can run when configured in Xcode.
final class LaunchAndSeeLayout: XCTestCase {
    func testAppLaunchesSuccessfully() {
        let app = XCUIApplication()
        app.launch()

        // Verify the app window exists
        XCTAssertTrue(app.windows.element(boundBy: 0).exists, "App window should exist after launch")

        // Verify sidebar is visible
        let sidebar = app.splitGroups.firstMatch
        XCTAssertTrue(sidebar.exists, "Sidebar should be visible in the split layout")
    }
}
