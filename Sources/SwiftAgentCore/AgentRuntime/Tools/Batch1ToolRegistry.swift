import Foundation

/// Registry for all 15 read-only (Batch 1) tools.
/// Constructs each tool with its required init-time context and pairs it with
/// ToolMetadata. Consumed by session construction in CLI (Plan 04-05) and App (Plan 04-06).
public struct Batch1ToolRegistry {
    public static func tools(
        workingDirectory: String,
        mcpClients: [any Sendable] = [],
        taskManager: TaskManager,
        availableTools: [SessionToolDefinition]
    ) -> [(any Tool, ToolMetadata)] {
        [
            (
                FileReadTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "Read file contents text image PDF notebook",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Reading file",
                    requiresApproval: false
                )
            ),
            (
                GrepTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "Search text patterns ripgrep regex grep",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Searching code",
                    requiresApproval: false
                )
            ),
            (
                GlobTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "Find files by pattern glob match",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Finding files",
                    requiresApproval: false
                )
            ),
            (
                WebSearchTool(),
                ToolMetadata(
                    searchHint: "Web search current information internet",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Searching web",
                    requiresApproval: false
                )
            ),
            (
                WebFetchTool(),
                ToolMetadata(
                    searchHint: "Fetch URL content markdown webpage",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Fetching URL",
                    requiresApproval: false
                )
            ),
            (
                ListSkillsTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "List available skills plugins custom",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Listing skills",
                    requiresApproval: false
                )
            ),
            (
                ToolSearchTool(availableTools: availableTools),
                ToolMetadata(
                    searchHint: "Search tool definitions schemas deferred",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Searching tools",
                    requiresApproval: false
                )
            ),
            (
                ListMcpResourcesTool(mcpClients: mcpClients),
                ToolMetadata(
                    searchHint: "List MCP resources servers connected",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Listing MCP resources",
                    requiresApproval: false
                )
            ),
            (
                ReadMcpResourceTool(mcpClients: mcpClients),
                ToolMetadata(
                    searchHint: "Read MCP resource URI server",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Reading MCP resource",
                    requiresApproval: false
                )
            ),
            (
                CtxInspectTool(),
                ToolMetadata(
                    searchHint: "Inspect context compaction collapse state",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Inspecting context",
                    requiresApproval: false
                )
            ),
            (
                ListPeersTool(),
                ToolMetadata(
                    searchHint: "List peer connections network unix socket",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Listing peers",
                    requiresApproval: false
                )
            ),
            (
                BriefTool(),
                ToolMetadata(
                    searchHint: "Send message user output visible channel",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Sending message",
                    requiresApproval: false
                )
            ),
            (
                TaskGetTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "Get task details status progress by ID",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Getting task",
                    requiresApproval: false
                )
            ),
            (
                TaskListTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "List tasks status progress all tracked",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Listing tasks",
                    requiresApproval: false
                )
            ),
            (
                BundledSkillsTool(),
                ToolMetadata(
                    searchHint: "List bundled built-in skills included",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Listing bundled skills",
                    requiresApproval: false
                )
            ),
        ]
    }
}
