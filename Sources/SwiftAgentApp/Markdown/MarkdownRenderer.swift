import SwiftUI
import SwiftAgentCore

/// Renders Markdown text into an `AttributedString` suitable for SwiftUI `Text`.
///
/// Reuses `RegexSyntaxHighlighter` and `LanguageRegistry` from SwiftAgentCore
/// for code-block syntax highlighting. Token capture names are mapped to
/// SwiftUI `Color` via `CodeColors`.
public struct MarkdownRenderer: Sendable {
    private let highlighter = RegexSyntaxHighlighter()
    private let baseFont: Font
    private let codeFont: Font
    private let foregroundColor: Color

    public init(
        baseFont: Font = Font.system(size: 13, weight: .regular),
        codeFont: Font = Font.system(size: 13, design: .monospaced),
        foregroundColor: Color = Color(red: 0.961, green: 0.961, blue: 0.961)
    ) {
        self.baseFont = baseFont
        self.codeFont = codeFont
        self.foregroundColor = foregroundColor
    }

    // MARK: - Public API

    public func render(_ markdown: String) -> AttributedString {
        guard !markdown.isEmpty else { return AttributedString("") }

        let lines = markdown.components(separatedBy: .newlines)
        var result = AttributedString()
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if let fence = codeFenceStart(line) {
                let (codeLines, nextIndex, language) = extractCodeBlock(
                    from: lines, start: i, fence: fence
                )
                if !codeLines.isEmpty {
                    result += renderCodeBlock(codeLines, language: language)
                    result += AttributedString("\n")
                }
                i = nextIndex
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                result += renderHeading(level: level, text)
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Blockquote
            if let text = parseBlockquote(line) {
                result += renderBlockquote(text)
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Unordered list item
            if let text = parseUnorderedListItem(line) {
                result += renderListItem(text)
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Ordered list item
            if let text = parseOrderedListItem(line) {
                result += renderListItem(text)
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces) == "---"
                || line.trimmingCharacters(in: .whitespaces) == "***" {
                result += renderHorizontalRule()
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result += AttributedString("\n")
                i += 1
                continue
            }

            // Regular paragraph line
            result += renderInline(line)
            result += AttributedString("\n")
            i += 1
        }

        return result
    }

    // MARK: - Shared Highlighting Utility

    /// Syntax-highlight source code and return an `AttributedString`.
    /// Reusable by any view that displays code (Review panel, Files preview, etc.).
    ///
    /// - Parameters:
    ///   - code: Raw source code.
    ///   - language: Optional language tag (e.g. `"swift"`, `"python"`).
    ///     If nil, language is heuristically detected.
    ///   - font: Monospace font for code. Default 12pt.
    ///   - foregroundColor: Default text color for unhighlighted code.
    /// - Returns: Syntax-colored `AttributedString`.
    public static func highlightCode(
        _ code: String,
        language: String?,
        font: Font = Font.system(size: 12, design: .monospaced),
        foregroundColor: Color = Color(red: 0.961, green: 0.961, blue: 0.961)
    ) -> AttributedString {
        guard !code.isEmpty else { return AttributedString("") }

        let highlighter = RegexSyntaxHighlighter()
        let lang = language ?? Self.detectLanguage(code)
        let tokens = lang.flatMap { highlighter.highlight(code, language: $0) }

        let nsCode = code as NSString
        var result = AttributedString()

        if let tokens, !tokens.isEmpty {
            var lastEnd = 0
            for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
                if token.range.location > lastEnd {
                    let plainText = nsCode.substring(
                        with: NSRange(location: lastEnd, length: token.range.location - lastEnd)
                    )
                    var attr = AttributedString(plainText)
                    attr.font = font
                    attr.foregroundColor = foregroundColor
                    result += attr
                }
                let tokenText = nsCode.substring(with: token.range)
                let tokenColor = CodeColors.color(for: token.captureName) ?? foregroundColor
                var tokenAttr = AttributedString(tokenText)
                tokenAttr.font = font
                tokenAttr.foregroundColor = tokenColor
                result += tokenAttr
                lastEnd = token.range.location + token.range.length
            }
            if lastEnd < nsCode.length {
                let plainText = nsCode.substring(
                    with: NSRange(location: lastEnd, length: nsCode.length - lastEnd)
                )
                var attr = AttributedString(plainText)
                attr.font = font
                attr.foregroundColor = foregroundColor
                result += attr
            }
        } else {
            var attr = AttributedString(code)
            attr.font = font
            attr.foregroundColor = foregroundColor
            result = attr
        }

        return result
    }

    /// Detect the file extension from a URL or file name for language detection.
    public static func languageFromFileExtension(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "typescript"
        case "jsx": return "javascript"
        case "sh", "bash", "zsh": return "bash"
        case "go": return "go"
        case "rs": return "rust"
        case "c": return "c"
        case "cpp", "cc", "cxx": return "cpp"
        case "h", "hpp": return "cpp"
        case "rb": return "ruby"
        case "sql": return "sql"
        case "yaml", "yml": return "yaml"
        case "json": return "json"
        case "toml": return "toml"
        case "css": return "css"
        case "html": return "html"
        case "md", "markdown": return "markdown"
        default: return nil
        }
    }

