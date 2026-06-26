import Foundation

/// Exits a worktree session created by EnterWorktree and restores the original working directory.
/// Matches Claude Code's ExitWorktreeTool.
public struct ExitWorktreeTool: Tool {
    public let name = "ExitWorktree"
    public let description = "Exits a worktree session created by EnterWorktree and restores the original working directory."

    private let workingDirectory: String

    public struct Arguments: Codable, Sendable {
        public var action: String
        public var discardChanges: Bool?

        enum CodingKeys: String, CodingKey {
            case action
            case discardChanges = "discard_changes"
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["action"] = JSONSchemaProperty(
            type: "string",
            description: "\"keep\" leaves the worktree and branch on disk; \"remove\" deletes both."
        )
        schema.properties?["discard_changes"] = JSONSchemaProperty(
            type: "boolean",
            description: "Required true when action is \"remove\" and the worktree has uncommitted files or unmerged commits."
        )
        schema.required = ["action"]
        return schema
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let markerPath = "\(workingDirectory)/.claude/worktrees/.active"

        guard FileManager.default.fileExists(atPath: markerPath) else {
            return .string("""
                No-op: there is no active EnterWorktree session to exit.

                This tool only operates on worktrees created by EnterWorktree in the current session — it will not touch worktrees created manually or in a previous session. No filesystem changes were made.
                """)
        }

        let action = arguments.action
        guard action == "keep" || action == "remove" else {
            return .string("Error: action must be \"keep\" or \"remove\".")
        }

        let discardChanges = arguments.discardChanges ?? false

        // Read marker to get original cwd and worktree path
        let markerContent: String
        do {
            markerContent = try String(contentsOfFile: markerPath, encoding: .utf8)
        } catch {
            return .string("Error: could not read worktree marker file.")
        }

        let lines = markerContent.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            return .string("Error: invalid worktree marker file.")
        }

        let worktreePath = lines[0]
        let branch = lines[1]
        let originalCwd = lines[2]

        if action == "remove" && !discardChanges {
            if FileManager.default.fileExists(atPath: worktreePath) {
                return .string("""
                    Worktree has changes that would be discarded. Confirm with the user, then re-invoke with discard_changes: true — or use action: \"keep\" to preserve the worktree.
                    """)
            }
        }

        if action == "remove" {
            try? FileManager.default.removeItem(atPath: worktreePath)
        }

        // Remove the marker
        try? FileManager.default.removeItem(atPath: markerPath)

        if action == "keep" {
            return .string("""
                Exited worktree. Your work is preserved at \(worktreePath) on branch \(branch). Session is now back in \(originalCwd).
                """)
        }

        return .string("""
            Exited and removed worktree at \(worktreePath). Session is now back in \(originalCwd).
            """)
    }
}
