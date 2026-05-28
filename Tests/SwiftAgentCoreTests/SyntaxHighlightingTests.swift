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

    // MARK: - Basic token types

    @Test("highlight swift keywords")
    func testHighlightSwiftKeywords() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "let x = 42"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let keywordTokens = tokens?.filter { $0.captureName == "keyword" } ?? []
        #expect(keywordTokens.count >= 1, "Should have at least one keyword token")
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

    // MARK: - Context-aware token types

    @Test("highlight function declaration name in Swift")
    func testFunctionDeclarationSwift() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "func greet() { }"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let decls = tokens!.filter { $0.captureName == "function.declaration" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(decls.contains("greet"), "Expected 'greet' to be function.declaration, got \(decls)")
    }

    @Test("highlight function declaration name in Python")
    func testFunctionDeclarationPython() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "def hello():\n    pass"
        let tokens = highlighter.highlight(source, language: "python")
        #expect(tokens != nil)

        let decls = tokens!.filter { $0.captureName == "function.declaration" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(decls.contains("hello"))
    }

    @Test("highlight function declaration name in Rust")
    func testFunctionDeclarationRust() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "fn main() { }"
        let tokens = highlighter.highlight(source, language: "rust")
        #expect(tokens != nil)

        let decls = tokens!.filter { $0.captureName == "function.declaration" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(decls.contains("main"))
    }

    @Test("highlight function call")
    func testFunctionCall() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "greet(world)"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let calls = tokens!.filter { $0.captureName == "function.call" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(calls.contains("greet"), "Expected 'greet' to be function.call, got \(calls)")
    }

    @Test("highlight type initializer call")
    func testTypeInitializerCall() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "let u = User(name: \"jim\")"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let types = tokens!.filter { $0.captureName == "type" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(types.contains("User"), "Expected 'User' to be type (constructor call), got \(types)")
    }

    @Test("highlight variable declaration")
    func testVariableDeclaration() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "let name = 42"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let variables = tokens!.filter { $0.captureName == "variable" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(variables.contains("name"), "Expected 'name' to be variable, got \(variables)")
    }

    @Test("highlight property access")
    func testPropertyAccess() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "user.name"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let props = tokens!.filter { $0.captureName == "property" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(props.contains("name"), "Expected 'name' to be property, got \(props)")
    }

    @Test("highlight type annotation after colon")
    func testTypeAnnotationColon() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "var age: Int"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let types = tokens!.filter { $0.captureName == "type" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(types.contains("Int"), "Expected 'Int' to be type annotation, got \(types)")
    }

    @Test("highlight class declaration name")
    func testClassDeclaration() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "class Person { }"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let types = tokens!.filter { $0.captureName == "type" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(types.contains("Person"), "Expected 'Person' to be type, got \(types)")
    }

    @Test("highlight 'as' type cast context")
    func testAsTypeCast() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "x as String"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let types = tokens!.filter { $0.captureName == "type" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(types.contains("String"), "Expected 'String' after 'as' to be type, got \(types)")
    }

    @Test("highlight chained property access")
    func testChainedPropertyAccess() {
        let highlighter = RegexSyntaxHighlighter()
        let source = "foo.bar.baz"
        let tokens = highlighter.highlight(source, language: "swift")
        #expect(tokens != nil)

        let props = tokens!.filter { $0.captureName == "property" }.map {
            (source as NSString).substring(with: $0.range)
        }
        #expect(props.contains("bar"))
        #expect(props.contains("baz"))
    }

    // MARK: - Edge cases

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
