# MCP Alignment Report

**Date:** 2026-06-01 (updated 2026-06-01)
**Scope:** MCP tool schema delivery, instructions injection, deferred loading, tool naming parity, and system prompt structure alignment between SwiftAgent and Claude Code.

---

## 1. Background

SwiftAgent and Claude Code share the same LLM backend (DeepSeek via Anthropic-compatible API), but initial testing revealed a significant behavioral gap:

- **Claude Code** used approximately 5 codegraph calls to understand and answer a question about a codebase: `codegraph_context` -> `codegraph_search` -> `codegraph_explore` -> `codegraph_node` -> `codegraph_trace`.
- **SwiftAgent** used approximately 20 calls for the same task: 3 `codegraph_explore`, 10 `codegraph_node`, 2 `codegraph_search`, 3 `Read`. The model was thrashing -- not converging on the right tools.

The root cause was not the model. It was structural: SwiftAgent was not communicating tool metadata to the LLM in the format and salience that Claude Code uses. The goal of this work was strict structural alignment with CC's prompts, message formatting, and tool definition patterns so that both systems present equivalent information to the same model backend.

---

## 2. Root Cause Analysis

Four distinct bugs were discovered, each independently causing degraded LLM tool selection.

### Bug 1: MCP tool inputSchema was hardcoded to empty `{}`

Before the fix, `MCPToolBridge` produced `JSONSchema(type: "object")` for every MCP tool. The LLM received tool definitions like:

```json
{
  "name": "mcp__codegraph__codegraph_node",
  "description": "...",
  "input_schema": { "type": "object" }
}
```

No `properties`, no `required` fields, no parameter descriptions. The LLM had no way to know what parameters a tool expected. It would guess parameter names and guess wrong, producing invalid tool calls or resorting to generic tools (like `Bash` with `grep`) instead.

The fix was to add `parseMCPInputSchema()` and `parseMCPProperty()` to `MCPClient.swift` (lines 269-343), which parse the full JSON Schema from the MCP `tools/list` response into SwiftAgent's `JSONSchema` type, preserving `properties`, `required`, `enum`, `items`, `additionalProperties`, and `description`.

### Bug 2: MCP server `instructions` were never passed to the LLM

The MCP protocol allows servers to return `instructions` in both the `InitializeResult` and the `tools/list` response. These instructions tell the LLM HOW to use the server's tools. For example, codegraph's instructions say:

> "Answer DIRECTLY using 2-3 codegraph calls: `codegraph_context` first, then ONE `codegraph_explore`..."

SwiftAgent was parsing and discarding these instructions. They never reached the system prompt or conversation.

The fix involved:
- `MCPClient.swift`: Capturing `initializeInstructions` from `InitializeResult` (line 36) and returning `instructions` from `listTools()` (line 48).
- `MCPBootstrapper.swift`: Collecting instructions into `serverInstructions: [String: String]` (line 25), preferring `client.initializeInstructions` over the `tools/list` version (line 270).
- `ChatCommand.swift`: Passing instructions into the new `buildMcpSystemReminder()` (line 555).

### Bug 3: MCP instructions were placed at the end of the system prompt (buried)

Even when instructions reached the system prompt, they were in the wrong place. SwiftAgent appended MCP instructions to the dynamic suffix of the system prompt -- the last section before the LLM's first turn. Claude Code instead injects them as `<system-reminder>` blocks in the conversation itself, where they are highly salient.

The `<system-reminder>` tag is an Anthropic API convention. Content wrapped in `<system-reminder>` blocks is treated by the model as system-level directives regardless of where it appears in the conversation. Claude Code uses this mechanism to deliver MCP instructions, project context, and other critical guidance.

The fix: `ChatCommand.swift` now builds the first user message as 4 separate text blocks:

1. **Deferred tools announcement** as `<system-reminder>`
2. **MCP server instructions** as `<system-reminder>`
3. **CLAUDE.md + project memory + current date** as `<system-reminder>`
4. **User input** (plain text, no tag)

This matches CC's message structure exactly. The `SystemPromptBuilder` now includes a comment noting that MCP instructions are delivered via conversation blocks, not the system prompt (line 103-106).

### Bug 4: Generic `MCPTool` registration steals calls from per-tool `DynamicMCPTool` instances

SwiftAgent had TWO parallel MCP invocation paths registered simultaneously:

1. **`MCPTool`** (`MCPTool.swift:11`) — a generic "meta" tool with `name = "MCP"`. Takes `serverName`, `toolName`, and `arguments` (JSON string) as parameters. Always inline (not deferred), always available with a short, simple name.
2. **`DynamicMCPTool`** instances — one per MCP server tool, named `mcp__codegraph__codegraph_context` etc., with the tool's full JSON Schema. Deferred, requiring ToolSearch to load.

