import Foundation
import SwiftAgentCore

/// Terminal output rendering utilities.
public struct TerminalRenderer: Sendable {
    public let capability: TerminalCapability
    public let theme: ColorTheme

    public init(capability: TerminalCapability = TerminalCapability(), theme: ColorTheme = .default) {
        self.capability = capability
        self.theme = theme
    }

    /// Print a styled line.
    public func write(_ text: String, color: ANSIColor? = nil, style: ANIStyle? = nil) {
        if capability.isTTY, let c = color {
            Swift.print(ansi(text, color: c, style: style))
        } else {
            Swift.print(text)
        }
    }

    /// Render a welcome banner.
    public func renderBanner(version: String) -> String {
        let banner = """
        ┌─────────────────────────────────────────┐
        │  SwiftAgent \(version.padding(toLength: 23, withPad: " ", startingAt: 0))│
        │  Swift-native AI coding agent            │
        └─────────────────────────────────────────┘
        """
        return capability.scrubANSICodes(ansi(banner, color: theme.primary, style: theme.bold))
    }

    /// Render a status line with token usage.
    public func renderStatusLine(_ snapshot: AppStateSnapshot) -> String {
        var parts: [String] = []

        if snapshot.isProcessing {
            parts.append("[Working...]")
        }

        parts.append("Tokens: ↓\(snapshot.tokenUsage.inputTokens) ↑\(snapshot.tokenUsage.outputTokens)")

        if let title = snapshot.sessionTitle {
            parts.append(title)
        }

        let line = parts.joined(separator: " | ")

        // ANSI reverse video for status area
        if capability.isTTY {
            return "\u{001B}[7m\(line.padding(toLength: capability.columns, withPad: " ", startingAt: 0))\u{001B}[0m"
        }
        return line
    }

    /// Render a streaming delta inline.
    public func renderDelta(_ text: String, current: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        return capability.scrubANSICodes(cleaned)
    }

    /// Display a permission prompt.
    public func renderPermissionPrompt(tool: String, input: String) -> String {
        let header = "Allow \(tool)?"
        let details = "  Input: \(input)"
        let options = "  [y]es / [n]o / [a]lways"
        return "\(header)\n\(details)\n\(options)"
    }

    /// Draw a horizontal rule.
    public func horizontalRule() -> String {
        String(repeating: "─", count: min(capability.columns, 80))
    }

    /// Clear screen and move cursor to home.
    public func clearScreen() -> String {
        guard capability.isTTY else { return "" }
        return "\u{001B}[2J\u{001B}[H"
    }

    /// Move cursor up N lines.
    public func cursorUp(_ lines: Int) -> String {
        guard capability.isTTY else { return "" }
        return "\u{001B}[\(lines)A"
    }

    /// Move cursor down N lines.
    public func cursorDown(_ lines: Int) -> String {
        guard capability.isTTY else { return "" }
        return "\u{001B}[\(lines)B"
    }

    /// Save cursor position.
    public func saveCursor() -> String {
        capability.isTTY ? "\u{001B}[s" : ""
    }

    /// Restore cursor position.
    public func restoreCursor() -> String {
        capability.isTTY ? "\u{001B}[u" : ""
    }
}
