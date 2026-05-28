import Foundation

/// Tool that lists all available skills, including project-level, user-level, and bundled.
/// Complements the `/skills` slash command — this tool allows the LLM to dynamically
/// discover available skills at runtime.
public struct ListSkillsTool: Tool {
    public let name = "ListSkills"
    public var searchHint: String? { "list all available skills" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "List all available skills with names, descriptions, and source locations."
    }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["includeDetail"] = JSONSchemaProperty(
            type: "boolean",
            description: "Whether to include full detail (aliases, model, allowed_tools). Default: false."
        )
        return schema
    }()

    public init() {}

    public func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn? = nil,
        parentMessage: Message? = nil,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
        let includeDetail: Bool
        if let detailValue = input["includeDetail"], case .bool(let includeDetailValue) = detailValue {
            includeDetail = includeDetailValue
        } else {
            includeDetail = false
        }

        let manifests = SkillFileLoader.loadAllManifests(workingDirectory: context.workingDirectory)

        guard !manifests.isEmpty else {
            return ToolResult(content: "No skills available.")
        }

        var output: [String] = ["Available Skills (\(manifests.count)):", ""]

        for (index, manifest) in manifests.enumerated() {
            let sourceLabel = sourceLabel(for: manifest)
            var line = "\(index + 1). /\(manifest.name) — \(manifest.description) [\(sourceLabel)]"

            if includeDetail {
                if let aliases = manifest.aliases, !aliases.isEmpty {
                    line += "\n     Aliases: \(aliases.joined(separator: ", "))"
                }
                if let allowedTools = manifest.allowedTools, !allowedTools.isEmpty {
                    line += "\n     Allowed tools: \(allowedTools.joined(separator: ", "))"
                }
                if let model = manifest.model {
                    line += "\n     Model: \(model)"
                }
                if let whenToUse = manifest.whenToUse {
                    line += "\n     When to use: \(whenToUse)"
                }
            }

            output.append(line)
            output.append("")
        }

        return ToolResult(content: output.joined(separator: "\n"))
    }

    /// Determine the source label for a skill manifest.
    /// - "project" — loaded from .claude/skills/ in the current project
    /// - "user" — loaded from ~/.claude/skills/
    /// - "bundled" — built-in skills
    private func sourceLabel(for manifest: SkillManifest) -> String {
        if manifest.sourcePath.hasPrefix("bundled://") {
            return "bundled"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userSkillsPrefix = "\(home)/.claude/skills/"
        if manifest.sourcePath.hasPrefix(userSkillsPrefix) {
            return "user"
        }
        return "project"
    }
}