The model always chose the simpler `"MCP"` tool. Debug log analysis showed:

```
112 "name":"MCP"          ← generic tool stealing calls
 10 "name":"mcp__codegraph__codegraph_context"   ← actual per-tool schema
 10 "name":"mcp__codegraph__codegraph_explore"
 10 "name":"mcp__codegraph__codegraph_node"
 10 "name":"mcp__codegraph__codegraph_search"
 10 "name":"mcp__codegraph__codegraph_trace"
```

This completely defeated deferred loading because:

- The model saw `"MCP"` as a shortcut — pass `serverName: "codegraph"`, `toolName: "codegraph_search"`, `arguments: "{\"query\":\"...\"}"` instead of learning the proper `mcp__codegraph__codegraph_search` schema.
- The generic tool has no per-tool parameter schema, so the model had to guess argument names anyway — exactly the problem Bug 1 already fixed.
- The terminal display showed `MCP → MCP` for every MCP call, making it impossible to tell which tool was actually invoked.
- The model never learned to use ToolSearch properly because `"MCP"` was always available as a direct shortcut.

**The fix:**

1. **Removed `registry.register(MCPTool())`** from `ChatCommand.swift:1810`. The `DynamicMCPTool` instances registered during MCP bootstrap already cover every MCP server tool with proper per-tool names and full schemas.
2. **Added `shouldDefer = true` to `MCPTool`** (`MCPTool.swift:17`) as a safety measure in case it gets re-registered elsewhere in the future.

This matches Claude Code's architecture: CC has no generic "MCP" meta-tool. Each MCP server tool gets its own entry in the tools list with its real name and schema.

**Verification:** After the fix, debug logs show zero `"MCP"` calls. All MCP tool usage flows through the properly-named `mcp__<server>__<tool>` tools with full schemas.

---

## 3. Changes Made

### 3.1 MCPClient.swift

- **`initializeInstructions` property** (line 12): Captured from `InitializeResult` response during `connect()`. Per the MCP spec this is the canonical source of server-level instructions.
- **`listTools()` return type** (line 45): Changed from `[MCPToolDescription]` to `(tools: [MCPToolDescription], instructions: String?)`. The tuple carries server-level instructions returned alongside the tools list.
- **`parseMCPInputSchema()`** (line 269): Private function that parses an MCP `inputSchema` JSON object into SwiftAgent's `JSONSchema` struct. Extracts `type`, `properties`, `required`, `additionalProperties`, and `description`.
- **`parseMCPProperty()`** (line 310): Private function that parses a single JSON Schema property. Extracts `type`, `description`, `enum`, and `items` (array element type).

### 3.2 MCPBootstrapper.swift

- **`serverInstructions` property** (line 25): `[String: String]` dictionary mapping server names to their instructions text.
- **Return type updates**: `connectAndDiscover()` and `doConnectAndDiscover()` now carry instructions through their return tuples.
- **Instructions priority** (line 270): Prefers `client.initializeInstructions` over `tools/list` instructions. From the comment: "InitializeResult.instructions is canonical per MCP spec."
- **Actor isolation fix** (line 140): Uses a local `collectedInstructions` dictionary inside `bootstrap()` to accumulate instructions across concurrent server connections, then assigns to the actor-isolated `serverInstructions` property at the end (line 189).

### 3.3 ChatCommand.swift

- **4 separate text blocks** (lines 542-570): The first user message is now constructed as separate `ContentBlock.text()` entries:
  - Block 1: Deferred tools `<system-reminder>` (via `buildDeferredToolsReminder`)
  - Block 2: MCP instructions `<system-reminder>` (via `buildMcpSystemReminder`)
  - Block 3: CLAUDE.md + memory + date `<system-reminder>` (via `buildClaudeMdReminder`)
  - Block 4: Raw user input
- **`buildMcpSystemReminder()`** (line 1236): Wraps MCP server instructions in `<system-reminder>` tags with a "MCP Server Instructions" header. Matches CC's `wrapMessagesInSystemReminder` format.
- **`buildDeferredToolsReminder()`** (line 1260): Lists deferred tool names in a `<system-reminder>` block with explicit `select:` prefix on each group so the model can copy-paste the exact ToolSearch query. Groups MCP tools by server, puts high-value tools (`context`, `explore`) first.
- **`buildClaudeMdReminder()`** (line 1277): Injects CLAUDE.md files, project memory, and current date as a single `<system-reminder>` block. Matches CC's claudeMd + project-memory-context + currentDate injection.
- **`buildSystemPrompt()`** (line 1226): Now accepts `model` and `toolNames` parameters, passed from the caller.
- **Removed `registry.register(MCPTool())`** (was line 1810): The generic MCP meta-tool is no longer registered. DynamicMCPTool instances provide per-tool schemas. See Bug 4.

