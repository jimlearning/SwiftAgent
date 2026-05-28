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

    // MARK: - Context-sensitive keyword categories

    /// Keywords that signal a function/method declaration follows (e.g. "func", "def", "fn").
    /// Must be a subset of `keywords`.
    let declarationKeywords: Set<String>
    /// Keywords that signal a variable/constant declaration follows (e.g. "let", "var", "const").
    /// Must be a subset of `keywords`.
    let variableKeywords: Set<String>
    /// Keywords that signal a type name follows (e.g. "class", "struct", "enum").
    /// Must be a subset of `keywords`.
    let typeDeclarationKeywords: Set<String>
    /// Whether the language uses PascalCase/camelCase naming where capitalization distinguishes types from variables.
    let usesCapitalizedTypes: Bool
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["func"],
            variableKeywords: ["let", "var"],
            typeDeclarationKeywords: ["class", "struct", "enum", "protocol", "extension"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["def"],
            variableKeywords: [],
            typeDeclarationKeywords: ["class"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["function"],
            variableKeywords: ["const", "let", "var"],
            typeDeclarationKeywords: ["class", "extends"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["function"],
            variableKeywords: ["const", "let", "var"],
            typeDeclarationKeywords: ["class", "extends", "implements", "interface", "type", "enum", "namespace"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\b"#,
            declarationKeywords: ["function"],
            variableKeywords: ["local", "export", "readonly", "declare"],
            typeDeclarationKeywords: [],
            usesCapitalizedTypes: false
        ),
        "json": LanguageGrammar(
            name: "json",
            keywords: ["true", "false", "null"],
            lineComment: nil,
            blockComment: nil,
            stringDelimiters: ["\""],
            numberPattern: #"-?\d+\.?\d*(?:[eE][+-]?\d+)?"#,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: [],
            usesCapitalizedTypes: false
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["func"],
            variableKeywords: ["var", "const"],
            typeDeclarationKeywords: ["type", "struct", "interface"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?(?:[ui](?:8|16|32|64|size|128))?\b"#,
            declarationKeywords: ["fn"],
            variableKeywords: ["let", "const"],
            typeDeclarationKeywords: ["struct", "enum", "trait", "impl", "type"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b0x[0-9a-fA-F]+\b|\b\d+\.?\d*(?:[eE][+-]?\d+)?[fFlL]?\b"#,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: ["struct", "enum", "union", "typedef"],
            usesCapitalizedTypes: false
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
            numberPattern: #"\b0x[0-9a-fA-F]+\b|\b\d+\.?\d*(?:[eE][+-]?\d+)?[fFlL]?\b"#,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: ["class", "struct", "enum", "namespace", "template", "typename"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: ["def"],
            variableKeywords: [],
            typeDeclarationKeywords: ["class", "module"],
            usesCapitalizedTypes: true
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
            numberPattern: #"\b\d+\.?\d*\b"#,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: [],
            usesCapitalizedTypes: false
        ),
        "yaml": LanguageGrammar(
            name: "yaml",
            keywords: ["true", "false", "null", "yes", "no", "on", "off"],
            lineComment: "#",
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            numberPattern: #"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: [],
            usesCapitalizedTypes: false
        ),
        "markdown": LanguageGrammar(
            name: "markdown",
            keywords: [],
            lineComment: nil,
            blockComment: nil,
            stringDelimiters: [],
            numberPattern: nil,
            declarationKeywords: [],
            variableKeywords: [],
            typeDeclarationKeywords: [],
            usesCapitalizedTypes: false
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
