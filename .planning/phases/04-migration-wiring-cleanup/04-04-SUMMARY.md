# Plan 04-04 Summary: Protocol Rename + Batch 4+5 Migration

**Status:** Complete

## What was done

1. **Renamed RuntimeAgentTool → Tool** per FoundationModels alignment (Wave 4 of master plan).
   - `Sources/SwiftAgentCore/AgentRuntime/Tools/RuntimeAgentTool.swift`: protocol renamed to `Tool<Arguments>`, `Input` → `Arguments`, `call(_:)` → `call(arguments:)`
   - Added `public typealias RuntimeAgentTool = Tool` for backward compatibility
   - Doc comment updated to reference `ToolMetadata` separation

2. **Migrated 20 Batch 4 tools** (task/agent/workflow): AgentTool, TaskCreateTool, TaskUpdateTool, TaskStopTool, TaskOutputTool, TodoWriteTool, TeamCreateTool, TeamDeleteTool, SendMessageTool, EnterPlanModeTool, ExitPlanModeV2Tool, VerifyPlanExecutionTool, SyntheticOutputTool, WorkflowTool, REPLMode, EnterWorktreeTool, ExitWorktreeTool, SuggestBackgroundPRTool, SubscribePRTool, SleepTool

3. **Migrated 16 Batch 5 tools** (MCP/cron/UI/notifications): MCPTool, DynamicMCPTool, McpAuthTool, SkillTool, AskUserQuestionTool, ConfigTool, TestingPermissionTool, CronCreateTool, CronDeleteTool, CronListTool, PushNotificationTool, RemoteTriggerTool, MonitorTool, SendUserFileTool, WebBrowserTool, OverflowTestTool

4. **Created 3 tool registries:**
   - `Batch1ToolRegistry.swift` — 15 read-only tools (requires workingDirectory, mcpClients, taskManager, availableTools)
   - `Batch23ToolRegistry.swift` — 9 file mutation + command tools (requires workingDirectory, shell)
   - `Batch45ToolRegistry.swift` — 36 task/agent/MCP/cron/UI tools (requires full subsystem set: modelProvider, memoryStore, permissionEngine, toolEngine, workingDirectory, mainLoopModel, mcpClients, userInputPromptHandler, setPlanModeActive, taskManager, todoStore, cronStore)

5. **Relocated shared types** from `Sources/SwiftAgentCore/Tools/` → `Sources/SwiftAgentCore/Types/`:
   - BuiltInAgents.swift, CronTypes.swift, WorktreeTypes.swift, BundledSkills.swift

6. **Emptied `Sources/SwiftAgentCore/Tools/`** — all 43 old tool files deleted. `Types/Tool.swift` reduced to 25 lines (only ToolProgress types survive).

## Key design decisions

- **D-03 context injection**: Tools capture context fields (workingDirectory, taskManager, etc.) as `let` properties at init — no `ToolUseContext` parameter
- **Typed Arguments structs**: Every tool has a Codable & Sendable Arguments struct with CodingKeys for snake_case JSON
- **ToolMetadata separation**: Operational data (searchHint, isReadOnly, isConcurrencySafe, isDestructive, interruptBehavior, activityDescription, requiresApproval) lives in ToolMetadata, not on the Tool protocol
- **Closure-based context**: Plan mode tools capture `setPlanModeActive`; AskUserQuestionTool captures `userInputPromptHandler`
- **AgentTool**: Creates child `LanguageModelSessionImpl` with same providers, calls `respond(to:)` for sub-agent delegation

## Verification

- 60 tools conforming to `Tool` protocol across 3 registries
- Old `Tools/` directory emptied (0 files)
- Old `Tool` protocol deleted from `Types/Tool.swift`
- All `RuntimeAgentTool` references updated to `Tool` in AgentRuntime/ subsystem
- `SessionToolDefinition` → `RuntimeToolDefinition` fix applied (ToolSearchTool, Batch1ToolRegistry)
- Build does NOT pass — `ToolUseContext`, `ToolResult`, old Tool members still referenced by files that Plans 04-05/04-06 will delete/rewrite (intentional)

## Next: Plan 04-05

CLI ChatCommand rewired to LanguageModelSessionImpl. SessionEventRenderer built. 13 deprecated files deleted.
