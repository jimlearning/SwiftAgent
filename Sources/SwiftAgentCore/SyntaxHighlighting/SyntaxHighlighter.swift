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

// MARK: - Scan Context

/// Tracks what the scanner just saw to categorize the next word token.
enum ScanContext: Equatable {
    case none
    /// Just saw func/def/fn — next word is a function/method declaration name
    case declaration
    /// Just saw let/var/const — next word is a variable name
    case variable
    /// Just saw class/struct/enum/etc — next word is a type name
    case typeDeclaration
    /// Just saw : or -> or as/new — next word is a type annotation
    case typeAnnotation
    /// Just saw . — next word is a property/member access
    case dot
}

// MARK: - Regex-Based Implementation

/// Zero-dependency syntax highlighter using Swift native regex.
/// Uses a context-aware single-pass scanner:
/// - Keywords, strings, comments, numbers: direct matching
/// - Word tokens: categorized via context state + capitalization + peek-ahead
public struct RegexSyntaxHighlighter: SyntaxHighlightingEngine, Sendable {

    public init() {}

    public func highlight(_ source: String, language rawLang: String) -> [HighlightToken]? {
        guard !source.isEmpty else { return nil }
        guard let grammar = LanguageRegistry.resolve(rawLang) else { return nil }

        var tokens: [HighlightToken] = []
        let nsSource = source as NSString
        let length = nsSource.length
        var pos = 0
        var context: ScanContext = .none

        while pos < length {
            let ch = nsSource.character(at: pos)

            // Track context-setting characters before attempting a match
            switch ch {
            case 46: // '.'
                context = .dot
                pos += 1
                continue
            case 58: // ':'
                context = .typeAnnotation
                pos += 1
                continue
            case 45: // '-'
                if pos + 1 < length, nsSource.character(at: pos + 1) == 62 { // '->'
                    context = .typeAnnotation
                    pos += 2
                    continue
                }
            default:
                break
            }

            guard let (name, range, newContext) = matchNext(
                in: nsSource, from: pos, length: length,
                grammar: grammar, context: context
            ) else {
                if !isWhitespace(ch) {
                    context = .none
                }
                pos += 1
                continue
            }
            tokens.append(HighlightToken(range: range, captureName: name))
            pos = range.location + range.length
            context = newContext
        }

        return tokens.isEmpty ? nil : tokens
    }

    private func matchNext(
        in ns: NSString,
        from pos: Int,
        length: Int,
        grammar: LanguageGrammar,
        context: ScanContext
    ) -> (String, NSRange, ScanContext)? {

        let rest = ns.substring(from: pos)

        // Block comment — check first since it's multi-character
        if let (open, close) = grammar.blockComment, rest.hasPrefix(open) {
            let searchRange = NSRange(location: pos + open.count, length: length - pos - open.count)
            let end = ns.range(of: close, range: searchRange)
            let commentEnd = end.location != NSNotFound ? end.location + close.count : length
            return ("comment", NSRange(location: pos, length: commentEnd - pos), context)
        }

        // Line comment
        if let lc = grammar.lineComment, rest.hasPrefix(lc) {
            let end = ns.range(of: "\n", range: NSRange(location: pos, length: length - pos))
            let commentEnd = end.location != NSNotFound ? end.location : length
            return ("comment", NSRange(location: pos, length: commentEnd - pos), context)
        }

        // String
        if !grammar.stringDelimiters.isEmpty {
            let ch = ns.character(at: pos)
            let char = Character(UnicodeScalar(ch) ?? " ")
            if grammar.stringDelimiters.contains(char) {
                let end = endOfString(in: ns, from: pos, delimiter: ch, length: length)
                return ("string", NSRange(location: pos, length: end - pos), context)
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
                    return ("number", range, context)
                }
            }
        }

        // Word token — keyword or context-dependent identifier
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
                let wordRange = NSRange(location: pos, length: end - pos)
                let word = ns.substring(with: wordRange)

                // 1. Is it a keyword?
                if grammar.keywords.contains(word) {
                    return keywordCapture(word, range: wordRange, grammar: grammar)
                }

                // 2. Not a keyword — categorize via context + heuristics
                if let (name, newCtx) = categorizeWord(
                    word: word, range: wordRange,
                    ns: ns, wordEnd: end, length: length,
                    grammar: grammar, context: context
                ) {
                    return (name, wordRange, newCtx)
                }

                // 3. Plain identifier — no highlight
                return ("identifier", wordRange, .none)
            }
        }

        return nil
    }

    // MARK: - Keyword dispatch

    private func keywordCapture(_ word: String, range: NSRange, grammar: LanguageGrammar) -> (String, NSRange, ScanContext) {
        if grammar.declarationKeywords.contains(word) {
            return ("keyword", range, .declaration)
        }
        if grammar.variableKeywords.contains(word) {
            return ("keyword", range, .variable)
        }
        if grammar.typeDeclarationKeywords.contains(word) {
            return ("keyword", range, .typeDeclaration)
        }
        // Keywords that signal a type annotation follows
        if word == "as" || word == "new" {
            return ("keyword", range, .typeAnnotation)
        }
        return ("keyword", range, .none)
    }

    // MARK: - Word categorization

    private func categorizeWord(
        word: String,
        range: NSRange,
        ns: NSString,
        wordEnd: Int,
        length: Int,
        grammar: LanguageGrammar,
        context: ScanContext
    ) -> (String, ScanContext)? {

        // Context from previous token/character takes priority
        switch context {
        case .declaration:
            return ("function.declaration", .none)
        case .variable:
            return ("variable", .none)
        case .typeDeclaration, .typeAnnotation:
            return ("type", .none)
        case .dot:
            return ("property", .none)
        case .none:
            break
        }

        // No context — use heuristics
        let peekParen = peekNonWhitespace(ns, from: wordEnd, length: length)

        if peekParen == 40 { // '(' follows
            if grammar.usesCapitalizedTypes, let first = word.first, first.isUppercase {
                return ("type", .none)
            }
            return ("function.call", .none)
        }

        // Standalone capitalized word → type
        if grammar.usesCapitalizedTypes, let first = word.first, first.isUppercase {
            return ("type", .none)
        }

        return nil
    }

    // MARK: - Helpers

    /// Peek ahead past whitespace to find the next meaningful character.
    private func peekNonWhitespace(_ ns: NSString, from start: Int, length: Int) -> UniChar {
        var p = start
        while p < length {
            let c = ns.character(at: p)
            if c == 32 || c == 9 || c == 10 || c == 13 {
                p += 1
                continue
            }
            return c
        }
        return 0
    }

    private func isWhitespace(_ ch: UniChar) -> Bool {
        ch == 32 || ch == 9 || ch == 10 || ch == 13
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
