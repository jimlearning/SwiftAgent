import Foundation

/// Creates an isolated git worktree and switches the session into it.
/// Matches Claude Code's EnterWorktreeTool.
public struct EnterWorktreeTool: Tool {
    public let name = "EnterWorktree"
    public let description = "Creates an isolated worktree (via git or configured hooks) and switches the session into it."

    private let workingDirectory: String

    public struct Arguments: Codable, Sendable {
        public var name: String?

        enum CodingKeys: String, CodingKey {
            case name
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["name"] = JSONSchemaProperty(
            type: "string",
            description: "Optional name for the worktree. Each \"/\"-separated segment may contain only letters, digits, dots, underscores, and dashes; max 64 chars total. A random name is generated if not provided."
        )
        return schema
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        // Check for existing session (tracked via a marker file akin to WorktreeStore.currentSession)
        let markerPath = "\(workingDirectory)/.claude/worktrees/.active"
        if FileManager.default.fileExists(atPath: markerPath) {
            return .string("Already in a worktree session.")
        }

        let slug: String
        if let name = arguments.name, !name.isEmpty {
            slug = sanitizeWorktreeSlug(name)
        } else {
            slug = "worktree-\(UUID().uuidString.prefix(8).lowercased())"
        }

        guard !slug.isEmpty, slug.count <= 64 else {
            return .string("Invalid worktree name: must be 1-64 characters, containing only letters, digits, dots, underscores, and dashes.")
        }

        let worktreePath = "\(workingDirectory)/.claude/worktrees/\(slug)"
        let branchName = "claude-worktree/\(slug)"

        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
            // Write active marker
            let markerDir = (worktreePath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: markerDir, withIntermediateDirectories: true)
            let payload = "\(worktreePath)\n\(branchName)\n\(workingDirectory)"
            try payload.write(toFile: markerPath, atomically: true, encoding: .utf8)
        } catch {
            return .string("Failed to create worktree directory: \(error.localizedDescription)")
        }

        return .string("""
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
