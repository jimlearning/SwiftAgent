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
}
