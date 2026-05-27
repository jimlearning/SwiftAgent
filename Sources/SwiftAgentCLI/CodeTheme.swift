import SwiftAgentCore

/// Theme for syntax-highlighted code blocks.
/// Maps tree-sitter capture names (from highlights.scm queries) to ANSI colors.
public struct CodeTheme: Sendable {
    public let name: String

    // Core token type colors
    public let keyword: ANSIColor
    public let string: ANSIColor
    public let comment: ANSIColor
    public let type: ANSIColor
    public let function: ANSIColor
    public let number: ANSIColor
    public let constant: ANSIColor
    public let variable: ANSIColor
    public let property: ANSIColor
    public let punctuation: ANSIColor
    public let `operator`: ANSIColor

    /// Map a tree-sitter capture name (e.g. "keyword", "string.special") to an ANSI color.
    /// Returns nil for capture names that should use the default foreground color.
    public func color(for captureName: String) -> ANSIColor? {
        switch captureName {
        case let c where c.hasPrefix("keyword") || c == "include" || c == "conditional"
                      || c == "repeat" || c == "exception" || c == "keyword.return":
            return keyword
        case let c where c.hasPrefix("string") || c.hasPrefix("character"):
            return string
        case let c where c.hasPrefix("comment") || c == "documentation":
            return comment
        case let c where c.hasPrefix("type") || c == "class" || c == "struct"
                      || c == "enum" || c == "interface" || c.hasPrefix("storage"):
            return type
        case let c where c.hasPrefix("function") || c.hasPrefix("method")
                      || c == "constructor" || c == "call":
            return function
        case let c where c.hasPrefix("number") || c.hasPrefix("float"):
            return number
        case let c where c.hasPrefix("boolean") || c == "null" || c.hasPrefix("constant")
                      || c.hasPrefix("builtin") || c == "none" || c == "self" || c == "super":
            return constant
        case let c where c.hasPrefix("variable") || c.hasPrefix("parameter"):
            return variable
        case let c where c.hasPrefix("property") || c.hasPrefix("field")
                      || c.hasPrefix("member") || c.hasPrefix("attribute"):
            return property
        case let c where c.hasPrefix("operator") || c == "symbol":
            return `operator`
        case let c where c.hasPrefix("punctuation") || c.hasPrefix("delimiter")
                      || c.hasPrefix("bracket") || c.hasPrefix("brace"):
            return punctuation
        default:
            return nil
        }
    }

    // MARK: - Presets

    /// Monokai Extended (dark theme, matches claude-code).
    public static let monokai = CodeTheme(
        name: "monokai",
        keyword: .brightMagenta,
        string: .brightYellow,
        comment: .brightBlack,
        type: .brightCyan,
        function: .brightGreen,
        number: .brightMagenta,
        constant: .brightMagenta,
        variable: .white,
        property: .brightCyan,
        punctuation: .white,
        operator: .brightRed
    )

    /// GitHub light theme.
    public static let github = CodeTheme(
        name: "github",
        keyword: .red,
        string: .blue,
        comment: .brightBlack,
        type: .cyan,
        function: .magenta,
        number: .green,
        constant: .blue,
        variable: .black,
        property: .cyan,
        punctuation: .black,
        operator: .red
    )
}
