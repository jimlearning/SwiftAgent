# SwiftAgent Roadmap

## Phase Progress

| Phase | Name | Status | Notes |
|---|---|---|---|
| 0 | Project Scaffolding | ✅ Done | Package.swift, docs, CI scripts, build/test pass |
| 1 | Core Types & Domain Model | ✅ Done | 10 types + 18 tests passing |
| 2 | LLM Adapter & Streaming | ✅ Done | LLMClient, StreamParser, RetryPolicy, ModelRegistry, TokenCounter + 14 tests |
| 3 | Agent Loop | ✅ Done | QueryEngine, PromptBuilder, ContextManager, ToolExecutor, StreamRenderer + 15 tests |
| 4 | Tool System | ✅ Done | 6 tools (Read/Write/Edit/Bash/Glob/Grep) + 12 tests |
| 5 | CLI & Terminal UI | ✅ Done | ChatCommand, TerminalRenderer, Capability, ColorTheme, LineEditor (paste detection, multi-line, ESC cancel), MarkdownRenderer (headings, code blocks, tables, blockquotes). CLI operational. |
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

All 12 phases complete (171 tests, 47 suites, build: 0 errors + 0 warnings). Full SwiftAgent core: types, LLM adapter, agent loop, tools, CLI/TUI, safety, config, slash commands, session/memory, MCP, sub-agents, hooks, plugins, and feature flags.

### Recent CLI Enhancements
- **Paste detection**: Multi-line pastes show `[Pasted text #N +M lines]` while submitting the original pasted text
- **Multi-line input**: Option+Enter and Shift+Enter support with cursor alignment under first character
- **ESC to cancel**: Immediately stops agent processing and restores user input
- **Markdown rendering**: Headings, bold/italic, fenced code blocks (boxed), display-width-aligned tables, blockquotes, links — toggle with `--no-markdown`
- **emitBlock spacing**: Uniform single-blank-line spacing between all content blocks
- **Zero build warnings**: All ~50 compiler warnings eliminated across 14 files
