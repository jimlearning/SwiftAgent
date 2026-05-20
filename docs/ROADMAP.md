# SwiftAgent Roadmap

## Phase Progress

| Phase | Name | Status | Notes |
|---|---|---|---|
| 0 | Project Scaffolding | ✅ Done | Package.swift, docs, CI scripts, build/test pass |
| 1 | Core Types & Domain Model | ✅ Done | 10 types + 18 tests passing |
| 2 | LLM Adapter & Streaming | ✅ Done | LLMClient, StreamParser, RetryPolicy, ModelRegistry, TokenCounter + 14 tests |
| 3 | Agent Loop | ✅ Done | QueryEngine, PromptBuilder, ContextManager, ToolExecutor, StreamRenderer + 15 tests |
| 4 | Tool System | ✅ Done | 6 tools (Read/Write/Edit/Bash/Glob/Grep) + 12 tests |
| 5 | CLI & Terminal UI | ✅ Done | ChatCommand, TerminalRenderer, Capability, StatusLine, ColorTheme. CLI operational. |
| 6 | Permission & Safety | ✅ Done | PermissionEngine, SafetyChecker, PermissionStore + 13 tests |
| 7 | Configuration System | ✅ Done | 5-layer ConfigLoader, ConfigSchema validation + 5 tests |
| 8 | Slash Commands | ✅ Done | CommandRegistry with 7 built-ins + 8 tests |
| 9 | Session & Memory | ✅ Done | SessionStore (JSON), MemoryStore (CLAUDE.md) + 8 tests |
| 10 | MCP Integration | ✅ Done | MCPClient, StdioTransport, MCPToolBridge, MessageCoder + 12 tests |
| 11 | Sub-Agent & Tasks | ✅ Done | SubAgentManager, TaskManager, WorktreeManager + 13 tests |
| 12+ | Advanced Features | ✅ Done | HookSystem, PluginManager, FeatureFlags + 14 tests |

## MVP Scope

Phases 0–5 constitute the Minimum Viable Product:
- Working Swift project
- Core agent loop with LLM integration
- File and shell tools
- Interactive CLI with terminal rendering

## Current Blockers

None.

## Recently Completed

All 12 phases complete (133 tests, 39 suites, build + test all green). Full SwiftAgent core: types, LLM adapter, agent loop, tools, CLI/TUI, safety, config, slash commands, session/memory, MCP, sub-agents, hooks, plugins, and feature flags.
