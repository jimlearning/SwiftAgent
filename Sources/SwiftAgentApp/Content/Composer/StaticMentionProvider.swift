import Foundation

// MARK: - Static Mention Provider

/// A concrete `MentionProvider` that serves items from in-memory data sources.
///
/// Used by the composer to provide @-mentionable files, skills, MCP tools, and threads.
/// Items are resolved from the current app state at provider initialization time.
public struct StaticMentionProvider: MentionProvider {
    public let supportedKinds: [MentionKind] = [.file, .skill, .mcp, .thread]

    private let files: [MentionItem]
    private let skills: [MentionItem]
    private let mcpTools: [MentionItem]
    private let threads: [MentionItem]

    public init(
        filePaths: [String] = [],
        skillNames: [String] = [],
        mcpToolNames: [String] = [],
        threadTitles: [(id: String, title: String)] = []
    ) {
        self.files = filePaths.map { path in
            let name = (path as NSString).lastPathComponent
            let dir = (path as NSString).deletingLastPathComponent
            return MentionItem(
                id: "file:\(path)",
                mentionText: "@\(name)",
                displayName: name,
                detail: dir,
                kind: .file
            )
        }

        self.skills = skillNames.map { name in
            MentionItem(
                id: "skill:\(name)",
                mentionText: "@\(name)",
                displayName: name,
                detail: "Skill",
                kind: .skill
            )
        }

        self.mcpTools = mcpToolNames.map { name in
            MentionItem(
                id: "mcp:\(name)",
                mentionText: "@\(name)",
                displayName: name,
                detail: "MCP Tool",
                kind: .mcp
            )
        }

        self.threads = threadTitles.map { thread in
            MentionItem(
                id: "thread:\(thread.id)",
                mentionText: "@\(thread.title)",
                displayName: thread.title,
                detail: "Thread",
                kind: .thread
            )
        }
    }

    public func fetchItems() async -> [MentionItem] {
        // All items are pre-computed — just return them
        files + skills + mcpTools + threads
    }
}
