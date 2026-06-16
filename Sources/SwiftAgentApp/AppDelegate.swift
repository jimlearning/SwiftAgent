import AppKit
import SwiftUI

/// AppDelegate ensures that the SwiftAgentApp executable, when launched as a
/// bare Mach-O binary (e.g. via Xcode Run from a Swift Package, or
/// `swift run` from the CLI), is treated by AppKit as a **regular GUI app**:
///
/// - Sets `NSApp.setActivationPolicy(.regular)` so a Dock icon and menu bar
///   appear, and the main window is allowed to come to the front.
/// - On `applicationDidFinishLaunching`, explicitly activates the app and
///   brings the main window forward. Without this, when the binary is not
///   wrapped in a `.app` bundle, SwiftUI's window creation can complete but
///   the window never gets key focus, so users see "nothing happened" after
///   hitting Run.
///
/// Also forwards `applicationShouldTerminateAfterLastWindowClosed` so closing
/// all windows quits the process.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Behave as a regular GUI app (Dock icon, menu bar, frontmost window).
        NSApp.setActivationPolicy(.regular)

        // Make SwiftAgent the frontmost app and bring the main window to the
        // front. When launched from Xcode as a SPM executable target, the
        // process otherwise stays in accessory mode and the SwiftUI window
        // never appears.
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Close-all-windows quits the app. Without this, the binary keeps
        // running in the background with no UI.
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
