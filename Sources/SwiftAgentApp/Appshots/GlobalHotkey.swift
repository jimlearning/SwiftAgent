import SwiftUI
import AppKit
@preconcurrency import ApplicationServices

/// Manages the Cmd+Cmd global hotkey for appshot capture.
/// Uses NSEvent monitoring to detect double-tap Command key.
@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    public static let shared = GlobalHotkeyManager()

    @Published public var isEnabled: Bool = true
    @Published public var showToast: Bool = false
    @Published public var toastSuccess: Bool = false
    @Published public var toastMessage: String = ""

    private var lastCmdPressTime: Date = .distantPast
    private var cmdIsDown: Bool = false
    private var eventMonitor: Any?
    private var localMonitor: Any?

    /// Callback when appshot is captured successfully.
    public var onCapture: ((AppshotCapture.AppshotData) -> Void)?

    private init() {}

    // MARK: - Start/Stop

    public func startMonitoring() {
        guard eventMonitor == nil else { return }

        // Global key-down monitor
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local key-down monitor (for when app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    public func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Detection Logic

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isEnabled else { return }

        let now = Date()
        let isCmd = event.modifierFlags.contains(.command) &&
                    !event.modifierFlags.contains(.shift) &&
                    !event.modifierFlags.contains(.option) &&
                    !event.modifierFlags.contains(.control)

        if isCmd && !cmdIsDown {
            // Command key pressed
            cmdIsDown = true
            let elapsed = now.timeIntervalSince(lastCmdPressTime)

            // Detect double-tap within 200ms window
            if elapsed < 0.2 && elapsed > 0.02 {
                // Double Cmd detected!
                handleAppshotTrigger()
            }
            lastCmdPressTime = now
        } else if !isCmd {
            cmdIsDown = false
        }
    }

    // MARK: - Capture Flow

    private func handleAppshotTrigger() {
        // Reset state to avoid false triggers
        lastCmdPressTime = .distantPast
        cmdIsDown = false

        Task { @MainActor in
            await triggerCapture()
        }
    }

    /// Trigger an appshot capture manually (e.g., from menu item).
    public func triggerManualCapture() async {
        await triggerCapture()
    }

    private func triggerCapture() async {
        // Check accessibility permission
        let trusted = checkAccessibilityPermission()
        if !trusted {
            showErrorToast("Enable accessibility in System Settings")
            return
        }

        // Perform capture
        if let capture = await AppshotCapture.shared.captureActiveWindow() {
            showSuccessToast()
            onCapture?(capture)
        } else {
            showErrorToast("Cannot capture - window may be hidden")
        }
    }

    nonisolated private func checkAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Toast

    private func showSuccessToast() {
        toastSuccess = true
        toastMessage = "Screen captured"
        showToast = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            showToast = false
        }
    }

    private func showErrorToast(_ message: String) {
        toastSuccess = false
        toastMessage = message
        showToast = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showToast = false
        }
    }
}
