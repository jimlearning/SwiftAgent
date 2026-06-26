import Foundation

/// Lists bundled skills available to the LLM.
public struct BundledSkillsTool: Tool {
    public let name = "BundledSkills"
    public let description = "List all bundled skills with names, descriptions, and aliases."

    public struct Arguments: Codable, Sendable {}

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let skills = BundledSkills.all
        if skills.isEmpty {
            return .string("No bundled skills available.")
        }

        var output = "Bundled Skills (\(skills.count)):\n"
        for (i, skill) in skills.enumerated() {
            output += "\n\(i + 1). /\(skill.name) — \(skill.description)"
            if let aliases = skill.aliases, !aliases.isEmpty {
                output += "\n   Aliases: \(aliases.joined(separator: ", "))"
            }
        }
        return .string(output)
    }
}
