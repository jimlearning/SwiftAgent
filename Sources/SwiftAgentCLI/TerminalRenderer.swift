import Foundation
import Darwin
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
        let innerWidth = 41 // must match the number of ─ in the box borders
        func padLine(_ text: String) -> String {
            text.padding(toLength: innerWidth, withPad: " ", startingAt: 0)
        }
        let line1 = "│" + padLine("  SwiftAgent \(version)") + "│"
        let line2 = "│" + padLine("  Swift-native AI coding agent") + "│"
        let hline = String(repeating: "─", count: innerWidth)
        let banner = "┌\(hline)┐\n\(line1)\n\(line2)\n└\(hline)┘"
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

    // MARK: - Panel rendering (Nanobot-style Rich Panel equivalent)

    /// Render a boxed panel around content text, similar to Rich's `Panel(Markdown(content))`.
    /// Uses Unicode box-drawing characters with optional colored border.
    public func renderPanel(title: String, content: String, borderColor: ANSIColor = .cyan) -> String {
        let termWidth = capability.columns
        let panelWidth = min(termWidth, 80)
        let innerWidth = panelWidth - 4 // "│ " + " │"

        // Wrap lines to inner width
        let rawLines = content.components(separatedBy: "\n")
        var wrappedLines: [String] = []
        for line in rawLines {
            if line.isEmpty {
                wrappedLines.append("")
                continue
            }
            var remaining = line
            while !remaining.isEmpty {
                if remaining.count <= innerWidth {
                    wrappedLines.append(remaining)
                    break
                }
                // Try to break at a word boundary
                let breakIndex = remaining.index(
                    remaining.startIndex, offsetBy: innerWidth, limitedBy: remaining.endIndex
                ) ?? remaining.endIndex
                if breakIndex == remaining.endIndex || remaining[breakIndex] == " " {
                    wrappedLines.append(String(remaining[..<breakIndex]))
                    remaining = String(remaining[remaining.index(after: breakIndex)...])
                    if remaining.first == " " { remaining = String(remaining.dropFirst()) }
                } else {
                    // Find last space within the width
                    if let lastSpace = remaining[..<breakIndex].lastIndex(of: " ") {
                        wrappedLines.append(String(remaining[..<lastSpace]))
                        remaining = String(remaining[remaining.index(after: lastSpace)...])
                    } else {
                        // Hard break — no spaces found
                        wrappedLines.append(String(remaining[..<breakIndex]))
                        remaining = String(remaining[breakIndex...])
                    }
                }
            }
        }

        let colorize = { (s: String) -> String in self.capability.color(s, color: borderColor) }

        // Top border: ╭── title ────────────────────────╮
        let titleSegment = "── " + title + " ──"
        let remainingTop = max(0, panelWidth - 2 - titleSegment.count)
        var result = ""
        result += colorize("╭" + titleSegment + String(repeating: "─", count: remainingTop) + "╮")
        result += "\n"

        // Empty padding line after top border
        result += colorize("│" + String(repeating: " ", count: panelWidth - 2) + "│")
        result += "\n"

        // Content lines
        for line in wrappedLines {
            let padded = line.padding(toLength: innerWidth, withPad: " ", startingAt: 0)
            result += colorize("│ ") + padded + colorize(" │")
            result += "\n"
        }

        // Empty padding line before bottom border
        result += colorize("│" + String(repeating: " ", count: panelWidth - 2) + "│")
        result += "\n"

        // Bottom border
        result += colorize("╰" + String(repeating: "─", count: panelWidth - 2) + "╯")

        return capability.scrubANSICodes(result)
    }

    /// Render content with a simple left border (no top/bottom/right borders).
    /// Used for AI response display — cleaner than the full panel.
    public func renderLeftBorder(content: String, color: ANSIColor = .cyan) -> String {
        let colorize = { (s: String) -> String in self.capability.color(s, color: color) }
        let rawLines = content.components(separatedBy: "\n")
        var result = ""
        for line in rawLines {
            result += colorize("│ ") + line + "\n"
        }
        return capability.scrubANSICodes(result)
    }

    // MARK: - Spinner

    /// A single spinner frame for inline animation (e.g., during LLM generation).
    /// Returns the ANSI string for one frame of a dots spinner.
    public func spinnerFrame(index: Int) -> String {
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let frame = frames[index % frames.count]
        return capability.color(frame, color: .cyan)
    }

    /// Renders a "Thinking..." line with spinner.
    public func renderThinkingLine(frame: Int) -> String {
        return "\r  \(spinnerFrame(index: frame)) Thinking..."
    }

    // MARK: - TTY drain (Nanobot's `_flush_pending_tty_input`)

    /// Discard unread keypresses typed while the model was generating, so they
    /// don't appear as the next input line.
    public func drainTTYInput() {
        let fd = STDIN_FILENO
        guard isatty(fd) != 0 else { return }

        // Try termios flush first (faster, comprehensive)
        var term = termios()
        if tcgetattr(fd, &term) == 0 {
            tcflush(fd, TCIFLUSH)
            return
        }

        // Fallback: non-blocking read to drain buffer
        var fds = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        var buf = [UInt8](repeating: 0, count: 4096)
        while poll(&fds, 1, 0) > 0 && (fds.revents & Int16(POLLIN)) != 0 {
            if read(fd, &buf, buf.count) <= 0 { break }
        }
    }
}
