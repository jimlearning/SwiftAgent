import Foundation

/// Tool that lists all available skills, including project-level, user-level, and bundled.
public struct ListSkillsTool: Tool {
    public let name = "ListSkills"
    public let description = "List all available skills with names, descriptions, and source locations."

    private let workingDirectory: String

    public struct Arguments: Codable, Sendable {
        public var includeDetail: Bool?

        enum CodingKeys: String, CodingKey {
            case includeDetail
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["includeDetail"] = JSONSchemaProperty(
            type: "boolean",
            description: "Whether to include full detail (aliases, model, allowed_tools). Default: false."
        )
        return schema
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let includeDetail = arguments.includeDetail ?? false
        let manifests = SkillFileLoader.loadAllManifests(workingDirectory: workingDirectory)

        guard !manifests.isEmpty else {
            return .string("No skills available.")
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

        return .string(output.joined(separator: "\n"))
    }

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
