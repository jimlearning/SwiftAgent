import Foundation

/// Converts markdown text to ANSI-formatted terminal output.
/// Post-processes accumulated response text before display.
/// Rendering style inspired by TermKit's MarkdownView.
public struct MarkdownRenderer: Sendable {
    private let capability: TerminalCapability
    private let theme: ColorTheme

    public init(capability: TerminalCapability, theme: ColorTheme) {
        self.capability = capability
        self.theme = theme
    }

    // MARK: - Public

    /// Render markdown string to ANSI-formatted string.
    public func render(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var result: [String] = []
        var inFence = false
        var fenceLang: String? = nil
        var fenceLines: [String] = []
        var tableBuffer: [String] = []

        /// Flush table buffer: detect if it forms a valid table, render accordingly.
        func flushTableBuffer() {
            defer { tableBuffer = [] }
            guard tableBuffer.count >= 2,
                  isTableRow(tableBuffer[0]),
                  isSeparatorRow(tableBuffer[1]) else {
                // Not a table — render as regular lines
                for line in tableBuffer {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        result.append(border(""))
                    } else if let heading = renderHeading(line) {
                        result.append(heading)
                    } else {
                        result.append(border(renderInline(line)))
                    }
                }
                return
            }
            renderTable(header: tableBuffer[0], separator: tableBuffer[1],
                        rows: Array(tableBuffer.dropFirst(2)), into: &result)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Fenced code block detection ---
            if trimmed.hasPrefix("```") {
                flushTableBuffer()
                if inFence {
                    renderCodeBlock(fenceLines, language: fenceLang, into: &result)
                    fenceLines = []
                    inFence = false
                    fenceLang = nil
                } else {
                    fenceLang = extractLanguage(from: trimmed)
                    inFence = true
                }
                continue
            }

            if inFence {
                fenceLines.append(line)
                continue
            }

            // --- Table buffering ---
            if isTableRow(line) || isSeparatorRow(trimmed) {
                tableBuffer.append(line)
                continue
            } else if !tableBuffer.isEmpty {
                flushTableBuffer()
            }

            // --- Block-level elements ---
            if let heading = renderHeading(line) {
                result.append(heading)
            } else if let blockquote = renderBlockquote(line) {
                result.append(blockquote)
            } else if let listItem = renderListItem(line) {
                result.append(listItem)
            } else if let divider = renderDivider(trimmed) {
                result.append(divider)
            } else if trimmed.isEmpty {
                result.append(border(""))
            } else {
                result.append(border(renderInline(line)))
            }
        }

        flushTableBuffer()

        // Unclosed fence — render what we have
        if inFence && !fenceLines.isEmpty {
            renderCodeBlock(fenceLines, language: fenceLang, into: &result)
        }

