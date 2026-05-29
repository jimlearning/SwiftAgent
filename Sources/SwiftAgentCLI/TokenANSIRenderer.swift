import Foundation
import SwiftAgentCore

/// Renders syntax highlight tokens as ANSI-colored text.
struct TokenANSIRenderer: Sendable {
    let theme: CodeTheme
    let capability: TerminalCapability

    /// Convert a source string with tokens into ANSI-colored output.
    /// Tokens must be sorted by location and non-overlapping.
    func render(_ source: String, tokens: [HighlightToken]) -> String {
        guard capability.supportsColor, !tokens.isEmpty else { return source }

        let nsSource = source as NSString
        var result = ""
        var pos = 0

        for token in tokens {
            let start = token.range.location
            let end = token.range.location + token.range.length

            // Skip tokens that fall behind our current position
            guard end > pos, start >= pos else { continue }

            // Plain text between tokens
            if start > pos {
                result += nsSource.substring(with: NSRange(location: pos, length: start - pos))
            }

            let text = nsSource.substring(with: token.range)

            if let color = theme.color(for: token.captureName) {
                result += capability.color(text, color: color)
            } else {
                result += text
            }

            pos = end
        }

        // Trailing text
        if pos < nsSource.length {
            result += nsSource.substring(with: NSRange(location: pos, length: nsSource.length - pos))
        }

        return result
    }

    /// Render source with tokens into an array of lines, where each line has
    /// **balanced ANSI codes**. Tokens that span multiple lines (e.g., multi-line
    /// comments or strings) would otherwise leave unclosed ANSI codes on line
    /// boundaries, leaking color into subsequent lines. This method detects
    /// open codes at the end of each line and closes them, then re-opens them
    /// at the start of the next line.
    func renderLines(_ source: String, tokens: [HighlightToken]) -> [String] {
        let rendered = render(source, tokens: tokens)
        let rawLines = rendered.components(separatedBy: "\n")

        guard rawLines.count > 1 else { return rawLines }

        var balanced: [String] = []
        var pendingOpen: String = ""

        for line in rawLines {
            var currentLine = line

            // Re-open ANSI sequences that were open at end of previous line
            if !pendingOpen.isEmpty {
                currentLine = pendingOpen + currentLine
            }

            // Determine what's still open at end of this line
            let stillOpen = openANSIStack(atEndOf: currentLine)

            // Close any still-open sequences so they don't leak into the next line
            if !stillOpen.isEmpty {
                currentLine += "\u{001B}[0m"
            }

            balanced.append(currentLine)
            pendingOpen = stillOpen.joined()
        }

        return balanced
    }

    // MARK: - Private helpers

    /// Returns the stack of ANSI escape sequences that remain open at the
    /// end of `line` (i.e., have not been followed by `\033[0m` or `\033[22m`).
    private func openANSIStack(atEndOf line: String) -> [String] {
        var stack: [String] = []
        var idx = line.startIndex

        while idx < line.endIndex {
            guard line[idx] == "\u{001B}" else {
                idx = line.index(after: idx)
                continue
            }
            let afterEsc = line.index(after: idx)
            guard afterEsc < line.endIndex, line[afterEsc] == "[" else {
                idx = afterEsc
                continue
            }

            let seqStart = idx
            idx = line.index(after: afterEsc) // skip past '['

            // Scan to the terminating letter (skipping digits, semicolons, etc.)
            while idx < line.endIndex, !line[idx].isLetter {
                idx = line.index(after: idx)
            }
            guard idx < line.endIndex else { break }
            idx = line.index(after: idx) // include the terminating letter

            let seq = String(line[seqStart..<idx])

            // \033[0m — full reset of all attributes
            if seq == "\u{001B}[0m" {
                stack.removeAll()
            } else if seq == "\u{001B}[22m" {
                // Normal intensity: only removes bold (1) and dim (2), not colors
                stack.removeAll { $0 == "\u{001B}[1m" || $0 == "\u{001B}[2m" }
            } else if seq.hasPrefix("\u{001B}[") {
                stack.append(seq)
            }
        }

        return stack
    }
}
