# SwiftAgent Roadmap

## Phase Progress

| Phase | Name | Status | Notes |
|---|---|---|---|
| 0 | Project Scaffolding | Done | Package.swift, docs, CI scripts |
| 1 | Core Types & Domain Model | Done | 22 type files, full CC domain model |
| 2 | LLM Adapter & Streaming | Done | LLMClient, StreamParser, RetryPolicy, ModelRegistry, TokenCounter |
| 3 | Agent Loop | Done | QueryEngine, PromptBuilder, ContextManager, ToolExecutor, StreamRenderer |
| 4 | Tool System | Done | 43 tools (Read/Write/Edit/Bash/Glob/Grep + Agent/Skill/Task*/MCP/etc.) |
| 5 | CLI & Terminal UI | Done | ChatCommand, TerminalRenderer, LineEditor (paste, multi-line, ESC cancel), MarkdownRenderer |
| 6 | Permission & Safety | Done | 10-step pipeline, AST-aware SafetyChecker, PermissionStore |
| 7 | Configuration System | Done | 5-layer ConfigLoader, ConfigSchema, APIKeyResolver |
| 8 | Slash Commands | Done | CommandRegistry with built-ins |
| 9 | Session & Memory | Done | SessionStore (JSON), MemoryStore (CLAUDE.md with frontmatter) |
| 10 | MCP Integration | Done | MCPClient, SSE/HTTP transport, tool bridge |
| 11 | Sub-Agent & Tasks | Done | SubAgentManager, TaskManager (actor), WorktreeManager |
| 12+ | Advanced Features | Done | HookSystem, PluginManager, FeatureFlags |

Build: 0 errors, 0 warnings. Tests: 171 tests, 47 suites, all passing.

## MVP Scope (Complete)

Phases 0–5: working Swift project, core agent loop, file and shell tools, interactive CLI with terminal rendering.

## Current Blockers

None.

## Next Priorities

1. **Wire up `prompt()`** — Have SystemPromptBuilder call `tool.prompt()` to inject tool docs into system prompt (matches CC behavior)
2. **Implement `isEnabled()` feature gates** — Add feature flag infrastructure for conditional tool enablement (19 tools need this)
3. **Expand CLI flags** — CC has ~70 flags; SA has ~7. Add the most impactful ones (--continue, --resume, --verbose, --print, --output-format)
4. **Flesh out stub tools** — MCPTool, McpAuthTool, RemoteTriggerTool, TeamCreateTool, TeamDeleteTool are stubs
5. **TUI enhancements** — Full terminal UI (tmux integration, iTerm2 features) not yet implemented

## Recently Completed

All 12 phases complete. Recent CLI enhancements: paste detection, multi-line input (Option+Enter/Shift+Enter), ESC to cancel, markdown rendering (headings, code blocks, display-width-aligned tables), emitBlock spacing, zero build warnings.