### 3.4 MCPTool.swift

- **`shouldDefer = true`** (line 17): Added as a safety measure in case `MCPTool` is re-registered elsewhere. The tool itself is no longer registered in ChatCommand.swift (see Bug 4).

### 3.5 SystemPromptBuilder.swift

- **`# Text output` section** (line 293): Added `textOutputSection()` matching CC's `getTextOutputSection`. Contains guidance about text output being the primary user-facing channel, end-of-turn summaries, and conciseness rules. This was previously missing.
- **MCP instructions removed** (lines 103-106): The `mcpInstructionsSection()` method still exists but is no longer called. Comment explains: "MCP server instructions are now delivered as <system-reminder> blocks in conversation messages. This matches Claude Code's approach and makes instructions far more salient."
- **System prompt caching** (in `LLMClient.swift`): The `apiFormattedSystem()` method (line 512) now wraps the entire system prompt as a single cached text block, matching CC's approach. Previously it used a 2-block split (static prefix cached, dynamic suffix uncached).

### 3.6 LLMClient.swift (ToolDefinition)

- **`deferLoading: Bool` field** (line 594): Added to `ToolDefinition`. Defaults to `false`.
- **`apiFormatted` inclusion** (line 612): When `deferLoading` is true, adds `"defer_loading": true` to the API-formatted tool definition. This is the standard Anthropic API field for deferred tools.
- **System prompt caching** (line 512): Changed to single-block full cache with `"cache_control": ["type": "ephemeral"]`. The 2-block split for cacheScope:'global' on the static prefix is no longer used.

### 3.7 ToolExecutor.swift (ToolRegistry)

- **`toolDefinitions()`** (line 181): Sets `deferLoading: deferLoading` on each `ToolDefinition` using `tool.shouldDefer && !tool.alwaysLoad`.
- **`filterToolsByDenyRules()`** (line 213): Same deferred flag logic for filtered tool lists.

### 3.8 DynamicMCPTool.swift

- **`shouldDefer = true`**: All MCP tools are deferred by default, matching CC's architecture. The model must use ToolSearch to load MCP tool schemas before calling them.
- **`mcpInfo: MCPToolInfo?`**: Carries server and tool name metadata for display and routing purposes.

### 3.9 Critical inline tools

The following tools that Claude Code ALWAYS keeps inline are confirmed to have no `shouldDefer` override in SwiftAgent:

| Tool | `shouldDefer` | Status |
|------|---------------|--------|
| `AskUserQuestionTool` | `false` (default) | Inline |
| `TodoWriteTool` | `false` (default) | Inline |
| `TaskCreateTool` | `false` (default) | Inline |
| `NotebookEditTool` | `false` (default) | Inline |
| `Agent`, `Bash`, `Edit`, `Read`, `Write`, `Skill`, `ToolSearch` | `false` (default) | Inline |

The current codebase has ~30 tools with `shouldDefer: true` — MCP tools (DynamicMCPTool, MCPTool), rarely-used specialized tools (ConfigTool, CronCreateTool, TaskGetTool, LSPTool, WebFetch, WebSearch), and management tools.

---

## 4. Deferred Loading: Attempt and Pivot

### 4.1 Why deferred loading was attempted

Claude Code's first API request sends only 9 tools inline:

1. Agent
2. AskUserQuestion
3. Bash
4. Edit
5. Read
6. ScheduleWakeup
7. Skill
8. ToolSearch
9. Write

All other tools (including ~35 built-in tools and all MCP tools) are deferred with `defer_loading: true`. The LLM discovers them via `ToolSearch`, which loads their schemas on demand. This two-step cognitive pattern:

- Reduces the initial prompt by thousands of tokens (tool schemas are expensive).
- Guides the LLM toward deliberate tool selection rather than serial guessing.
- Matches how humans learn tools: know the handful of core tools, discover specialized ones as needed.

### 4.2 Infrastructure built

The deferred loading feature required changes across multiple files:

- `ToolDefinition.deferLoading: Bool` -- maps to `defer_loading: true` in the API body.
- `ToolRegistry.toolDefinitions()` -- sets the flag based on `shouldDefer && !alwaysLoad`.
- `buildDeferredToolsReminder()` -- lists available deferred tools in a `<system-reminder>` block so the LLM knows about them without seeing schemas.
- `DynamicMCPTool.shouldDefer = true` was set to treat all MCP tools as deferred.

### 4.3 Model behavior with deferred loading

With the infrastructure fixed (Bug 1-4 all resolved), deferred loading is structurally correct and active for MCP tools. However, DeepSeek-v4-pro does not leverage it as efficiently as Claude's native models:

