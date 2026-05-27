/// Language grammar definition for regex-based syntax highlighting.
struct LanguageGrammar: Sendable {
    /// Canonical language name.
    let name: String
    /// Keywords — highlighted with keyword color.
    let keywords: Set<String>
    /// Single-line comment prefix (e.g., "//", "#", "--").
    let lineComment: String?
    /// Multi-line comment delimiters (start, end). e.g., ("/*", "*/").
    let blockComment: (String, String)?
    /// String delimiter characters (e.g., "\"", "'", "`").
    let stringDelimiters: Set<Character>
    /// Regex pattern for number literals.
    let numberPattern: String?
}

/// Maps user-facing language names to grammar definitions.
/// Uses pure-Swift regex patterns — no external dependencies.
struct LanguageRegistry: Sendable {

    private static let aliases: [String: String] = [
        "js": "javascript",
        "ts": "typescript",
        "py": "python",
        "rb": "ruby",
        "rs": "rust",
        "sh": "bash",
        "zsh": "bash",
        "shell": "bash",
        "yml": "yaml",
        "c++": "cpp",
        "csharp": "csharp",
        "objc": "objective-c",
        "tsx": "typescript",
        "jsx": "javascript",
        "plaintext": "text",
    ]

    private static let grammars: [String: LanguageGrammar] = [
        "swift": LanguageGrammar(
            name: "swift",
            keywords: ["let", "var", "func", "class", "struct", "enum", "protocol", "extension",
                       "import", "return", "if", "else", "for", "in", "while", "switch", "case",
                       "default", "break", "continue", "guard", "defer", "do", "catch", "try",
                       "throw", "throws", "async", "await", "public", "private", "internal",
                       "fileprivate", "open", "static", "mutating", "nonmutating", "override",
                       "convenience", "required", "optional", "weak", "unowned", "lazy", "init",
                       "deinit", "subscript", "associatedtype", "typealias", "where", "self",
                       "Self", "super", "nil", "true", "false", "is", "as", "rethrows", "some",
                       "any", "final", "dynamic", "indirect", "infix", "prefix", "postfix"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "\""],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "python": LanguageGrammar(
            name: "python",
            keywords: ["def", "class", "import", "from", "return", "if", "elif", "else",
                       "for", "in", "while", "break", "continue", "pass", "raise", "try",
                       "except", "finally", "with", "as", "lambda", "yield", "async", "await",
                       "and", "or", "not", "is", "None", "True", "False", "global", "nonlocal",
                       "del", "assert"],
            lineComment: "#",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "javascript": LanguageGrammar(
            name: "javascript",
            keywords: ["const", "let", "var", "function", "class", "extends", "import",
                       "export", "default", "return", "if", "else", "for", "in", "of",
                       "while", "do", "switch", "case", "break", "continue", "try", "catch",
                       "finally", "throw", "new", "this", "super", "async", "await", "yield",
                       "typeof", "instanceof", "void", "delete", "null", "undefined", "true", "false"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'", "`"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "typescript": LanguageGrammar(
            name: "typescript",
            keywords: ["const", "let", "var", "function", "class", "extends", "implements",
                       "import", "export", "default", "return", "if", "else", "for", "in", "of",
                       "while", "do", "switch", "case", "break", "continue", "try", "catch",
                       "finally", "throw", "new", "this", "super", "async", "await", "yield",
                       "typeof", "instanceof", "void", "delete", "null", "undefined", "true", "false",
                       "type", "interface", "enum", "namespace", "declare", "abstract", "as",
                       "readonly", "keyof", "infer", "never", "unknown", "any", "string", "number",
                       "boolean", "symbol"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'", "`"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "bash": LanguageGrammar(
            name: "bash",
            keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done",
                       "while", "until", "case", "esac", "function", "return", "exit",
                       "export", "local", "readonly", "unset", "declare", "source",
                       "echo", "printf", "cd", "test", "exec", "trap", "set", "shift",
                       "break", "continue", "alias"],
            lineComment: "#",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\b"#
        ),
        "json": LanguageGrammar(
            name: "json",
            keywords: ["true", "false", "null"],
            lineComment: nil,
            blockComment: nil,
            stringDelimiters: ["\""],
            numberPattern: #"-?\d+\.?\d*(?:[eE][+-]?\d+)?"#
        ),
        "go": LanguageGrammar(
            name: "go",
            keywords: ["break", "case", "chan", "const", "continue", "default", "defer",
                       "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
                       "interface", "map", "package", "range", "return", "select", "struct",
                       "switch", "type", "var", "nil", "true", "false"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'", "`"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "rust": LanguageGrammar(
            name: "rust",
            keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn",
                       "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
                       "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
                       "self", "Self", "static", "struct", "super", "trait", "true", "type",
                       "unsafe", "use", "where", "while", "yield"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?(?:[ui](?:8|16|32|64|size|128))?\b"#
        ),
        "c": LanguageGrammar(
            name: "c",
            keywords: ["auto", "break", "case", "const", "continue", "default", "do", "else",
                       "enum", "extern", "for", "goto", "if", "register", "return", "signed",
                       "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
                       "void", "volatile", "while", "NULL", "true", "false", "int", "char",
                       "float", "double", "long", "short"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b0x[0-9a-fA-F]+\b|\b\d+\.?\d*(?:[eE][+-]?\d+)?[fFlL]?\b"#
        ),
        "cpp": LanguageGrammar(
            name: "cpp",
            keywords: ["alignas", "alignof", "auto", "bool", "break", "case", "catch", "char",
                       "class", "const", "constexpr", "continue", "decltype", "default", "delete",
                       "do", "double", "else", "enum", "explicit", "export", "extern", "false",
                       "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable",
                       "namespace", "new", "noexcept", "nullptr", "operator", "override", "private",
                       "protected", "public", "register", "return", "short", "signed", "sizeof",
                       "static", "struct", "switch", "template", "this", "throw", "true", "try",
                       "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual",
                       "void", "volatile", "while"],
            lineComment: "//",
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b0x[0-9a-fA-F]+\b|\b\d+\.?\d*(?:[eE][+-]?\d+)?[fFlL]?\b"#
        ),
        "ruby": LanguageGrammar(
            name: "ruby",
            keywords: ["begin", "break", "case", "class", "def", "do", "else", "elsif",
                       "end", "ensure", "false", "for", "if", "in", "module", "next",
                       "nil", "raise", "rescue", "return", "self", "super", "then",
                       "true", "unless", "until", "when", "while", "yield"],
            lineComment: "#",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "sql": LanguageGrammar(
            name: "sql",
            keywords: ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                       "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX",
                       "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "GROUP", "BY",
                       "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "AS",
                       "AND", "OR", "NOT", "NULL", "TRUE", "FALSE", "PRIMARY", "KEY",
                       "FOREIGN", "REFERENCES", "CASCADE", "DISTINCT", "COUNT", "SUM",
                       "AVG", "MAX", "MIN", "BETWEEN", "LIKE", "IN", "EXISTS", "CASE",
                       "WHEN", "THEN", "ELSE", "END", "IS", "NULL", "ASC", "DESC",
                       "select", "from", "where", "insert", "into", "values", "update",
                       "set", "delete", "create", "table", "alter", "drop", "index",
                       "join", "left", "right", "inner", "outer", "on", "group", "by",
                       "order", "having", "limit", "offset", "union", "all", "as",
                       "and", "or", "not", "null", "true", "false", "primary", "key",
                       "foreign", "references", "cascade", "distinct", "count", "sum",
                       "avg", "max", "min", "between", "like", "in", "exists"],
            lineComment: "--",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "yaml": LanguageGrammar(
            name: "yaml",
            keywords: ["true", "false", "null", "yes", "no", "on", "off"],
            lineComment: "#",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        ),
        "markdown": LanguageGrammar(
            name: "markdown",
            keywords: [],
            lineComment: nil,
            blockComment: nil,
            stringDelimiters: [],
            numberPattern: nil
        ),
    ]

    /// Resolve a user-provided language string (e.g., from a markdown fence) to a LanguageGrammar.
    static func resolve(_ raw: String) -> LanguageGrammar? {
        let firstToken = raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .first
            .map(String.init) ?? raw

        let lower = firstToken.trimmingCharacters(in: .whitespaces).lowercased()
        let canonical = aliases[lower] ?? lower

        return grammars[canonical]
    }

    static func isSupported(_ raw: String) -> Bool {
        resolve(raw) != nil
    }
}
