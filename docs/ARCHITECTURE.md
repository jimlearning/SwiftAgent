# SwiftAgent Architecture

## Module Boundaries

### SwiftAgentCore (Library)
Shared, reusable agent runtime. No CLI/TUI dependencies.

**Responsibilities:**
- Domain types (Conversation, Message, Tool, Permission, Config, etc.)
- Agent loop engine (query → stream → execute → loop)
- Tool system (protocol, registry, built-in tools)
- LLM adapters (Anthropic API client, streaming, retry)
- Configuration management (multi-source loading, merging)
- Permission engine (mode-based decision pipeline)
- Session and memory persistence
- MCP protocol integration
- Sub-agent and task management

### SwiftAgentCLI (Executable)
Thin CLI layer. All UI/UX lives here.

**Responsibilities:**
- ArgumentParser command structure (chat, exec, config, etc.)
- Terminal rendering (ANSI escape sequences, virtual buffer, diff)
- Input handling (raw mode, composer, history, slash completion)
- Permission approval UI
- Streaming output formatting

## Design Principles

1. **No god files.** Decompose when a file becomes hard to reason about.
2. **Explicit types.** Prefer enums and structs over booleans and positional literals.
3. **Actor isolation.** Use Swift actors for mutable shared state.
4. **Claude Code parity.** Align naming, behavior, and boundaries with Claude Code.
5. **Testable without live models.** Mock LLM responses for unit tests.

## Key Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Terminal rendering | Custom 3-layer ANSI engine | No Swift equivalent of Ink; build tailored solution |
| Async model | Swift Concurrency (async/await, actor, AsyncStream) | Natural mapping to Claude Code's AsyncGenerator pattern |
| Tool definition | Protocol + resultBuilder DSL | Swift-native way to express builder pattern |
| Prompt management | External .md files with template variables | Reuse claude-code-system-prompts directly |
| Config format | JSON (settings.json) | Compatible with existing Claude Code configs |

## Current Module Layout (Phases 0-12 Complete)

```
Sources/SwiftAgentCore/
├── Types/          Conversation, Tool, Permission, Config, Agent, Session, Command, StreamEvent
├── State/          AppState (actor), AppStateStore (pub/sub bridge)
├── LLM/            LLMClient, LLMStreamParser, RetryPolicy, ModelRegistry, TokenCounter
├── Agent/          QueryEngine, SystemPromptBuilder, ContextManager, ToolExecutor, StreamRenderer
│                   SubAgentManager, TaskManager (actor), WorktreeManager
├── Tools/          ReadTool, WriteTool, EditTool, BashTool, GlobTool, GrepTool (all Tool)
├── Safety/         PermissionEngine (7-step), SafetyChecker, PermissionStore
├── Config/         ConfigLoader (5-layer merge), ConfigSchema (validation)
├── Commands/       CommandRegistry
├── Storage/        SessionStore (JSON), MemoryStore (CLAUDE.md)
├── MCP/            MCPClient (actor), StdioTransport (actor), MCPToolBridge
├── Hooks/          HookSystem (actor, lifecycle events)
├── Plugins/        PluginManager (actor, manifest validation)
├── Features/       FeatureFlags (compile-time + runtime)

Tests/SwiftAgentCoreTests/ + Tests/SwiftAgentCLITests/ — 171 tests, 47 suites

Sources/SwiftAgentCLI/
├── EntryPoint.swift, ChatCommand.swift
├── ColorTheme.swift, TerminalCapability.swift
├── TerminalRenderer.swift
├── LineEditor.swift (raw-mode editing, bracketed paste, multi-line, ESC cancel)
├── MarkdownRenderer.swift (ANSI markdown: headings, code blocks, display-width-aligned tables)
├── TerminalDisplayWidth.swift (CJK/emoji-aware terminal column width helpers)
├── DebugLogger.swift (JSONL API request/response logging)
├── StreamRenderer.swift
```

## Reference Materials

- [Claude Code Source Study](../Claude-Code-Source-Study/) — 25-chapter deep analysis
- [Claude Code System Prompts](../claude-code-system-prompts/) — 190+ modular prompts
- [Claude Code Source](../claude-code/) — Full TypeScript reference implementation (~512K lines)
