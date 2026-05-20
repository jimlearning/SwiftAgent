import Foundation

// MARK: - Tool Name Constants
// Matches Claude Code's constants/tools.ts — centralized tool name registry.

public let FILE_READ_TOOL_NAME = "Read"
public let FILE_WRITE_TOOL_NAME = "Write"
public let FILE_EDIT_TOOL_NAME = "Edit"
public let BASH_TOOL_NAME = "Bash"
public let NOTEBOOK_EDIT_TOOL_NAME = "NotebookEdit"
public let GLOB_TOOL_NAME = "Glob"
public let GREP_TOOL_NAME = "Grep"
public let WEB_FETCH_TOOL_NAME = "WebFetch"
public let WEB_SEARCH_TOOL_NAME = "WebSearch"
public let TODO_WRITE_TOOL_NAME = "TodoWrite"
public let TASK_CREATE_TOOL_NAME = "TaskCreate"
public let TASK_GET_TOOL_NAME = "TaskGet"
public let TASK_LIST_TOOL_NAME = "TaskList"
public let TASK_UPDATE_TOOL_NAME = "TaskUpdate"
public let TASK_OUTPUT_TOOL_NAME = "TaskOutput"
public let TASK_STOP_TOOL_NAME = "TaskStop"
public let AGENT_TOOL_NAME = "Agent"
public let SKILL_TOOL_NAME = "Skill"
public let SEND_MESSAGE_TOOL_NAME = "SendMessage"
public let ASK_USER_QUESTION_TOOL_NAME = "AskUserQuestion"
public let ENTER_PLAN_MODE_TOOL_NAME = "EnterPlanMode"
public let EXIT_PLAN_MODE_TOOL_NAME = "ExitPlanMode"
public let ENTER_WORKTREE_TOOL_NAME = "EnterWorktree"
public let EXIT_WORKTREE_TOOL_NAME = "ExitWorktree"
public let TOOL_SEARCH_TOOL_NAME = "ToolSearch"
public let SYNTHETIC_OUTPUT_TOOL_NAME = "StructuredOutput"
public let CONFIG_TOOL_NAME = "Config"
public let LSP_TOOL_NAME = "LSP"
public let BRIEF_TOOL_NAME = "SendUserMessage"
public let SLEEP_TOOL_NAME = "Sleep"
public let POWERSHELL_TOOL_NAME = "PowerShell"
public let CRON_CREATE_TOOL_NAME = "CronCreate"
public let CRON_DELETE_TOOL_NAME = "CronDelete"
public let CRON_LIST_TOOL_NAME = "CronList"
public let MCP_TOOL_NAME = "MCP"
public let LIST_MCP_RESOURCES_TOOL_NAME = "ListMcpResourcesTool"
public let READ_MCP_RESOURCE_TOOL_NAME = "ReadMcpResourceTool"
public let TEAM_CREATE_TOOL_NAME = "TeamCreate"
public let TEAM_DELETE_TOOL_NAME = "TeamDelete"
public let WORKFLOW_TOOL_NAME = "Workflow"
public let REMOTE_TRIGGER_TOOL_NAME = "RemoteTrigger"
// REPL_TOOL_NAME defined in Tools/REPLMode.swift

public let SHELL_TOOL_NAMES: [String] = [BASH_TOOL_NAME, POWERSHELL_TOOL_NAME]

// MARK: - Agent Tool Access Control Sets

/// Tools disallowed for ALL sub-agents.
/// CC: ALL_AGENT_DISALLOWED_TOOLS — blocks recursion and plan tools.
public var allAgentDisallowedTools: Set<String> {
    var base: Set<String> = [
        TASK_OUTPUT_TOOL_NAME,
        EXIT_PLAN_MODE_TOOL_NAME,
        ENTER_PLAN_MODE_TOOL_NAME,
        ASK_USER_QUESTION_TOOL_NAME,
        TASK_STOP_TOOL_NAME,
    ]
    if ProcessInfo.processInfo.environment["USER_TYPE"] != "ant" {
        base.insert(AGENT_TOOL_NAME)
    }
    // CC: feature('WORKFLOW_SCRIPTS') — ant-internal, gated on USER_TYPE
    if ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" {
        base.insert(WORKFLOW_TOOL_NAME)
    }
    return base
}

/// CC: CUSTOM_AGENT_DISALLOWED_TOOLS — same as ALL for now.
public var customAgentDisallowedTools: Set<String> {
    allAgentDisallowedTools
}

/// Tools allowed for async agents.
/// CC: ASYNC_AGENT_ALLOWED_TOOLS
public let asyncAgentAllowedTools: Set<String> = [
    FILE_READ_TOOL_NAME,
    WEB_SEARCH_TOOL_NAME,
    TODO_WRITE_TOOL_NAME,
    GREP_TOOL_NAME,
    WEB_FETCH_TOOL_NAME,
    GLOB_TOOL_NAME,
    FILE_EDIT_TOOL_NAME,
    FILE_WRITE_TOOL_NAME,
    NOTEBOOK_EDIT_TOOL_NAME,
    SKILL_TOOL_NAME,
    SYNTHETIC_OUTPUT_TOOL_NAME,
    TOOL_SEARCH_TOOL_NAME,
    ENTER_WORKTREE_TOOL_NAME,
    EXIT_WORKTREE_TOOL_NAME,
]

/// Tools allowed for in-process teammates (beyond async agent tools).
/// CC: IN_PROCESS_TEAMMATE_ALLOWED_TOOLS
public var inProcessTeammateAllowedTools: Set<String> {
    var base: Set<String> = [
        TASK_CREATE_TOOL_NAME,
        TASK_GET_TOOL_NAME,
        TASK_LIST_TOOL_NAME,
        TASK_UPDATE_TOOL_NAME,
        SEND_MESSAGE_TOOL_NAME,
    ]
    if FeatureFlags.isKairosCronEnabled() {
        base.formUnion([CRON_CREATE_TOOL_NAME, CRON_DELETE_TOOL_NAME, CRON_LIST_TOOL_NAME])
    }
    return base
}

/// Tools allowed in coordinator mode — output and agent management only.
/// CC: COORDINATOR_MODE_ALLOWED_TOOLS
public let coordinatorModeAllowedTools: Set<String> = [
    AGENT_TOOL_NAME,
    TASK_STOP_TOOL_NAME,
    SEND_MESSAGE_TOOL_NAME,
    SYNTHETIC_OUTPUT_TOOL_NAME,
]