    // MARK: - Code Block Parsing

    /// Returns (fence string, language) if the line starts a code fence, nil otherwise.
    private func codeFenceStart(_ line: String) -> (fence: String, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }

        let fenceChar = String(trimmed.prefix(3))
        let afterFence = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let language = afterFence.isEmpty ? nil : afterFence
        return (fenceChar, language)
    }

    /// Extract a fenced code block. Returns (joined code lines, next line index, language).
    private func extractCodeBlock(
        from lines: [String], start: Int, fence: (fence: String, language: String?)
    ) -> (String, Int, String?) {
        var code: [String] = []
        var i = start + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence.fence) { break }
            code.append(lines[i])
            i += 1
        }
        // Skip closing fence
        if i < lines.count { i += 1 }
        return (code.joined(separator: "\n"), i, fence.language)
    }

    // MARK: - Line Parsing

    private func parseHeading(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level <= 6 else { return nil }
        let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func parseUnorderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
        return nil
    }

    private func parseOrderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isNumber else { return nil }
        guard let dotIndex = trimmed.firstIndex(of: "."),
              dotIndex < trimmed.index(before: trimmed.endIndex),
              trimmed[trimmed.index(after: dotIndex)] == " " else { return nil }
        return String(trimmed[trimmed.index(dotIndex, offsetBy: 2)...])
    }

    // MARK: - Block Renderers

    private func renderCodeBlock(_ code: String, language: String?) -> AttributedString {
        var block = AttributedString()

        // Use the Core syntax highlighter if we recognize the language
        let lang = language ?? Self.detectLanguage(code)
        let tokens = lang.flatMap { highlighter.highlight(code, language: $0) }

        let nsCode = code as NSString
        if let tokens, !tokens.isEmpty {
            var lastEnd = 0
            for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
                if token.range.location > lastEnd {
                    let plainText = nsCode.substring(
                        with: NSRange(location: lastEnd, length: token.range.location - lastEnd)
                    )
                    block += codeAttributedString(plainText)
                }
                let tokenText = nsCode.substring(with: token.range)
                let tokenColor = CodeColors.color(for: token.captureName) ?? foregroundColor
                var tokenAttr = AttributedString(tokenText)
                tokenAttr.font = codeFont
                tokenAttr.foregroundColor = tokenColor
                block += tokenAttr
                lastEnd = token.range.location + token.range.length
            }
            if lastEnd < nsCode.length {
                let plainText = nsCode.substring(
                    with: NSRange(location: lastEnd, length: nsCode.length - lastEnd)
                )
                block += codeAttributedString(plainText)
            }
        } else {
            block += codeAttributedString(code)
        }

        return block
    }

    private func codeAttributedString(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = codeFont
        attr.foregroundColor = foregroundColor
        return attr
    }

    private func renderHeading(level: Int, _ text: String) -> AttributedString {
        let sizes: [CGFloat] = [0, 20, 17, 15, 14, 13, 12]
        let size = level < sizes.count ? sizes[level] : 12
        let weight: Font.Weight = level <= 2 ? .bold : .semibold

        var attr = renderInline(text)
        attr.font = .system(size: size, weight: weight)
        attr.foregroundColor = foregroundColor
        return attr
    }

    private func renderBlockquote(_ text: String) -> AttributedString {
        var attr = AttributedString()
        // ▎ prefix in secondary color
        var prefix = AttributedString("▎ ")
        prefix.foregroundColor = .textTertiary
        attr += prefix
        attr += renderInline(text).dimmed()
        return attr
    }

    private func renderListItem(_ text: String) -> AttributedString {
        var attr = AttributedString()
        var bullet = AttributedString("  • ")
        bullet.foregroundColor = .textSecondary
        attr += bullet
        attr += renderInline(text)
        return attr
    }

    private func renderHorizontalRule() -> AttributedString {
        var attr = AttributedString(String(repeating: "─", count: 40))
        attr.foregroundColor = .textTertiary
        attr.font = .system(size: 8)
        return attr
    }

    // MARK: - Inline Rendering

    private func renderInline(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }

        var result = AttributedString()
        var remaining = text

        while !remaining.isEmpty {
            // Inline code: `...`
            if let (code, before, after) = extractInlineCode(remaining) {
                if !before.isEmpty { result += plainText(before) }
                result += renderInlineCode(code)
                remaining = after
                continue
            }

            // Bold: **...**
            if let (bold, before, after) = extractDelimited(remaining, delimiter: "**") {
                if !before.isEmpty { result += plainText(before) }
                result += renderBold(bold)
                remaining = after
                continue
            }

            // Italic: *...* (but not **)
            if let (italic, before, after) = extractDelimited(remaining, delimiter: "*") {
                if !before.isEmpty { result += plainText(before) }
                result += renderItalic(italic)
                remaining = after
                continue
            }

            // Link: [text](url)
            if let (linkText, url, before, after) = extractLink(remaining) {
                if !before.isEmpty { result += plainText(before) }
                result += renderLink(text: linkText, url: url)
                remaining = after
                continue
            }

            // Plain text — consume up to the next special character
            if let nextSpecial = findNextSpecial(remaining) {
                let idx = remaining.distance(from: remaining.startIndex, to: nextSpecial)
                if idx > 0 {
                    let plain = String(remaining.prefix(idx))
                    result += plainText(plain)
                    remaining = String(remaining.dropFirst(idx))
                } else {
                    // At a special char — consume it as plain text and advance
                    result += plainText(String(remaining.prefix(1)))
                    remaining = String(remaining.dropFirst())
                }
            } else {
                result += plainText(remaining)
                remaining = ""
            }
        }

        return result
    }

    private func plainText(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = baseFont
        attr.foregroundColor = foregroundColor
        return attr
    }

    private func renderInlineCode(_ code: String) -> AttributedString {
        var attr = AttributedString(code)
        attr.font = codeFont
        attr.foregroundColor = .textPrimary
        attr.backgroundColor = .codeInlineBG
        return attr
    }

    private func renderBold(_ text: String) -> AttributedString {
        var inner = renderInline(text)
        inner.font = baseFont.bold()
        return inner
    }

    private func renderItalic(_ text: String) -> AttributedString {
        var inner = renderInline(text)
        inner.font = baseFont.italic()
        return inner
    }

    private func renderLink(text: String, url: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = baseFont
        attr.foregroundColor = .accentPrimary
        attr.underlineStyle = .single
        if let nsurl = URL(string: url) {
            attr.link = nsurl
        }
        return attr
    }

    // MARK: - Inline Extractors

    /// Extract `` `code` `` from the start of a string. Returns (code, text-before, text-after).
    private func extractInlineCode(_ text: String) -> (String, String, String)? {
        guard let firstBacktick = text.firstIndex(of: "`") else { return nil }
        let afterFirst = text.index(after: firstBacktick)
        guard let secondBacktick = text[afterFirst...].firstIndex(of: "`") else { return nil }
        let before = String(text[..<firstBacktick])
        let code = String(text[afterFirst..<secondBacktick])
        let after = String(text[text.index(after: secondBacktick)...])
        return (code, before, after)
    }

    /// Extract `**bold**` or `*italic*`. Returns (inner, before, after).
    private func extractDelimited(_ text: String, delimiter: String) -> (String, String, String)? {
        guard let first = text.range(of: delimiter) else { return nil }
        let searchStart = text.index(first.upperBound, offsetBy: 0)
        guard searchStart < text.endIndex,
              let second = text[searchStart...].range(of: delimiter) else { return nil }
        let before = String(text[..<first.lowerBound])
        let inner = String(text[first.upperBound..<second.lowerBound])
        let after = String(text[second.upperBound...])
        guard !inner.isEmpty else { return nil }
        return (inner, before, after)
    }

    /// Extract `[text](url)`. Returns (text, url, before, after).
    private func extractLink(_ text: String) -> (String, String, String, String)? {
        guard let bracketOpen = text.firstIndex(of: "["),
              let bracketClose = text[bracketOpen...].firstIndex(of: "]") else { return nil }
        let afterClose = text.index(after: bracketClose)
        guard afterClose < text.endIndex, text[afterClose] == "(",
              let parenClose = text[afterClose...].firstIndex(of: ")") else { return nil }
        let before = String(text[..<bracketOpen])
        let linkText = String(text[text.index(after: bracketOpen)..<bracketClose])
        let url = String(text[text.index(after: afterClose)..<parenClose])
        let after = String(text[text.index(after: parenClose)...])
        return (linkText, url, before, after)
    }

    /// Find the position of the next markdown-special character.
    private func findNextSpecial(_ text: String) -> String.Index? {
        let specials: [Character] = ["`", "*", "[", "!", "_", "~"]
        var earliest: String.Index?
        for ch in specials {
            if let idx = text.firstIndex(of: ch) {
                if earliest == nil || idx < earliest! {
                    earliest = idx
                }
            }
        }
        return earliest
    }

    // MARK: - Language Detection

    /// Heuristic language detection for code blocks without a fenced language tag.
    /// Mirrors the CLI's `detectLanguage` but simplified for SwiftUI.
    private static func detectLanguage(_ code: String) -> String? {
        let lines = code.components(separatedBy: .newlines).prefix(10)
        let joined = lines.joined(separator: "\n")

        let detectors: [(String, [String])] = [
            ("swift", ["import Swift", "import Foundation", "struct ", "class ", "enum ", "let ", "var ", "func "]),
            ("python", ["import ", "def ", "class ", "from ", "print("]),
            ("javascript", ["const ", "let ", "function ", "import {", "require("]),
            ("typescript", ["interface ", "type ", ": string", ": number", "export "]),
            ("bash", ["#!/bin/bash", "#!/usr/bin/env bash", "echo ", "export "]),
            ("go", ["package ", "func ", "import (", "fmt."]),
            ("rust", ["fn ", "let mut", "impl ", "use ", "struct ", "enum "]),
            ("json", ["{", "\""]),
            ("sql", ["SELECT ", "CREATE TABLE", "INSERT INTO", "FROM ", "WHERE "]),
            ("yaml", ["apiVersion:", "kind:", "metadata:", "spec:"]),
        ]

        for (lang, patterns) in detectors {
            for pattern in patterns {
                if joined.contains(pattern) {
                    return lang
                }
            }
        }
        return nil
    }
}

// MARK: - AttributedString Helpers

private extension AttributedString {
    func dimmed() -> AttributedString {
        var copy = self
        copy.foregroundColor = .textSecondary
        return copy
    }
}
