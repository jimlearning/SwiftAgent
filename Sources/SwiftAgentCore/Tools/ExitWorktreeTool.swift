import Foundation

/// Exits a worktree session created by EnterWorktree and restores the original working directory.
/// Matches Claude Code's ExitWorktreeTool.
public struct ExitWorktreeTool: Tool {
    public let name = "ExitWorktree"
    public var searchHint: String? { "exit a worktree session and return to the original directory" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Exits a worktree session created by EnterWorktree and restores the original working directory" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["action"] = JSONSchemaProperty(type: "string", description: "\"keep\" leaves the worktree and branch on disk; \"remove\" deletes both.")
        schema.properties?["discardChanges"] = JSONSchemaProperty(type: "boolean", description: "Required true when action is \"remove\" and the worktree has uncommitted files or unmerged commits.")
        schema.required = ["action"]
        return schema
    }()

    private let worktreeStore: WorktreeStore

    public init(worktreeStore: WorktreeStore = WorktreeStore()) {
        self.worktreeStore = worktreeStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let session = worktreeStore.currentSession else {
            return ToolResult(content: """
                No-op: there is no active EnterWorktree session to exit.

                This tool only operates on worktrees created by EnterWorktree in the current session — it will not touch worktrees created manually or in a previous session. No filesystem changes were made.
                """)
        }

        guard case .string(let action) = input["action"],
              ["keep", "remove"].contains(action) else {
            return ToolResult(content: "Error: action must be \"keep\" or \"remove\"", isError: true)
        }

        let discardChanges: Bool
        if case .bool(let b) = input["discardChanges"] { discardChanges = b }
        else { discardChanges = false }

        if action == "remove" && !discardChanges {
            let fm = FileManager.default
            if fm.fileExists(atPath: session.worktreePath) {
                return ToolResult(content: """
                    Worktree has changes that would be discarded. Confirm with the user, then re-invoke with discardChanges: true — or use action: "keep" to preserve the worktree.
                    """, isError: true)
            }
        }

        let originalCwd = session.originalCwd
        let worktreePath = session.worktreePath
        let branch = session.worktreeBranch

        if action == "remove" {
            try? FileManager.default.removeItem(atPath: worktreePath)
        }

        worktreeStore.currentSession = nil

        if action == "keep" {
            return ToolResult(content: """
                Exited worktree. Your work is preserved at \(worktreePath) on branch \(branch). Session is now back in \(originalCwd).
                """)
        }

        return ToolResult(content: """
            Exited and removed worktree at \(worktreePath). Session is now back in \(originalCwd).
            """)
    }
}
