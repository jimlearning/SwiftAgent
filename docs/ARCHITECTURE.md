# SwiftAgent Architecture

## Module Boundaries

### SwiftAgentCore (Library)
Shared, reusable agent runtime. No CLI/TUI dependencies.

**Responsibilities:**
- Domain types (Conversation, Message, Tool, Permission, Config, etc.)
- Agent loop engine (query → stream → execute → loop)
- Tool system (protocol, registry, 43 built-in tools)
- LLM adapters (Anthropic API client, streaming, retry)
- Configuration management (multi-source loading, merging)
- Permission engine (mode-based decision pipeline)
- Session and memory persistence
- MCP protocol integration
- Sub-agent and task management
- Hooks, plugins, feature flags

### SwiftAgentCLI (Executable)
Thin CLI layer. All UI/UX lives here.

**Responsibilities:**
- ArgumentParser command structure
- Terminal rendering (ANSI escape sequences, virtual buffer, diff)
- Input handling (raw mode, composer, history, slash completion)
- Permission approval UI
- Streaming output formatting and markdown rendering

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
| Async model | Swift Concurrency (async/await, actor, AsyncStream) | Natural mapping to CC's AsyncGenerator pattern |
| Tool definition | Protocol + struct conformance | Swift-native way to express CC's builder pattern |
| Prompt management | External .md files with template variables | Reuse claude-code-system-prompts directly |
| Config format | JSON (settings.json) | Compatible with existing Claude Code configs |
| Agent loop location | ChatCommand (inline), not QueryEngine | Matches CC's pattern; CLI owns the loop orchestration |
| Stream parsing | Manual SSE accumulation + contentBlockStop parse | CC pattern; avoids premature parse of partial tool input |
| Sub-agent execution | REPL wires `AgentTool` to `SubAgentManager` | Foreground sub-agents run to completion with status-line progress; background sub-agents return a `TaskOutput` task ID and store progress/final output in `TaskManager` |

## Design Conventions

