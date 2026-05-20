import Foundation

/// Creates an isolated git worktree and switches the session into it.
/// Matches Claude Code's EnterWorktreeTool.
public struct EnterWorktreeTool: Tool {
    public let name = "EnterWorktree"
    public var searchHint: String? { "create an isolated git worktree and switch into it" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Creates an isolated worktree (via git or configured hooks) and switches the session into it" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["name"] = JSONSchemaProperty(type: "string", description: "Optional name for the worktree. Each \"/\"-separated segment may contain only letters, digits, dots, underscores, and dashes; max 64 chars total. A random name is generated if not provided.")
        return schema
    }()

    private let worktreeStore: WorktreeStore

    public init(worktreeStore: WorktreeStore = WorktreeStore()) {
        self.worktreeStore = worktreeStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        if worktreeStore.currentSession != nil {
            return ToolResult(content: "Already in a worktree session", isError: true)
        }

        let slug: String
        if case .string(let name) = input["name"], !name.isEmpty {
            slug = sanitizeWorktreeSlug(name)
        } else {
            slug = "worktree-\(UUID().uuidString.prefix(8).lowercased())"
        }

        guard !slug.isEmpty, slug.count <= 64 else {
            return ToolResult(content: "Invalid worktree name: must be 1-64 characters, containing only letters, digits, dots, underscores, and dashes", isError: true)
        }

        let worktreePath = "\(context.workingDirectory)/.claude/worktrees/\(slug)"
        let branchName = "claude-worktree/\(slug)"

        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
        } catch {
            return ToolResult(content: "Failed to create worktree directory: \(error.localizedDescription)", isError: true)
        }

        let session = WorktreeSession(
            id: UUID().uuidString,
            originalCwd: context.workingDirectory,
            worktreePath: worktreePath,
            worktreeBranch: branchName,
            createdAt: Date()
        )
        worktreeStore.currentSession = session

        return ToolResult(content: """
            Created worktree at \(worktreePath) on branch \(branchName).

            The session is now working in the worktree. Use ExitWorktree to leave mid-session, or exit the session to be prompted.
            """)
    }

    private func sanitizeWorktreeSlug(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/"))
        let sanitized = raw.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        return String(sanitized.replacingOccurrences(of: "/", with: "-").prefix(64))
    }
}