        return result.joined(separator: "\n") + "\n"
    }

    // MARK: - Code blocks (TermKit-style boxed)

    private func renderCodeBlock(_ lines: [String], language: String?, into result: inout [String]) {
        guard !lines.isEmpty else { return }

        // Calculate inner width from the longest line (capped by terminal width)
        let maxContentLen = lines.map(TerminalDisplayWidth.width).max() ?? 0
        let innerWidth = min(max(maxContentLen, 8), max(0, capability.columns - 6))
        let langLabel = language.map { " \($0) " } ?? ""
        // Box border adds 4 columns ("│ " + " │"), so top/bottom need innerWidth + 2 dashes
        let dashCount = innerWidth + 2

        // Top border: ┌──────── lang ────────┐
        let topDashCount = max(0, dashCount - TerminalDisplayWidth.width(langLabel))
        let topBorder = "┌" + repeatChar("─", topDashCount) + langLabel + "┐"
        result.append(border(dim(topBorder)))

        // Content lines: │ padded content │
        for line in lines {
            let padded = padToVisibleWidth(line, width: innerWidth)
            result.append(border(dim("│ " + padded + " │")))
        }

        // Bottom border: └──────────────────┘
        let bottom = "└" + repeatChar("─", dashCount) + "┘"
        result.append(border(dim(bottom)))
    }

    private func extractLanguage(from fence: String) -> String? {
        let lang = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? nil : lang
    }

    // MARK: - Headings (TermKit-style)

    private func renderHeading(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(#{1,6})\s+(.+)/#) else { return nil }
        let level = match.1.count
        let text = String(match.2)
        let styled = capability.color(text, color: headingColor(level), style: .bold)
        let prefix = border("")

        switch level {
        case 1:
            // H1: Overline + text + underline with ═
            let rule = repeatChar("═", text.count)
            return prefix + "\n" + border(dim(rule)) + "\n" + border(styled) + "\n" + border(dim(rule))
        case 2:
            // H2: Text + underline with ─
            let rule = repeatChar("─", text.count)
            return border(styled) + "\n" + border(dim(rule))
        case 3:
            // H3: Just bold + color, no underline
            return border(styled)
        default:
            // H4+: Bold only
            return border(bold(text))
        }
    }

    private func headingColor(_ level: Int) -> ANSIColor {
        switch level {
        case 1: .brightBlue
        case 2: .brightGreen
        case 3: .brightYellow
        default: .white
        }
    }

    // MARK: - Blockquote

    private func renderBlockquote(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^>\s?(.+)/#) else { return nil }
        let text = String(match.1)
        return border(dim("▎ ") + dim(renderInline(text)))
    }

    // MARK: - Divider (horizontal rule)

    private func renderDivider(_ trimmed: String) -> String? {
        let isDivider = trimmed.allSatisfy { $0 == "-" } && trimmed.count >= 3
                      || trimmed.allSatisfy { $0 == "*" } && trimmed.count >= 3
                      || trimmed.allSatisfy { $0 == "_" } && trimmed.count >= 3
        guard isDivider else { return nil }
        let width = max(0, capability.columns - 4)
        return border(dim(String(repeating: "─", count: width)))
    }

    // MARK: - List items

    private func renderListItem(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(\s*)[-*]\s+(.+)/#) else { return nil }
        let indent = String(repeating: " ", count: match.1.count)
        let text = String(match.2)
        return border(indent + capability.color("•", color: theme.secondary) + " " + renderInline(text))
    }

    // MARK: - Table rendering

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|")
    }

    private func isSeparatorRow(_ trimmed: String) -> Bool {
        // Separator: |---|:---:|---|  (only dashes, colons, pipes, spaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let inner = trimmed.dropFirst().dropLast()
        let allowed: Set<Character> = ["|", "-", ":", " "]
        return !inner.isEmpty && inner.allSatisfy { allowed.contains($0) }
    }

    private func renderTable(header: String, separator: String, rows: [String], into result: inout [String]) {
        let headerCols = parseColumns(header)
        let sepCols = parseColumns(separator)
        let dataCols = rows.map(parseColumns)

        guard !headerCols.isEmpty else { return }
        let colCount = headerCols.count

        // Calculate max width per column
        var colWidths = Array(repeating: 3, count: colCount) // minimum width
        for i in 0..<colCount {
            colWidths[i] = max(colWidths[i], TerminalDisplayWidth.width(headerCols[i]))
            for row in dataCols where i < row.count {
                colWidths[i] = max(colWidths[i], TerminalDisplayWidth.width(row[i]))
            }
        }

        // Alignments from separator row (default: left)
        var alignments = Array(repeating: TableAlignment.left, count: colCount)
        for i in 0..<min(colCount, sepCols.count) {
            let sep = sepCols[i].trimmingCharacters(in: .whitespaces)
            if sep.hasPrefix(":") && sep.hasSuffix(":") { alignments[i] = .center }
            else if sep.hasSuffix(":") { alignments[i] = .right }
            else { alignments[i] = .left }
        }

        // Render header — bold cells within dim borders (inner bold doesn't reset dim)
        let headerCells = headerCols.enumerated().map { i, col in
            innerBold(padCell(col, width: colWidths[i], alignment: .center))
        }
        result.append(border(dim("│ " + headerCells.joined(separator: " │ ") + " │")))

        // Separator line with box chars
        let sepLine = colWidths.map { repeatChar("─", $0 + 2) }.joined(separator: "┼")
        result.append(border(dim("├" + sepLine + "┤")))

        // Data rows
        for row in dataCols {
            let cells: [String]
            if row.count >= colCount {
                cells = row.enumerated().map { i, col -> String in
                    let width = colWidths[min(i, colWidths.count - 1)]
                    let align = alignments[min(i, alignments.count - 1)]
                    return padCell(col, width: width, alignment: align)
                }
            } else {
                // Pad missing columns
                var padded = [String]()
                for i in 0..<colCount {
                    let col = i < row.count ? row[i] : ""
                    padded.append(padCell(col, width: colWidths[i], alignment: alignments[i]))
                }
                cells = padded
            }
            result.append(border(dim("│ " + cells.joined(separator: " │ ") + " │")))
        }
    }

    private enum TableAlignment { case left, center, right }

    private func parseColumns(_ row: String) -> [String] {
        var cols = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // Drop leading empty and trailing empty from split (outer pipes)
        if let first = cols.first, first.trimmingCharacters(in: .whitespaces).isEmpty { cols.removeFirst() }
        if let last = cols.last, last.trimmingCharacters(in: .whitespaces).isEmpty { cols.removeLast() }
        return cols.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func padCell(_ text: String, width: Int, alignment: TableAlignment) -> String {
        let visibleWidth = TerminalDisplayWidth.width(text)
        switch alignment {
        case .left:
            return padToVisibleWidth(text, width: width)
        case .right:
            let pad = String(repeating: " ", count: max(0, width - visibleWidth))
            return pad + text
        case .center:
            let totalPad = max(0, width - visibleWidth)
            let leftPad = totalPad / 2
            let rightPad = totalPad - leftPad
            return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
        }
    }

    private func padToVisibleWidth(_ text: String, width: Int) -> String {
        let pad = max(0, width - TerminalDisplayWidth.width(text))
        return text + String(repeating: " ", count: pad)
    }

    // MARK: - Inline rendering

    private func renderInline(_ line: String) -> String {
        var result = line
        result = replaceLinks(result)
        result = replaceCodeSpans(result)
        result = replaceBold(result)
        result = replaceItalic(result)
        return result
    }

    /// Replace `code` with standout-styled text. Backtick content is literal.
    private func replaceCodeSpans(_ text: String) -> String {
        let pattern = #/`([^`]+)`/#
        return text.replacing(pattern) { match in
            inlineCode(String(match.1))
        }
    }

    /// Replace **bold** with ANSI bold.
    private func replaceBold(_ text: String) -> String {
        let pattern = #/\*\*(.+?)\*\*/#
        return text.replacing(pattern) { match in
            bold(String(match.1))
        }
    }

    /// Replace *italic* with ANSI italic. Bold processed first, so remaining *text* is italic.
    private func replaceItalic(_ text: String) -> String {
        let pattern = #/\*(.+?)\*/#
        return text.replacing(pattern) { match in
            italic(String(match.1))
        }
    }

    /// Replace [text](url) with underlined styled text.
    private func replaceLinks(_ text: String) -> String {
        let pattern = #/\[([^\]]+)\]\(([^)]+)\)/#
        return text.replacing(pattern) { match in
            let linkText = String(match.1)
            return capability.color(linkText, color: theme.secondary, style: .underline)
        }
    }

    // MARK: - ANSI helpers

    private func border(_ text: String) -> String {
        capability.color("│ ", color: theme.secondary) + text
    }

    private func bold(_ text: String) -> String {
        styled(text, style: .bold)
    }

    /// Bold that toggles bold on/off within a dim context.
    /// \033[22m resets intensity (both bold and dim), so we re-apply \033[2m after.
    private func innerBold(_ text: String) -> String {
        capability.supportsColor
            ? "\u{001B}[1m\(text)\u{001B}[22m\u{001B}[2m"
            : text
    }

    private func italic(_ text: String) -> String {
        styled(text, style: .italic)
    }

    private func dim(_ text: String) -> String {
        styled(text, style: .dim)
    }

    /// Inline code: underlined dim for standout effect against normal text.
    private func inlineCode(_ text: String) -> String {
        capability.supportsColor
            ? "\u{001B}[2m\u{001B}[4m\(text)\u{001B}[0m"
            : text
    }

    private func styled(_ text: String, style: ANIStyle) -> String {
        capability.supportsColor
            ? "\u{001B}[\(style.rawValue)m\(text)\u{001B}[0m"
            : text
    }

    private func repeatChar(_ ch: Character, _ count: Int) -> String {
        count > 0 ? String(repeating: ch, count: count) : ""
    }
}
