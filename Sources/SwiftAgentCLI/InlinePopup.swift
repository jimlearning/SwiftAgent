import Foundation

// MARK: - Popup Configuration

/// Visual configuration for the inline popup.
public struct PopupConfig {
    /// Maximum popup height in rows (including borders).
    public let maxHeight: Int
    /// Absolute maximum popup width in columns (hard cap, also bounded by terminal).
    public let maxWidth: Int
    /// Minimum popup width in columns.
    public let minWidth: Int
    /// Left padding inside the border before item text.
    public let leftPadding: Int

    public init(maxHeight: Int = 12, maxWidth: Int = 80, minWidth: Int = 20, leftPadding: Int = 2) {
        self.maxHeight = maxHeight
        self.maxWidth = maxWidth
        self.minWidth = minWidth
        self.leftPadding = leftPadding
    }
}

// MARK: - Popup Action

/// Result of processing a key event while the popup is active.
public enum PopupActionResult {
    /// User confirmed selection — caller should replace buffer text.
    case select(PopupItem)
    /// User cancelled — caller should revert to pre-trigger state.
    case cancel
    /// Continue searching — query was updated (or unchanged for navigation keys).
    case `continue`
}

// MARK: - Inline Popup

/// Inline popup menu rendered below the input line in raw terminal mode.
///
/// Manages:
/// - Search: typing refines the query, fuzzy-matches against the data source
/// - Navigation: ↑/↓ move selection with virtual scrolling
/// - Confirmation: Enter inserts selected item; Esc cancels
///
/// Rendering uses ANSI escape codes for cursor positioning, colors, and
/// box-drawing. No dependency on TermKit or any external TUI framework.
public struct InlinePopup {

    // MARK: - State

    private let dataSource: PopupDataSource
    private let config: PopupConfig

    /// All items matching the current query, sorted by score descending.
    public private(set) var items: [PopupItem] = []
    /// Index of the currently selected item (0-based within `items`).
    public private(set) var selectedIndex: Int = 0
    /// Index of the first visible item (virtual scrolling).
    public private(set) var scrollOffset: Int = 0
    /// Current search query string.
    public private(set) var query: String = ""

    // MARK: - Init

    public init(dataSource: PopupDataSource, config: PopupConfig = PopupConfig()) {
        self.dataSource = dataSource
        self.config = config
    }

    // MARK: - Public API

    /// Update the data source and refresh items. Call when the working
    /// directory or command set changes.
    public mutating func reloadDataSource(_ dataSource: PopupDataSource) {
        self = InlinePopup(dataSource: dataSource, config: config)
        refresh()
    }

    /// Refresh items for the current query (e.g. after filesystem change).
    public mutating func refresh() {
        items = dataSource.search(query: query)
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
        // Keep scroll in sync
        if scrollOffset >= items.count {
            scrollOffset = max(0, items.count - maxVisibleItems)
        }
    }

    /// Handle a printable character: append to query, re-search, reset selection.
    public mutating func appendQuery(_ char: Character) {
        query.append(char)
        items = dataSource.search(query: query)
        selectedIndex = 0
        scrollOffset = 0
    }

    /// Delete the last character of the query. Returns `true` if the query
    /// is now empty (caller should exit popup mode).
    public mutating func deleteQueryChar() -> Bool {
        guard !query.isEmpty else { return true }
        query.removeLast()
        items = dataSource.search(query: query)
        selectedIndex = 0
        scrollOffset = 0
        return query.isEmpty
    }

    /// Move selection up by one item.
    public mutating func moveUp() {
        guard !items.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
        updateScroll()
    }

    /// Move selection down by one item.
    public mutating func moveDown() {
        guard !items.isEmpty else { return }
        if selectedIndex < items.count - 1 {
            selectedIndex += 1
        }
        updateScroll()
    }

    /// Number of terminal rows the popup occupies.
    public var height: Int {
        let visible = maxVisibleItems
        guard visible > 0 else { return 2 }  // just borders with "No matches"

        var rows = visible + 2  // items + top/bottom borders

        // Scroll indicators
        if scrollOffset > 0 { rows += 1 }
        let endIndex = min(scrollOffset + visible, items.count)
        if items.count - endIndex > 0 { rows += 1 }

        return rows
    }

    // MARK: - Private helpers

    /// How many items can be displayed in the available popup height.
    private var maxVisibleItems: Int {
        // Popup height = visibleItems + 2 (borders)
        // visibleItems = popupHeight - 2
        let maxItems = config.maxHeight - 2
        return min(items.count, max(0, maxItems))
    }

    /// Adjust scrollOffset so that selectedIndex is within the visible window.
    private mutating func updateScroll() {
        let visible = maxVisibleItems
        guard visible > 0 else { return }

        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + visible {
            scrollOffset = selectedIndex - visible + 1
        }

        // Clamp
        scrollOffset = max(0, min(scrollOffset, max(0, items.count - visible)))
    }

    // MARK: - Rendering

    /// ANSI escape sequences used throughout.
    private enum ANSI {
        static let reset = "\u{001B}[0m"
        static let bold = "\u{001B}[1m"
        static let dim = "\u{001B}[2m"
        static let reverse = "\u{001B}[7m"
        static let cyan = "\u{001B}[36m"
        static let yellow = "\u{001B}[33m"
        static let brightBlack = "\u{001B}[90m"

        static func moveUp(_ n: Int) -> String { "\u{001B}[\(n)A" }
        static func clearToEnd() -> String { "\u{001B}[0K" }
    }

