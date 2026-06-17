# SwiftAgent Roadmap

## Phase Progress — Core (Complete)

| Phase | Name | Status | Notes |
|---|---|---|---|
| 0 | Project Scaffolding | ✅ Done | Package.swift, docs, CI scripts |
| 1 | Core Types & Domain Model | ✅ Done | 22 type files, full CC domain model |
| 2 | LLM Adapter & Streaming | ✅ Done | LLMClient, StreamParser, RetryPolicy, ModelRegistry, TokenCounter |
| 3 | Agent Loop | ✅ Done | QueryEngine, PromptBuilder, ContextManager, ToolExecutor, StreamRenderer |
| 4 | Tool System | ✅ Done | 43 tools (Read/Write/Edit/Bash/Glob/Grep + Agent/Skill/Task*/MCP/etc.) |
| 5 | CLI & Terminal UI | ✅ Done | ChatCommand, TerminalRenderer, LineEditor (paste, multi-line, ESC cancel), MarkdownRenderer |
| 6 | Permission & Safety | ✅ Done | 10-step pipeline, AST-aware SafetyChecker, PermissionStore |
| 7 | Configuration System | ✅ Done | 5-layer ConfigLoader, ConfigSchema, APIKeyResolver |
| 8 | Slash Commands | ✅ Done | CommandRegistry with built-ins |
| 9 | Session & Memory | ✅ Done | SessionStore (JSON), MemoryStore (CLAUDE.md with frontmatter) |
| 10 | MCP Integration | ✅ Done | MCPClient, SSE/HTTP transport, tool bridge |
| 11 | Sub-Agent & Tasks | ✅ Done | SubAgentManager, TaskManager (actor), WorktreeManager |
| 12+ | Advanced Features | ✅ Done | HookSystem, PluginManager, FeatureFlags |

## Phase Progress — SwiftAgentApp (Complete)

| Phase | Name | Status | Notes |
|---|---|---|---|
| 1 | Skeleton | ✅ Done | HSplitView 3-pane (Sidebar / Content / Right), DesignSystem, Sidebar, Content, Right panel |
| 2 | DeepSeek Integration | ✅ Done | DeepSeekClient, KeychainStore, Composer 4 controls, streaming chat |
| 3 | Multi-Thread + Persistence | ✅ Done | SQLite storage, Projects, Threads, Messages, slash commands |
| 4 | Advanced Features | ✅ Done | Skills, MCP, Worktree, Appshots, 4-tier permissions, right multi-tabs |
| 5 | Polish | ✅ Done | Settings (4 cat/13 tabs), 27+ shortcuts, animations, 16 errors, a11y, UI tests |

Build: 0 errors, 0 warnings. Tests: 258 passing (Core, CLI, App).

## Current Blockers

None.

## Next Priorities

### v1.1 (Planned)

1. **Computer Use** — Agent desktop interaction (click, type, navigate apps)
2. **6 Role Plugins** — Specialized agent personas (Code Reviewer, Architect, DevOps, etc.)
3. **Face ID / Password Lock** — macOS local unlock for sensitive operations
4. **Flesh out stub features** — Voice input (^M), Browser panel (WKWebView), Terminal panel (PTY)
5. **Enhanced Appshots** — Multi-window capture, region selection

### v1.2+ (Future)

1. **Mobile Companion** — iOS companion app
2. **Remote SSH** — First-class remote execution
3. **Cloud Environments** — Managed remote sandboxes
4. **Sites Deployment** — One-click deploy to hosting

## Recently Completed

All 12 core phases + 5 app phases complete. Phase 5 (Polish) delivered:
- Settings window with 4 categories / 13 tabs
- Full keyboard shortcut table (27+ shortcuts)
- Animation system with reduce-motion support
- 16 error states (banner/toast/modal)
- Accessibility (VoiceOver labels, high contrast, dynamic type)
- XCUITest suites for core flows
- CHANGELOG.md, updated docs (CLAUDE.md, AGENTS.md, ARCHITECTURE.md, AI_HANDOFF.md, README.md)

### TUI Decomposition (June 2026)

- **ChatCommand** split into 5 extension files: `+Types`, `+SystemPrompt`, `+ToolDisplay`, `+SessionPicker`, `+UserPrompt`. Main file reduced from 1,992→1,111 lines (-44%).
- **LineEditor** decomposed into 5 independent modules: `TextBuffer` (value-type buffer), `TerminalInput` (raw I/O + escape parsing), `EditorRenderer` (terminal drawing), `PasteBurstDetector` (paste handling), `ComposerState` (popup state machine). Main file reduced from 1,287→461 lines (-64%).
- CLI directory grew from 10 files to 27 files, each with a single well-defined responsibility.
