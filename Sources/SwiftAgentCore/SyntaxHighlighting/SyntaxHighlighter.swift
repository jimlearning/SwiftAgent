import Foundation

// MARK: - Highlight Token

/// A single highlighted token from syntax parsing.
public struct HighlightToken: Sendable, Equatable {
    /// UTF-16 code unit offset from the start of the source string.
    public let range: NSRange
    /// Token capture name (e.g., "keyword", "string", "comment", "number").
    public let captureName: String

    public init(range: NSRange, captureName: String) {
        self.range = range
        self.captureName = captureName
    }
}

// MARK: - Protocol

/// Protocol for syntax highlighting engines.
public protocol SyntaxHighlightingEngine: Sendable {
    func highlight(_ source: String, language: String) -> [HighlightToken]?
}

// MARK: - Regex-Based Implementation

/// Zero-dependency syntax highlighter using Swift native regex.
/// Tokenizes line-by-line for efficiency.
public struct RegexSyntaxHighlighter: SyntaxHighlightingEngine, Sendable {

    public init() {}

    public func highlight(_ source: String, language rawLang: String) -> [HighlightToken]? {
        guard !source.isEmpty else { return nil }
        guard let grammar = LanguageRegistry.resolve(rawLang) else { return nil }

        var tokens: [HighlightToken] = []
        let nsSource = source as NSString
        let length = nsSource.length
        var pos = 0

        while pos < length {
            guard let (name, range) = matchNext(in: nsSource, from: pos, length: length, grammar: grammar) else {
                pos += 1
                continue
            }
            tokens.append(HighlightToken(range: range, captureName: name))
            pos = range.location + range.length
        }

        return tokens.isEmpty ? nil : tokens
    }

    private func matchNext(
        in ns: NSString,
        from pos: Int,
        length: Int,
        grammar: LanguageGrammar
    ) -> (String, NSRange)? {

        let rest = ns.substring(from: pos)

        // Block comment — check first since it's multi-character
        if let (open, close) = grammar.blockComment, rest.hasPrefix(open) {
            let searchRange = NSRange(location: pos + open.count, length: length - pos - open.count)
            let end = ns.range(of: close, range: searchRange)
            let commentEnd = end.location != NSNotFound ? end.location + close.count : length
            return ("comment", NSRange(location: pos, length: commentEnd - pos))
        }

        // Line comment
        if let lc = grammar.lineComment, rest.hasPrefix(lc) {
            let end = ns.range(of: "\n", range: NSRange(location: pos, length: length - pos))
            let commentEnd = end.location != NSNotFound ? end.location : length
            return ("comment", NSRange(location: pos, length: commentEnd - pos))
        }

        // String
        if !grammar.stringDelimiters.isEmpty {
            let ch = ns.character(at: pos)
            let char = Character(UnicodeScalar(ch) ?? " ")
            if grammar.stringDelimiters.contains(char) {
                let end = endOfString(in: ns, from: pos, delimiter: ch, length: length)
                return ("string", NSRange(location: pos, length: end - pos))
            }
        }

        // Number (only if starts with digit)
        if let numPattern = grammar.numberPattern {
            let ch = ns.character(at: pos)
            if (48...57).contains(ch) || ch == 46 { // digit or dot
                let substr = ns.substring(from: pos)
                if let regex = try? NSRegularExpression(pattern: "^" + numPattern, options: []),
                   let match = regex.firstMatch(in: substr, range: NSRange(location: 0, length: substr.utf16.count)) {
                    let range = NSRange(location: pos, length: match.range.length)
                    return ("number", range)
                }
            }
        }

        // Keyword / word token
        if !grammar.keywords.isEmpty {
            let ch = ns.character(at: pos)
            let char = Character(UnicodeScalar(ch) ?? " ")
            if char.isLetter || char == "_" {
                // Extract the full word
                var end = pos
                while end < length {
                    let c = ns.character(at: end)
                    let sc = UnicodeScalar(c).map(Character.init) ?? " "
                    if sc.isLetter || sc.isNumber || sc == "_" {
                        end += 1
                    } else {
                        break
                    }
                }
                let word = ns.substring(with: NSRange(location: pos, length: end - pos))
                if grammar.keywords.contains(word) {
                    return ("keyword", NSRange(location: pos, length: end - pos))
                }
            }
        }

        return nil
    }

    /// Find the end of a string literal, handling backslash escapes.
    private func endOfString(in ns: NSString, from start: Int, delimiter: UniChar, length: Int) -> Int {
        var pos = start + 1
        while pos < length {
            let ch = ns.character(at: pos)
            if ch == 92 { // backslash
                pos += 2 // skip escaped character
                continue
            }
            if ch == delimiter {
                return pos + 1
            }
            if ch == 10 { // newline — string not closed
                return pos
            }
            pos += 1
        }
        return length
    }
}

// Legacy alias for existing code
public typealias TreeSitterSyntaxHighlighter = RegexSyntaxHighlighter
