import Foundation

// MARK: - Skill Manifest

/// Parsed skill metadata from YAML frontmatter.
/// Matches Claude Code's skill manifest fields.
public struct SkillManifest: Sendable {
    public let name: String
    public let description: String
    public let aliases: [String]?
    public let whenToUse: String?
    public let allowedTools: [String]?
    public let model: String?
    public let effort: EffortValue?
    public let context: CommandExecutionContext?
    public let agent: String?
    public let paths: [String]?
    public let argumentHint: String?
    public let disableModelInvocation: Bool
    public let userInvocable: Bool?
    public let hooks: HookConfig?
    public let version: String?
    public let author: String?

    /// The raw markdown body (after frontmatter) — injected as the skill prompt.
    public let markdownBody: String

    /// The file path this manifest was loaded from.
    public let sourcePath: String

    public init(
        name: String,
        description: String,
        aliases: [String]? = nil,
        whenToUse: String? = nil,
        allowedTools: [String]? = nil,
        model: String? = nil,
        effort: EffortValue? = nil,
        context: CommandExecutionContext? = nil,
        agent: String? = nil,
        paths: [String]? = nil,
        argumentHint: String? = nil,
        disableModelInvocation: Bool = false,
        userInvocable: Bool? = nil,
        hooks: HookConfig? = nil,
        version: String? = nil,
        author: String? = nil,
        markdownBody: String,
        sourcePath: String
    ) {
        self.name = name
        self.description = description
        self.aliases = aliases
        self.whenToUse = whenToUse
        self.allowedTools = allowedTools
        self.model = model
        self.effort = effort
        self.context = context
        self.agent = agent
        self.paths = paths
        self.argumentHint = argumentHint
        self.disableModelInvocation = disableModelInvocation
        self.userInvocable = userInvocable
        self.hooks = hooks
        self.version = version
        self.author = author
        self.markdownBody = markdownBody
        self.sourcePath = sourcePath
    }
}

// MARK: - Skill YAML Parser

/// Parses YAML frontmatter from skill markdown files.
///
/// Skill files use the standard Jekyll/Hugo frontmatter format:
/// ```
/// ---
/// name: my-skill
/// description: My custom skill
/// allowed_tools: [Read, Bash]
/// ---
///
/// # Instructions for the model
/// ...
/// ```
///
/// No external YAML library dependency — uses a simple line-based parser
/// sufficient for the subset of YAML used in skill frontmatter.
public struct SkillYAMLParser {

    /// Parse a skill markdown file into a manifest and body.
    /// Returns nil if the file has no valid frontmatter or required fields.
    public static func parse(fileContent: String, sourcePath: String) -> SkillManifest? {
        let lines = fileContent.components(separatedBy: .newlines)

        // Must start with "---"
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        // Find closing "---"
        var frontmatterLines: [String] = []
        var bodyStartIndex = 0
        var foundEnd = false
        for (i, line) in lines.enumerated().dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                foundEnd = true
                bodyStartIndex = i + 1
                break
            }
            frontmatterLines.append(line)
        }

        guard foundEnd else { return nil }

        // Parse key-value pairs
        let fields = parseFields(frontmatterLines)

        // name and description are required
        guard let name = fields["name"] as? String,
              let description = fields["description"] as? String else {
            return nil
        }

        // Reconstruct markdown body (everything after closing ---)
        let bodySl = lines[bodyStartIndex...]
        let markdownBody = bodySl
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse optional typed fields
        let aliases = (fields["aliases"] as? [String]) ?? (fields["alias"] as? [String])
        let whenToUse = fields["when_to_use"] as? String
            ?? fields["whenToUse"] as? String
        let allowedTools = fields["allowed_tools"] as? [String]
            ?? fields["allowedTools"] as? [String]
        let model = fields["model"] as? String
        let effort = parseEffort(fields["effort"])
        let context = parseContext(fields["context"])
        let agent = fields["agent"] as? String
        let paths = fields["paths"] as? [String]
        let argumentHint = fields["argument_hint"] as? String
            ?? fields["argumentHint"] as? String
        let disableModelInvocation = (fields["disable_model_invocation"] as? Bool)
            ?? (fields["disableModelInvocation"] as? Bool) ?? false
        let userInvocable = fields["user_invocable"] as? Bool
            ?? fields["userInvocable"] as? Bool
        let version = fields["version"] as? String
        let author = fields["author"] as? String

        return SkillManifest(
            name: name,
            description: description,
            aliases: aliases,
            whenToUse: whenToUse,
            allowedTools: allowedTools,
            model: model,
            effort: effort,
            context: context,
            agent: agent,
            paths: paths,
            argumentHint: argumentHint,
            disableModelInvocation: disableModelInvocation,
            userInvocable: userInvocable,
            hooks: nil,
            version: version,
            author: author,
            markdownBody: markdownBody,
            sourcePath: sourcePath
        )
    }

    // MARK: - Field Parsing

    /// Parse raw key: value lines into a dictionary of mixed types.
    private static func parseFields(_ lines: [String]) -> [String: Any] {
        var fields: [String: Any] = [:]
        var currentKey: String? = nil
        var currentMultiLine: [String] = []

        func flushMultiLine() {
            guard let key = currentKey, !currentMultiLine.isEmpty else { return }
            fields[key] = currentMultiLine.joined(separator: "\n")
            currentKey = nil
            currentMultiLine = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if currentKey != nil {
                    flushMultiLine()
                }
                continue
            }

            // Check if continuing a multi-line value (indented)
            if line.first?.isWhitespace ?? false, currentKey != nil {
                currentMultiLine.append(trimmed)
                continue
            }

            // Flush previous multi-line before starting a new key
            if currentKey != nil {
                flushMultiLine()
            }

            // Parse "key: value"
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            if rawValue.isEmpty {
                // Possible multi-line string value
                currentKey = key
                currentMultiLine = []
            } else if rawValue == "|" || rawValue == ">" {
                // Literal/folded block scalar
                currentKey = key
                currentMultiLine = []
            } else {
                fields[key] = parseScalar(rawValue)
            }
        }

        flushMultiLine()
        return fields
    }

    /// Parse a scalar value, returning String, Bool, or [String].
    private static func parseScalar(_ value: String) -> Any {
        // Boolean
        if value.lowercased() == "true" { return true }
        if value.lowercased() == "false" { return false }

        // Array: [item1, item2, ...]
        if value.hasPrefix("[") && value.hasSuffix("]") {
            let inner = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return [String]() }
            let items = inner
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return items
        }

        // Quoted string: remove surrounding quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }

        return value
    }

    private static func parseEffort(_ value: Any?) -> EffortValue? {
        guard let raw = value else { return nil }
        if let str = raw as? String {
            if let level = EffortLevel(rawValue: str) {
                return .level(level)
            }
            if let num = Int(str) {
                return .number(num)
            }
        }
        if let num = raw as? Int {
            return .number(num)
        }
        return nil
    }

    private static func parseContext(_ value: Any?) -> CommandExecutionContext? {
        guard let str = value as? String else { return nil }
        switch str.lowercased() {
        case "inline": return .inline
        case "fork": return .fork
        default: return nil
        }
    }
}
