# Plan 04-02 Summary: Batch 1 Read-Only Tool Migration

**Status:** Complete

## What was done

1. Created 15 RuntimeAgentTool-conforming tool files in `AgentRuntime/Tools/`:
   FileReadTool, GrepTool, GlobTool, WebSearchTool, WebFetchTool, ListSkillsTool,
   ToolSearchTool, ListMcpResourcesTool, ReadMcpResourceTool, CtxInspectTool,
   ListPeersTool, BriefTool (SendUserMessage), TaskGetTool, TaskListTool, BundledSkillsTool

2. Each tool uses typed `Arguments: Codable & Sendable` structs with `CodingKeys` for snake_case JSON keys. Context fields (workingDirectory, mcpClients, taskManager, availableTools) captured at init per D-03. All return `ToolOutputValue` (no `isError` parameter).

3. Restored `JSONValueHelpers.swift` with `[String: JSONValue]` extensions (stringValue, intValue, boolValue) needed by unmigrated code (ChatCommand, BashTool).

4. Added public `extractDiscoveredToolNames` and `filterDeferredTools` functions to ToolSearchTool.swift (referenced by ChatCommand).

5. Created `Batch1ToolRegistry.swift` with static `tools(workingDirectory:mcpClients:taskManager:availableTools:)` returning `[(any RuntimeAgentTool, ToolMetadata)]` for all 15 tools. All metadata has `isReadOnly: true`, `requiresApproval: false`.

6. Deleted 14 old tool files from `Sources/SwiftAgentCore/Tools/` (SPM naming conflict required removal; BundledSkills.swift kept as BundledSkillsTool.swift is a different name).

## Verification

- `swift build --disable-sandbox --target SwiftAgentCore` compiles with zero errors
- 15 tool files conform to RuntimeAgentTool
- Batch1ToolRegistry has 15 ToolMetadata entries, all `isReadOnly: true`
