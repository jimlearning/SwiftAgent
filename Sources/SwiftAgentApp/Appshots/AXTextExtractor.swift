import Foundation
import AppKit
import ApplicationServices

/// Extracts text from the currently active application window
/// using macOS Accessibility API (AXUIElementCopyAttributeValue).
public struct AXTextExtractor {

    /// Extract all visible text from the currently active window.
    public static func extractTextFromActiveWindow() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get focused window
        var windowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        guard windowResult == .success,
              let window = windowValue else {
            // Fallback: try main window
            var mainWindow: CFTypeRef?
            let mainResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXMainWindowAttribute as CFString,
                &mainWindow
            )
            guard mainResult == .success,
                  let mainWin = mainWindow else {
                return nil
            }
            return extractText(from: mainWin as! AXUIElement)
        }

        return extractText(from: window as! AXUIElement)
    }

    /// Recursively extract text from an AXUIElement.
    public static func extractText(from element: AXUIElement) -> String? {
        var allTexts: [String] = []

        // Try to get the value attribute (contains text for text elements)
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        if valueResult == .success, let val = value as? String, !val.isEmpty {
            allTexts.append(val)
        }

        // Try to get the description
        var desc: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(
            element,
            kAXDescriptionAttribute as CFString,
            &desc
        )
        if descResult == .success, let d = desc as? String, !d.isEmpty {
            allTexts.append(d)
        }

        // Try to get title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &title
        )
        if titleResult == .success, let t = title as? String, !t.isEmpty {
            allTexts.append(t)
        }

        // Get children and recurse
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        )
        if childrenResult == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray {
                if let childText = extractText(from: child) {
                    allTexts.append(childText)
                }
            }
        }

        return allTexts.isEmpty ? nil : allTexts.joined(separator: "\n")
    }
}
