import Foundation
import Darwin

// MARK: - EditorRenderer

/// Renders the line editor's text buffer to the terminal.
/// Pure rendering logic — no state, no input, no popup management.
/// Uses TerminalDisplayWidth for accurate cursor positioning.
public struct EditorRenderer: Sendable {
    /// Prompt text displayed before the input line (styling applied externally).
    public let styledPrompt: String
    /// Width of the prompt in terminal columns (after ANSI stripping).
    public let promptWidth: Int
    /// Terminal columns (for wrap calculation).
    public let terminalColumns: Int

    /// Rows currently occupied on screen by the drawn content (prompt + buffer).
    public private(set) var drawnRows: Int = 1
    /// Row (0-indexed) where the cursor was left after last render.
    public private(set) var lastCursorRow: Int = 0

    public init(prompt: String, promptWidth: Int, terminalColumns: Int) {
        self.styledPrompt = "\u{001B}[1;34m\(prompt)\u{001B}[0m"
        self.promptWidth = promptWidth
        self.terminalColumns = terminalColumns
    }

    // MARK: - Bash mode

    /// Width of the visual gap rendered after the `!` prefix (in terminal columns).
    /// Always 1 (a single space), but stored as a property so `cursorPosition`
    /// can account for it without coupling to the render implementation.
    private static let bashGapWidth: Int = 1

    /// Whether the buffer is in bash mode (first character is `!`).
    public static func isBashMode(_ buffer: TextBuffer) -> Bool {
        guard let firstLine = buffer.lines.first, let first = firstLine.first else { return false }
        return first == "!"
    }

    // MARK: - Main render

    /// Full redraw of the line: clear previous content and draw buffer + ghost text.
    /// Does NOT render the popup — that's the caller's responsibility.
    public mutating func redraw(buffer: TextBuffer) {
        let lines = buffer.lines
        let totalRows = renderedRows(promptWidth: promptWidth, lines: lines)
        let bashMode = Self.isBashMode(buffer)

        // Move cursor to row 0 of previously drawn area, then clear
        if lastCursorRow > 0 {
            writeToStdout("\u{001B}[\(lastCursorRow)A")
        }
        writeToStdout("\r\u{001B}[J")

        // Draw first line with prompt
        if bashMode {
            let firstLine = lines[0]
            let rest = String(firstLine.dropFirst())
            // Colored ! (magenta bold) + rendered gap + rest of text
            writeToStdout(styledPrompt + "\u{001B}[1;35m!\u{001B}[0m " + rest)
        } else {
            writeToStdout(styledPrompt + lines[0])
        }

        // Draw continuation lines
        let pad = String(repeating: " ", count: promptWidth)
        for i in 1..<lines.count {
            writeToStdout("\r\n" + pad + lines[i])
        }

        // Calculate target cursor position
        let prefix = String(buffer.content.prefix(buffer.cursor))
        let target = cursorPosition(promptWidth: promptWidth, prefix: prefix, bashMode: bashMode)

        // Move cursor from end of drawn content up to target row
        let upRows = (totalRows - 1) - target.row
        if upRows > 0 {
            writeToStdout("\u{001B}[\(upRows)A")
        }
        writeToStdout("\r")
        if target.column > 0 {
            writeToStdout("\u{001B}[\(target.column)C")
        }

        // Ghost / placeholder text
        if let gt = buffer.ghostText {
            writeToStdout("\u{001B}[2m")
            writeToStdout("\u{001B}[90m")
            writeToStdout(gt)
            writeToStdout("\u{001B}[0m")
            writeToStdout("\r")
            if target.column > 0 {
                writeToStdout("\u{001B}[\(target.column)C")
            }
        }

        drawnRows = totalRows
        lastCursorRow = target.row
    }

    /// Move cursor below the input area (after a popup or other overlay content).
    /// Returns the row where the popup area starts (0-indexed from screen top).
    public mutating func moveToPopupArea() -> Int {
        // Move from current cursor (lastCursorRow) to the bottom of input area
        let bottomRow = drawnRows - 1
        let downToEnd = bottomRow - lastCursorRow
        if downToEnd > 0 {
            writeToStdout("\u{001B}[\(downToEnd)B")
        }
        writeToStdout("\r\n")
        let popupStartRow = drawnRows
        return popupStartRow
    }

    /// Restore cursor to a position within the input area after popup rendering.
    /// - Parameters:
    ///   - target: The (row, column) to restore to within the input area.
    ///   - popupStartRow: The row where the popup started (returned by moveToPopupArea).
    ///   - popupHeight: Number of rows the popup occupies.
    public func restoreCursorAfterPopup(
        target: (row: Int, column: Int),
        popupStartRow: Int,
        popupHeight: Int
    ) {
        let rowsAfterPopup = popupStartRow + popupHeight
        let rowsUp = rowsAfterPopup - target.row
        if rowsUp > 0 { writeToStdout("\u{001B}[\(rowsUp)A") }
        writeToStdout("\r")
        if target.column > 0 { writeToStdout("\u{001B}[\(target.column)C") }
    }

    // MARK: - Cursor position calculation

    public func cursorPosition(promptWidth: Int, prefix: String, bashMode: Bool = false) -> (row: Int, column: Int) {
        let prefixLines = prefix.components(separatedBy: "\n")
        var row = 0

        for line in prefixLines.dropLast() {
            let width = promptWidth + TerminalDisplayWidth.width(line)
            row += TerminalDisplayWidth.rows(forWidth: width, columns: terminalColumns)
        }

        let currentLine = prefixLines.last ?? ""
        // Add bash gap width when cursor is past the `!` prefix (rendered gap is
        // not stored in the buffer, so cursor calculation must account for it).
        let extraGap = (bashMode && !prefix.isEmpty) ? Self.bashGapWidth : 0
        let offset = promptWidth + TerminalDisplayWidth.width(currentLine) + extraGap
        let position = TerminalDisplayWidth.cursorPosition(forOffset: offset, columns: terminalColumns)
        return (row + position.row, position.column)
    }

    public func renderedRows(promptWidth: Int, lines: [String]) -> Int {
        lines.reduce(0) { total, line in
            let width = promptWidth + TerminalDisplayWidth.width(line)
            return total + TerminalDisplayWidth.rows(forWidth: width, columns: terminalColumns)
        }
    }

    // MARK: - Fallback

    /// Write a styled prompt for non-TTY mode (using print).
    public static func writePrompt(_ prompt: String, isTTY: Bool) {
        if isTTY {
            print("\u{001B}[1;34m\(prompt)\u{001B}[0m", terminator: "")
        } else {
            print(prompt, terminator: "")
        }
        fflush(stdout)
    }
}