1. **One tool per file** — matches CC's file organization
2. **PascalCase LLM tool names** — `"Bash"` not `"bash"`, matches CC
3. **camelCase JSON schema properties** — `"taskId"` not `"task_id"`, matches CC
4. **CC-native snake_case retained** — Edit/Write/Read tools keep `file_path`, `old_string`, `new_string`, `replace_all` (CC's own convention)
5. **Tool protocol** defined in `Types/Tool.swift`, all tools implement via struct
6. **Tool descriptions** in `description()` method (LLM-visible); `prompt()` defined on protocol, not yet wired into SystemPromptBuilder

## Detailed Module Layout

```
Sources/SwiftAgentCore/
├── Types/                    # 22 files — protocols, enums, structs
│   ├── Tool.swift            # Core Tool protocol
│   ├── Conversation.swift    # Message, Conversation models
│   ├── Config.swift          # 80+ settings fields
│   ├── Permission.swift      # Permission types and modes
│   ├── StreamEvent.swift     # SSE stream event types
│   ├── HookJSONTypes.swift   # Hook event JSON types
│   ├── MessageFactory.swift  # Message construction helpers
│   ├── Session.swift         # Session management types
│   ├── Ids.swift             # Branded IDs (SessionId, AgentId, etc.)
│   └── ...                   # Agent, AttachmentTypes, ClassifierTypes,
│                             #   CompactionTypes, InputTypes, LogEntries,
│                             #   MCPServerConfig, SDKTypes, SandboxSettings,
│                             #   SettingSource, SlashCommand, SystemMessage,
│                             #   ThinkingConfig
│
├── Tools/                    # 43 tools, one per file
│   ├── BashTool.swift        # Shell execution
│   ├── FileReadTool.swift    # File reading
│   ├── FileWriteTool.swift   # File writing
│   ├── FileEditTool.swift    # Exact string replacement
│   ├── GlobTool.swift        # Filename pattern matching
│   ├── GrepTool.swift        # ripgrep content search
│   ├── AgentTool.swift       # Sub-agent dispatch
│   ├── SkillTool.swift       # Skill invocation
│   ├── Task*Tool.swift       # Task management (Create/Get/List/Output/Stop/Update)
│   ├── TodoWriteTool.swift   # Todo list
│   ├── WebSearchTool.swift   # Web search
│   ├── WebFetchTool.swift    # Web fetch
│   ├── LSPTool.swift         # LSP code intelligence
│   └── ...                   # Cron*, MCP*, NotebookEdit, PowerShell, etc.
│
├── Agent/                    # Agent loop engine
│   ├── QueryEngine.swift     # Core query loop (streaming, batch, hooks, compaction)
│   ├── ToolExecutor.swift    # Tool execution (concurrent/streaming)
│   ├── MessageNormalizer.swift # Message normalization (9 passes)
│   ├── SystemPromptBuilder.swift # System prompt construction
│   ├── Compactor.swift       # Context compaction
│   ├── SubAgentManager.swift # Sub-agent management
│   ├── TaskManager.swift     # Background task lifecycle (actor)
│   ├── StreamRenderer.swift  # Streaming output rendering
│   ├── ContextManager.swift  # Context management
│   └── WorktreeManager.swift # Git worktree isolation
│
├── LLM/                      # LLM client layer
│   ├── LLMClient.swift       # HTTP client (auth, model normalization, fallback)
│   ├── LLMStreamParser.swift # SSE stream parser
│   ├── ModelRegistry.swift   # Model registry
│   ├── RetryPolicy.swift     # Retry policy
│   └── TokenCounter.swift    # Token counting
│
├── Safety/                   # Permission & safety
│   ├── PermissionEngine.swift # 10-step permission pipeline
│   ├── SafetyChecker.swift    # AST-aware safety checks
│   ├── PermissionStore.swift  # Permission persistence
│   └── PermissionClassifier.swift
│
├── MCP/                      # Model Context Protocol
│   ├── MCPClient.swift       # MCP client (actor)
│   ├── MCPTransport.swift    # SSE/HTTP transport
│   ├── MCPToolBridge.swift   # MCP tools → ToolDefinition bridge
│   └── MCPResourceTypes.swift
│
├── Config/                   # Configuration
│   ├── ConfigLoader.swift    # 5-layer priority merge
│   ├── ConfigSchema.swift    # Schema definition and validation
│   └── APIKeyResolver.swift  # API key resolution chain
│
├── State/                    # Application state
│   ├── AppState.swift        # Central state actor
│   └── AppStateStore.swift   # Pub/sub bridge
│
├── Features/                 # Feature flags
│   └── FeatureFlags.swift    # Runtime + compile-time toggles
│
├── Hooks/                    # Hook system
│   └── HookSystem.swift      # All CC hook event types, async execution
│
├── Commands/                 # Command system
│   └── CommandRegistry.swift # Slash command registry + alias matching
│
├── Plugins/                  # Plugin system
│   └── PluginManager.swift   # Directory scanning + manifest loading
│
├── Storage/                  # Persistence
│   ├── MemoryStore.swift     # Memory storage (YAML frontmatter parsing)
│   └── SessionStore.swift    # Session JSON persistence
│
├── Workspace/                # Workspace
│   └── ClaudeMdLoader.swift  # CLAUDE.md hierarchical loading + @include
│
├── Utilities/                # Utilities
│   └── ToolResultStorage.swift # Tool result disk persistence
│
├── CoreTypes.swift           # Core enums (ExitReason, etc.)
└── ShellResolver.swift       # Shell resolution

Sources/SwiftAgentCLI/
├── EntryPoint.swift          # Program entry point
├── ChatCommand.swift         # Main command + 43 tool registrations + inline agent loop
├── TerminalRenderer.swift    # ANSI rendering (banner, spinner, left-border, panel)
├── TerminalCapability.swift  # Terminal capability detection
├── LineEditor.swift          # Raw-mode editor (history, bracketed paste, multi-line, ESC cancel)
├── MarkdownRenderer.swift    # Markdown → ANSI (headings, code blocks, display-width-aligned tables)
├── TerminalDisplayWidth.swift # CJK/emoji-aware terminal column width helpers
├── DebugLogger.swift         # JSONL API request/response logging
├── ColorTheme.swift          # Color theme definitions
└── StreamRenderer.swift      # SSE stream event rendering

Tests/
├── SwiftAgentCoreTests/      # Core library tests
└── SwiftAgentCLITests/       # Terminal rendering and input regression tests
    └── 171 tests, 47 suites total
```

## Reference Materials

- [Claude Code Source Study](../Claude-Code-Source-Study/) — 25-chapter deep analysis
- [Claude Code System Prompts](../claude-code-system-prompts/) — 190+ modular prompts
- [Claude Code Source](../claude-code/) — Full TypeScript reference implementation (~512K lines)
