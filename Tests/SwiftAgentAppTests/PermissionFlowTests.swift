import XCTest
@testable import SwiftAgentApp

final class PermissionFlowTests: XCTestCase {

    // MARK: - PermissionMode Tests

    func testPermissionModeAllCases() {
        let cases = PermissionMode.allCases
        XCTAssertEqual(cases.count, 4)
    }

    func testPermissionModeIcons() {
        for mode in PermissionMode.allCases {
            XCTAssertFalse(mode.iconName.isEmpty, "\(mode) should have an icon name")
        }
    }

    func testPermissionModeDescriptions() {
        for mode in PermissionMode.allCases {
            XCTAssertFalse(mode.description.isEmpty, "\(mode) should have a description")
        }
    }

    func testCustomIsDefault() {
        // Per spec §5.4: Custom (config.toml) is the default
        let defaultMode = PermissionMode.custom
        XCTAssertEqual(defaultMode.iconName, "gearshape")
        XCTAssertTrue(defaultMode.description.contains("config.toml"))
    }

    // MARK: - Permission Display Labels

    func testDisplayLabels() {
        XCTAssertEqual(PermissionMode.askForApproval.displayLabel, "Ask")
        XCTAssertEqual(PermissionMode.approveForMe.displayLabel, "Approve")
        XCTAssertEqual(PermissionMode.fullAccess.displayLabel, "Full")
        XCTAssertEqual(PermissionMode.custom.displayLabel, "Custom")
    }
}
