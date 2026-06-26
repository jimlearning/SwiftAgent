import Foundation

/// Registry for Batch 4 (task/agent/workflow) and Batch 5 (MCP/cron/notifications) tools.
/// All 36 tools paired with ToolMetadata. Combined with Batch1ToolRegistry (15) and
/// Batch23ToolRegistry (9), covers all 63 tools.
public struct Batch45ToolRegistry {
    public static func tools(
        modelProvider: any LanguageModel,
        memoryStore: any SessionMemoryStore,
        permissionEngine: any SessionPermissionEngine,
        toolEngine: any ToolEngine,
        workingDirectory: String,
        mainLoopModel: String,
        mcpClients: [any Sendable] = [],
        userInputPromptHandler: UserInputPromptHandler? = nil,
        setPlanModeActive: (@Sendable (Bool) -> Void)? = nil,
        taskManager: TaskManager,
        todoStore: TodoStore = TodoStore(),
        cronStore: CronStore = CronStore()
    ) -> [(any Tool, ToolMetadata)] {
        let planModeActive = setPlanModeActive ?? { _ in }

        return [
            // MARK: Batch 4 — Task / Agent / Workflow Tools

            (
                AgentTool(
                    modelProvider: modelProvider,
                    memoryStore: memoryStore,
                    permissionEngine: permissionEngine,
                    toolEngine: toolEngine,
                    workingDirectory: workingDirectory,
                    mainLoopModel: mainLoopModel
                ),
                ToolMetadata(
                    searchHint: "spawn sub-agent delegate task",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Spawning sub-agent",
                    requiresApproval: true
                )
            ),
            (
                TaskCreateTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "create task tracking todo",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Creating task",
                    requiresApproval: false
                )
            ),
            (
                TaskUpdateTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "update task status progress",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Updating task",
                    requiresApproval: false
                )
            ),
            (
                TaskStopTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "stop cancel kill task",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Stopping task",
                    requiresApproval: false
                )
            ),
            (
                TaskOutputTool(taskManager: taskManager),
                ToolMetadata(
                    searchHint: "get task output result",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Getting task output",
                    requiresApproval: false
                )
            ),
            (
                TodoWriteTool(todoStore: todoStore),
                ToolMetadata(
                    searchHint: "write todo list create task",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Writing todos",
                    requiresApproval: false
                )
            ),
            (
                TeamCreateTool(),
                ToolMetadata(
                    searchHint: "create team workspace",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Creating team",
                    requiresApproval: false
                )
            ),
            (
                TeamDeleteTool(),
                ToolMetadata(
                    searchHint: "delete team workspace",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Deleting team",
                    requiresApproval: false
                )
            ),
            (
                SendMessageTool(),
                ToolMetadata(
                    searchHint: "send message user notification broadcast",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Sending message",
                    requiresApproval: false
                )
            ),
            (
                EnterPlanModeTool(setPlanModeActive: planModeActive),
                ToolMetadata(
                    searchHint: "enter plan mode planning architecture",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Entering plan mode",
                    requiresApproval: false
                )
            ),
            (
                ExitPlanModeV2Tool(setPlanModeActive: planModeActive),
                ToolMetadata(
                    searchHint: "exit plan mode leave planning",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Exiting plan mode",
                    requiresApproval: false
                )
            ),
            (
                VerifyPlanExecutionTool(),
                ToolMetadata(
                    searchHint: "verify plan execution validation",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Verifying plan",
                    requiresApproval: false
                )
            ),
            (
                SyntheticOutputTool(),
                ToolMetadata(
                    searchHint: "synthetic output test mock",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Generating output",
                    requiresApproval: false
                )
            ),
            (
                WorkflowTool(),
                ToolMetadata(
                    searchHint: "workflow automation pipeline",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Running workflow",
                    requiresApproval: false
                )
            ),
            (
                REPLModeTool(),
                ToolMetadata(
                    searchHint: "REPL mode read eval print loop",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Toggling REPL mode",
                    requiresApproval: false
                )
            ),
            (
                EnterWorktreeTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "enter worktree git isolation",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Entering worktree",
                    requiresApproval: true
                )
            ),
            (
                ExitWorktreeTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "exit worktree leave isolation",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Exiting worktree",
                    requiresApproval: false
                )
            ),
            (
                SuggestBackgroundPRTool(),
                ToolMetadata(
                    searchHint: "suggest background PR pull request",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Suggesting PR",
                    requiresApproval: false
                )
            ),
            (
                SubscribePRTool(),
                ToolMetadata(
                    searchHint: "subscribe PR pull request watch",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Subscribing to PR",
                    requiresApproval: false
                )
            ),
            (
                SleepTool(),
                ToolMetadata(
                    searchHint: "sleep wait delay pause",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Sleeping",
                    requiresApproval: false
                )
            ),

            // MARK: Batch 5 — MCP / Cron / UI / Notifications

            (
                MCPTool(mcpClients: mcpClients),
                ToolMetadata(
                    searchHint: "MCP server tool execute call",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Calling MCP tool",
                    requiresApproval: true
                )
            ),
            (
                DynamicMCPTool(
                    serverName: "",
                    toolName: "",
                    toolDescription: "",
                    inputSchema: JSONSchema(type: "object", properties: [:]),
                    bootstrapper: MCPBootstrapper()
                ),
                ToolMetadata(
                    searchHint: "dynamic MCP tool bootstrapper discover",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Bootstrapping MCP tool",
                    requiresApproval: true
                )
            ),
            (
                McpAuthTool(mcpClients: mcpClients),
                ToolMetadata(
                    searchHint: "MCP authentication OAuth login",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Authenticating MCP",
                    requiresApproval: true
                )
            ),
            (
                SkillTool(),
                ToolMetadata(
                    searchHint: "skill execute run plugin",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Running skill",
                    requiresApproval: false
                )
            ),
            (
                AskUserQuestionTool(userInputPromptHandler: userInputPromptHandler),
                ToolMetadata(
                    searchHint: "ask user question prompt interact",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Asking user",
                    requiresApproval: false
                )
            ),
            (
                ConfigTool(),
                ToolMetadata(
                    searchHint: "get or set configuration settings theme model",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Configuring",
                    requiresApproval: false
                )
            ),
            (
                TestingPermissionTool(),
                ToolMetadata(
                    searchHint: "test permission system behavior",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Testing permissions",
                    requiresApproval: false
                )
            ),
            (
                CronCreateTool(cronStore: cronStore),
                ToolMetadata(
                    searchHint: "schedule recurring one-shot cron job timer",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Scheduling cron",
                    requiresApproval: false
                )
            ),
            (
                CronDeleteTool(cronStore: cronStore),
                ToolMetadata(
                    searchHint: "delete remove cancel cron job schedule",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Deleting cron",
                    requiresApproval: false
                )
            ),
            (
                CronListTool(cronStore: cronStore),
                ToolMetadata(
                    searchHint: "list cron jobs schedules",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Listing crons",
                    requiresApproval: false
                )
            ),
            (
                PushNotificationTool(),
                ToolMetadata(
                    searchHint: "push notification send notify",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Sending notification",
                    requiresApproval: false
                )
            ),
            (
                RemoteTriggerTool(),
                ToolMetadata(
                    searchHint: "remote trigger invoke webhook",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Triggering remote",
                    requiresApproval: false
                )
            ),
            (
                MonitorTool(),
                ToolMetadata(
                    searchHint: "monitor watch observe stream",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Monitoring",
                    requiresApproval: false
                )
            ),
            (
                SendUserFileTool(),
                ToolMetadata(
                    searchHint: "send user file attachment upload",
                    isReadOnly: false,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Sending file",
                    requiresApproval: false
                )
            ),
            (
                WebBrowserTool(),
                ToolMetadata(
                    searchHint: "web browser open URL navigate",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Opening browser",
                    requiresApproval: false
                )
            ),
            (
                OverflowTestTool(),
                ToolMetadata(
                    searchHint: "overflow test large output truncation",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Running overflow test",
                    requiresApproval: false
                )
            ),
        ]
    }
}
