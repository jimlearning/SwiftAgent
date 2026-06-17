import SwiftUI

/// Maps syntax-highlighting capture names (from `RegexSyntaxHighlighter`) to
/// SwiftUI `Color` values. Uses the **classic Monokai palette** — the same
/// colors the CLI's `CodeTheme.monokai` renders via ANSI escape codes.
///
/// Capture name prefixes (same taxonomy as CLI's `CodeTheme`):
/// - `keyword` / `keyword.return` / `conditional` / `repeat` ...
/// - `string` / `string.special` / `character` ...
/// - `comment` / `documentation` ...
/// - `type` / `class` / `struct` / `enum` / `interface` / `storage` ...
/// - `function` / `function.call` / `function.declaration` / `method` / `constructor` ...
/// - `number` / `float` ...
/// - `constant` / `boolean` / `null` / `builtin` ...
/// - `variable` / `parameter` ...
/// - `property` / `field` / `member` / `attribute` ...
/// - `operator` / `symbol` ...
/// - `punctuation` / `delimiter` / `bracket` / `brace` ...
public enum CodeColors {
    /// Classic Monokai palette (matches CLI `CodeTheme.monokai`).
    public static func color(for captureName: String) -> Color? {
        switch captureName {
        case let c where c.hasPrefix("keyword") || c == "include" || c == "conditional"
                      || c == "repeat" || c == "exception" || c == "keyword.return":
            return .codeKeyword
        case let c where c.hasPrefix("string") || c.hasPrefix("character"):
            return .codeString
        case let c where c.hasPrefix("comment") || c == "documentation":
            return .codeComment
        case let c where c.hasPrefix("type") || c == "class" || c == "struct"
                      || c == "enum" || c == "interface" || c.hasPrefix("storage"):
            return .codeType
        case let c where c.hasPrefix("function") || c.hasPrefix("method")
                      || c == "constructor" || c == "call":
            return .codeFunction
        case let c where c.hasPrefix("number") || c.hasPrefix("float"):
            return .codeNumber
        case let c where c.hasPrefix("boolean") || c == "null" || c.hasPrefix("constant")
                      || c.hasPrefix("builtin") || c == "none" || c == "self" || c == "super":
            return .codeConstant
        case let c where c.hasPrefix("variable") || c.hasPrefix("parameter"):
            return .codeVariable
        case let c where c.hasPrefix("property") || c.hasPrefix("field")
                      || c.hasPrefix("member") || c.hasPrefix("attribute"):
            return .codeProperty
        case let c where c.hasPrefix("operator") || c == "symbol":
            return .codeOperator
        case let c where c.hasPrefix("punctuation") || c.hasPrefix("delimiter")
                      || c.hasPrefix("bracket") || c.hasPrefix("brace"):
            return .codePunctuation
        default:
            return nil
        }
    }
}

// MARK: - Syntax Colors (Classic Monokai)

public extension Color {
    /// Classic Monokai palette — same colors rendered by the CLI's ANSI
    /// `CodeTheme.monokai` (brightMagenta, brightYellow, brightCyan, etc.)
    /// when displayed in a standard terminal emulator.

    /// `#F92672` — Pink/red for keywords (`func`, `let`, `class`, `if`, `return`).
    static let codeKeyword     = Color(red: 0.976, green: 0.149, blue: 0.447)

    /// `#E6DB74` — Warm yellow for strings and character literals.
    static let codeString      = Color(red: 0.902, green: 0.859, blue: 0.455)

    /// `#75715E` — Muted brown-gray for comments.
    static let codeComment     = Color(red: 0.459, green: 0.443, blue: 0.369)

    /// `#66D9EF` — Bright cyan for type names, class/struct/enum declarations.
    static let codeType        = Color(red: 0.400, green: 0.851, blue: 0.937)

    /// `#A6E22E` — Bright green for function/method names.
    static let codeFunction    = Color(red: 0.651, green: 0.886, blue: 0.180)

    /// `#AE81FF` — Purple for numeric and constant literals.
    static let codeNumber      = Color(red: 0.682, green: 0.506, blue: 1.000)

    /// `#AE81FF` — Purple for booleans, `nil`/`null`, builtins.
    static let codeConstant    = Color(red: 0.682, green: 0.506, blue: 1.000)

    /// `#F8F8F2` — Near-white for variables and parameters.
    static let codeVariable    = Color(red: 0.973, green: 0.973, blue: 0.949)

    /// `#66D9EF` — Bright cyan for property/member access.
    static let codeProperty    = Color(red: 0.400, green: 0.851, blue: 0.937)

    /// `#F92672` — Pink/red for operators.
    static let codeOperator    = Color(red: 0.976, green: 0.149, blue: 0.447)

    /// `#F8F8F2` — Near-white for punctuation, delimiters, brackets.
    static let codePunctuation = Color(red: 0.973, green: 0.973, blue: 0.949)

    // MARK: - Code Backgrounds

    /// `#272822` — Classic Monokai background for fenced code blocks.
    static let codeBlockBG     = Color(red: 0.153, green: 0.157, blue: 0.133)

    /// `#3E3D32` — Slightly lighter background for inline code spans.
    static let codeInlineBG    = Color(red: 0.243, green: 0.239, blue: 0.196)
}
