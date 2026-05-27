import Testing
import Foundation
@testable import SwiftAgentCore

@Suite("Syntax Highlighting")
struct SyntaxHighlightingTests {

    // MARK: - LanguageRegistry

    @Test("resolve returns grammar for known languages")
    func testResolveKnownLanguages() {
        let tests: [(String, String?)] = [
            ("swift", "swift"),
            ("python", "python"),
            ("javascript", "javascript"),
            ("typescript", "typescript"),
            ("bash", "bash"),
            ("json", "json"),
            ("go", "go"),
            ("rust", "rust"),
            ("ruby", "ruby"),
            ("sql", "sql"),
        ]
        for (input, expected) in tests {
            let grammar = LanguageRegistry.resolve(input)
            #expect(grammar != nil, "Should resolve \(input)")
            #expect(grammar?.name == expected, "\(input) -> \(expected ?? "nil"), got \(grammar?.name ?? "nil")")
        }
    }

    @Test("resolve handles aliases")
    func testResolveAliases() {
        let aliases: [(String, String)] = [
            ("js", "javascript"),
            ("ts", "typescript"),
            ("py", "python"),
            ("sh", "bash"),
            ("zsh", "bash"),
            ("shell", "bash"),
            ("rs", "rust"),
        ]
        for (alias, expected) in aliases {
            let grammar = LanguageRegistry.resolve(alias)
            #expect(grammar?.name == expected, "\(alias) -> \(expected), got \(grammar?.name ?? "nil")")
        }
    }

    @Test("resolve returns nil for unknown languages")
    func testResolveUnknown() {
        #expect(LanguageRegistry.resolve("brainfuck") == nil)
        #expect(LanguageRegistry.resolve("zig") == nil)
        #expect(LanguageRegistry.resolve("") == nil)
    }

    @Test("resolve handles CommonMark fence info strings")
    func testResolveCommonMarkFenceInfo() {
        // Split on comma, space, tab
        let tests: [(String, String?)] = [
            ("swift", "swift"),
            ("rust,no_run", "rust"),
            ("python title=hello", "python"),
            ("bash\ttitle=script", "bash"),
        ]
        for (input, expected) in tests {
            let grammar = LanguageRegistry.resolve(input)
            #expect(grammar?.name == expected, "\(input) -> \(expected ?? "nil")")
        }
    }

    // MARK: - RegexSyntaxHighlighter

    @Test("highlight swift keywords")
    func testHighlightSwiftKeywords() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "let x = 42"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let keywordTokens = tokens?.filter { $0.captureName == "keyword" } ?? []
        #expect(keywordTokens.count >= 1, "Should have at least one keyword token")
        #expect(keywordTokens.contains { $0.captureName == "keyword" })
    }

    @Test("highlight python keywords")
    func testHighlightPythonKeywords() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "def hello():\n    return None"
        let tokens = highlighter.highlight(source, language: "python")
        #expect(tokens != nil)

        let keywords = tokens?.filter { $0.captureName == "keyword" }.map { token in
            (source as NSString).substring(with: token.range)
        } ?? []
        #expect(keywords.contains("def"))
        #expect(keywords.contains("return"))
        #expect(keywords.contains("None"))
    }

    @Test("highlight string literals")
    func testHighlightStrings() {
        let highlighter = RegexSyntaxHighlighter()
        let source = #"let msg = "hello world""#
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let strings = tokens?.filter { $0.captureName == "string" } ?? []
        #expect(!strings.isEmpty, "Should have string tokens")
    }

    @Test("highlight comments")
    func testHighlightComments() {
        let highlighter = RegexSyntaxHighlighter()

        // Single-line comment
        let source1 = "let x = 1 // this is a comment"
        let tokens1 = highlighter.highlight(source1, language: "swift")
        let comments1 = tokens1?.filter { $0.captureName == "comment" } ?? []
        #expect(!comments1.isEmpty, "Should highlight // comments in Swift")

        // Python comment
        let source2 = "x = 1 # this is a comment"
        let tokens2 = highlighter.highlight(source2, language: "python")
        let comments2 = tokens2?.filter { $0.captureName == "comment" } ?? []
        #expect(!comments2.isEmpty, "Should highlight # comments in Python")
    }

    @Test("highlight numbers")
    func testHighlightNumbers() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "x = 42 + 3.14"
        let tokens = highlighter.highlight(source, language: "python")
        #expect(tokens != nil)

        let numbers = tokens?.filter { $0.captureName == "number" }.map { token in
            (source as NSString).substring(with: token.range)
        } ?? []
        let numberCount = numbers.count
        #expect(numberCount >= 1, "Should have at least one number token, got \(numberCount)")
    }

    @Test("highlight JSON")
    func testHighlightJSON() {
        let highlighter = RegexSyntaxHighlighter()
        let source = #"{"key": "value", "flag": true, "count": 42}"#
        let tokens = highlighter.highlight(source, language: "json")
        #expect(tokens != nil)

        let strings = tokens?.filter { $0.captureName == "string" } ?? []
        #expect(!strings.isEmpty, "Should have string tokens")
    }

    @Test("empty source returns nil")
    func testEmptySource() {
        let highlighter = RegexSyntaxHighlighter()
        #expect(highlighter.highlight("", language: "swift") == nil)
    }

    @Test("unsupported language returns nil")
    func testUnsupportedLanguage() {
        let highlighter = RegexSyntaxHighlighter()
        #expect(highlighter.highlight("code", language: "unknown-lang") == nil)
    }

    @Test("tokens are sorted by position")
    func testTokensSorted() {
        let highlighter = RegexSyntaxHighlighter()
        let tokens = highlighter.highlight("let x = \"hello\"", language: "swift")
        guard let t = tokens, t.count > 1 else { return }

        for i in 1..<t.count {
            #expect(t[i].range.location >= t[i-1].range.location, "Tokens should be sorted")
        }
    }
}