    /// Render the popup by calling `write` for each output segment.
    /// The caller must position the cursor at the top-left of the popup area
    /// before calling this method.
    ///
    /// After rendering, the cursor is left at the **start of the input area**
    /// (the caller should save/restore cursor around this call).
    public func render(
        to write: (String) -> Void,
        terminalWidth: Int,
        inputStartCol: Int = 0
    ) {
        let visible = min(items.count, maxVisibleItems)

        // ── Adaptive width ──
        let haveHelp = items.contains { ($0.help ?? "").isEmpty == false }

        // Max display text width across all items (not just visible, so width is stable)
        let maxDisplayWidth = items.map { TerminalDisplayWidth.width($0.display) }.max() ?? 10
        // Estimate help column from raw help text (capped at 30), width-independent
        let maxHelpWidth: Int = haveHelp
            ? min(30, items.compactMap { $0.help }.map { TerminalDisplayWidth.width($0) }.max() ?? 0)
            : 0

        // Content-ideal = leftPadding + indicator(2) + maxDisplay + separator(2) + help + rightPadding(2)
        let contentIdeal = config.leftPadding + 2 + maxDisplayWidth + (haveHelp ? 2 + maxHelpWidth : 0) + 2
        let idealWidth = max(config.minWidth, min(contentIdeal, config.maxWidth))
        let popupWidth = min(idealWidth, terminalWidth - inputStartCol - 2)

        // Help column width from the resolved popup
        let helpWidth = haveHelp ? min(30, popupWidth / 3) : 0
        let displayWidth = popupWidth - config.leftPadding - (haveHelp ? helpWidth + 2 : 0) - 2  // -2 for right padding

        // Helper: pad or truncate text to fit, append "…" if truncated
        func fit(_ text: String, to width: Int) -> String {
            if TerminalDisplayWidth.width(text) <= width {
                return text.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            // Truncate to width-1 and append "…"
            var trimmed = ""
            var w = 0
            for char in text {
                let cw = TerminalDisplayWidth.width(String(char))
                if w + cw > width - 1 { break }
                trimmed.append(char)
                w += cw
            }
            return trimmed + "…"
        }

        // ── Top border ──
        write(ANSI.dim)
        write(ANSI.cyan)
        let title = query.isEmpty ? "" : " \(query) "
        let titleLen = TerminalDisplayWidth.width(title)
        let remainingTitle = max(0, popupWidth - titleLen - 2)  // -2 for ╭╮
        write("╭" + title + String(repeating: "─", count: remainingTitle) + "╮")
        write(ANSI.reset)
        write("\r\n")

        // ── Items ──
        let endIndex = min(scrollOffset + visible, items.count)

        // Top scroll indicator
        if scrollOffset > 0 {
            write(ANSI.dim)
            write(ANSI.brightBlack)
            let indicator = " ↑ \(scrollOffset) more "
            write("│" + indicator.padding(toLength: popupWidth - 2, withPad: " ", startingAt: 0) + "│")
            write(ANSI.reset)
            write("\r\n")
        }

        for i in scrollOffset..<endIndex {
            let item = items[i]
            let isSelected = (i == selectedIndex)

            // ── Left border ──
            write(ANSI.dim)
            write(ANSI.cyan)
            write("│")
            write(ANSI.reset)

            // ── Item content ──
            let padding = String(repeating: " ", count: config.leftPadding)
            write(padding)

            let indicator = isSelected ? "▸ " : "  "
            write(indicator)

            if isSelected {
                write(ANSI.reverse)
            }

            // Render item text with highlighting
            let highlightPositions = Set(item.matchPositions)
            var colOffset = 0  // visual column within displayWidth

            for (idx, char) in item.display.enumerated() {
                if colOffset >= displayWidth { break }
                let charWidth = TerminalDisplayWidth.width(String(char))
                if colOffset + charWidth > displayWidth {
                    write("…")
                    break
                }

                if highlightPositions.contains(idx) {
                    write(ANSI.bold)
                    write(ANSI.yellow)
                    write(String(char))
                    write(ANSI.reset)
                    if isSelected { write(ANSI.reverse) }
                } else {
                    write(String(char))
                }
                colOffset += charWidth
            }

            // Pad to fill display width
            let remaining = displayWidth - colOffset
            if remaining > 0 {
                write(String(repeating: " ", count: remaining))
            }

            if isSelected {
                write(ANSI.reset)
            }

            // ── Help text (if present) ──
            if haveHelp {
                write("  ")
                let help = item.help ?? ""
                write(ANSI.dim)
                let fittedHelp = fit(help, to: helpWidth)
                write(fittedHelp)
            }

            // ── Right border ──
            write(ANSI.dim)
            write(ANSI.cyan)
            write("│")
            write(ANSI.reset)
            write("\r\n")
        }

        // Bottom scroll indicator
        let remaining = items.count - endIndex
        if remaining > 0 {
            write(ANSI.dim)
            write(ANSI.brightBlack)
            let indicator = " ↓ \(remaining) more "
            write("│" + indicator.padding(toLength: popupWidth - 2, withPad: " ", startingAt: 0) + "│")
            write(ANSI.reset)
            write("\r\n")
        }

        // ── Bottom border ──
        write(ANSI.dim)
        write(ANSI.cyan)
        write("╰" + String(repeating: "─", count: popupWidth - 2) + "╯")
        write(ANSI.reset)
        write("\r\n")
    }
}
