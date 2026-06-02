import Foundation
import SwiftAgentCore

extension ChatCommand {
    // MARK: - System prompt

    /// Built once per session. Rebuilding on every API call would break prompt caching.
    func buildSystemPrompt(model: String? = nil, toolNames: Set<String> = []) -> String {
        let loader = ClaudeMdLoader()
        let builder = SystemPromptBuilder(claudeMdLoader: loader)
        return builder.build(for: Conversation(), toolNames: toolNames, model: model)
    }

    /// Build MCP server instructions as a `<system-reminder>` block.
    /// Matches Claude Code's `wrapMessagesInSystemReminder` format from
    /// `utils/messages.ts:4216-4231` — injected as conversation content,
    /// not appended to the system prompt.
    func buildMcpSystemReminder(instructions: [String: String]) -> String? {
        guard !instructions.isEmpty else { return nil }
        var lines: [String] = [
            "<system-reminder>",
            "",
            "# MCP Server Instructions",
            "",
            "The following MCP servers have provided instructions for how to use their tools and resources:",
        ]
        for (serverName, serverInstructions) in instructions.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            lines.append("## \(serverName)")
            lines.append(serverInstructions)
        }
        lines.append("")
        lines.append("</system-reminder>")
        return lines.joined(separator: "\n")
    }

    /// Build deferred tools announcement as a `<system-reminder>` block.
    /// Groups MCP tools by server and provides ready-to-use `select:` queries
    /// so the model can load all tools from a server in one call.
    /// Matches Claude Code's deferred tools delta injection.
    func buildDeferredToolsReminder(deferredNames: [String]) -> String? {
        guard !deferredNames.isEmpty else { return nil }

        let mcpPrefix = "mcp__"
        var mcpByServer: [String: [String]] = [:]
        var otherDeferred: [String] = []

        for name in deferredNames.sorted() {
            if name.hasPrefix(mcpPrefix) {
                let rest = String(name.dropFirst(mcpPrefix.count))
                let parts = rest.split(separator: "__", maxSplits: 1)
                if let server = parts.first {
                    mcpByServer[String(server), default: []].append(name)
                } else {
                    otherDeferred.append(name)
                }
            } else {
                otherDeferred.append(name)
            }
        }

        var lines: [String] = [
            "<system-reminder>",
            "The following deferred tools are available via ToolSearch. Their schemas are NOT loaded — calling them directly will fail. Use ToolSearch to load tool schemas before calling them.",
            "",
            "Load ALL tools from a server at once by copying the select: query below:",
            "",
        ]

        for (server, tools) in mcpByServer.sorted(by: { $0.key < $1.key }) {
            let sorted = tools.sorted {
                let aIsExplore = $0.hasSuffix("_explore") || $0.hasSuffix("_context")
                let bIsExplore = $1.hasSuffix("_explore") || $1.hasSuffix("_context")
                if aIsExplore != bIsExplore { return aIsExplore }
                return $0 < $1
            }
            let query = sorted.joined(separator: ",")
            lines.append("\(server): select:\(query)")
        }

        if !otherDeferred.isEmpty {
            lines.append("")
            lines.append("Other: select:\(otherDeferred.joined(separator: ","))")
        }

        lines.append("</system-reminder>")
        return lines.joined(separator: "\n")
    }

    /// Build CLAUDE.md + project memory + context as a `<system-reminder>` block.
    /// Matches Claude Code's claudeMd + project-memory-context + currentDate injection.
    func buildClaudeMdReminder() -> String? {
        let loader = ClaudeMdLoader()
        let cwd = FileManager.default.currentDirectoryPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let memoryFiles = loader.loadAll(workingDirectory: cwd, homeDirectory: home)

        guard !memoryFiles.isEmpty else { return nil }

        var lines: [String] = [
            "<system-reminder>",
            "As you answer the user's questions, you can use the following context:",
        ]

        for file in memoryFiles {
            let pathLabel: String
            switch file.type {
            case .user:
                pathLabel = "Contents of \(file.path) (user's private global instructions for all projects)"
            case .project:
                pathLabel = "Contents of \(file.path) (project instructions, checked into the codebase)"
            case .local:
                pathLabel = "Contents of \(file.path) (user's private project instructions)"
            case .managed:
                pathLabel = "Contents of \(file.path) (enterprise managed policy)"
            case .autoMem:
                pathLabel = "Contents of \(file.path) (user's auto-memory, persists across conversations)"
            }
            lines.append("")
            lines.append("# \(pathLabel)")
            lines.append("")
            lines.append(file.content)
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd"
        lines.append("")
        lines.append("# currentDate")
        lines.append("Today's date is \(df.string(from: Date())).")
        lines.append("")
        lines.append("      IMPORTANT: this context may or may not be relevant to your tasks. You should not respond to this context unless it is highly relevant to your task.")
        lines.append("</system-reminder>")

        return lines.joined(separator: "\n")
    }
}