- Claude's models read MCP instructions, load multiple tools at once via `select:` query, and use the optimal `context → explore → trace` chain.
- DeepSeek loads the tools but tends to chain individual `codegraph_node` calls (30-50 per task) rather than using `codegraph_explore`. It also sometimes falls back to manual Read/Grep/Bash despite the instructions.

This is a model-level behavior gap, not a code issue. The infrastructure is correct.

### 4.4 Current state

- **Infrastructure fully operational**: `deferLoading` field, `ToolRegistry` support, `buildDeferredToolsReminder()`, `extractDiscoveredToolNames()`, and `filterDeferredTools()` are all functional and tested.
- **MCP tools deferred**: `DynamicMCPTool.shouldDefer = true` is active. All MCP tools require ToolSearch discovery. This matches CC's architecture.
- **ToolSearch returns full schemas**: `select:` queries with explicit prefix in deferred reminder cause model to load all codegraph tools in one call. `extractDiscoveredToolNames()` and `filterDeferredTools()` correctly manage the discover/undefer lifecycle.
- **Generic MCPTool removed**: The legacy `MCPTool(name: "MCP")` meta-tool is no longer registered (Bug 4). All MCP calls go through properly-named per-tool instances.
- **~30 tools deferred**: MCP tools + rarely-used specialized tools (ConfigTool, CronCreateTool, LSPTool, WebFetch, WebSearch, etc.).
- **Verified**: Zero `"MCP"` generic tool calls in latest debug logs. Tool names display correctly as `mcp__codegraph__codegraph_context` etc.

---

## 5. Results

| Metric | Before | After |
|--------|--------|-------|
| Generic MCP tool calls | 112 "MCP" calls (tool name hidden) | 0 — removed, all calls use proper names |
| MCP tool display | `MCP → MCP` (unreadable) | `mcp__codegraph__codegraph_context → task: ...` |
| MCP tool schemas | Empty `{}` | Full JSON Schema with `properties`, `required`, `enum` |
| MCP instructions | Not delivered | Delivered as `<system-reminder>` conversation blocks |
| Deferred tool discovery | Broken: ToolSearch keyword search, no `select:` | Working: explicit `select:` queries load schemas in one call |
| User message structure | 1 merged text block | 4 separate text blocks (deferred tools + MCP + CLAUDE.md + user input) |
| System prompt caching | 2-block split (static prefix cached, dynamic uncached) | 1-block full cache (CC-aligned) |
| `# Text output` section | Missing | Added matching CC's `getTextOutputSection` |
| `ToolDefinition` API format | No `defer_loading` field | `defer_loading: true` set when `shouldDefer && !alwaysLoad` |

---

## 6. Remaining Work

### 6.1 Model-level tool selection optimization

The infrastructure is now structurally aligned with Claude Code. All four bugs are fixed. However, DeepSeek-v4-pro does not follow the codegraph instructions as reliably as Claude's native models:

- DeepSeek tends to chain individual `codegraph_node` and `codegraph_search` calls instead of using `codegraph_explore` (the preferred tool for surveying an area).
- It sometimes falls back to manual Read/Grep/Bash operations (90+ calls in some sessions) despite instructions to prefer codegraph.
- The instructions ARE delivered correctly; this is a model behavior gap, not a code issue.

Potential mitigations:
- Simplified/shorter codegraph instructions that emphasize the `context -> explore` chain more aggressively.
- A post-processing step that detects repetitive `codegraph_node` patterns and prompts the model to use `codegraph_explore` instead.
- Model upgrade when a more capable version becomes available.

### 6.2 `alwaysLoad` flag for critical tools

Claude Code keeps certain tools inline even when deferred loading is enabled (`alwaysLoad: true`). SwiftAgent should identify tools that should ALWAYS be available and set `alwaysLoad` appropriately. Candidates: tools that run during session startup or are fundamental to the agent loop (e.g., `ScheduleWakeup`).

### 6.3 SessionStart hook support for superpowers/skills

Claude Code uses SessionStart hooks to inject superpowers and skills as `<system-reminder>` blocks. SwiftAgent currently hardcodes CLAUDE.md loading in `buildClaudeMdReminder()`. A generic SessionStart hook mechanism would allow skills to register their own `<system-reminder>` injections, making the system extensible without modifying ChatCommand.

### 6.4 `anthropic-beta` headers for advanced tool use

SwiftAgent currently sends beta headers for `prompt-caching-scope` and `interleaved-thinking` (line 671 in ChatCommand), plus conditionally `advanced-tool-use-2025-11-20` when deferred tools are present. Additional beta headers may be needed as tool capabilities expand.
