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
| ChatCommand decomposition | Extension files (`+Type`, `+SystemPrompt`, etc.) | Keeps struct definition intact, uses module-level visibility for extension access. Reduced from 1,992→1,111 lines (-44%) |
| LineEditor decomposition | 5 independent modules (`TextBuffer`, `TerminalInput`, `EditorRenderer`, `PasteBurstDetector`, `ComposerState`) | Pure function-like subsystems with no terminal side-effects. Reduced from 1,287→461 lines (-64%) |

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
├── ChatCommand.swift         # Orchestrator: run() + ArgumentParser struct
├── ChatCommand+Types.swift   # Shared types (ExpandState, SessionState, CurrentToolTracker, etc.)
├── ChatCommand+SystemPrompt.swift  # System prompt builders (MCP, CLAUDE.md, deferred tools)
├── ChatCommand+ToolDisplay.swift   # Tool result display, Ctrl+O expand/collapse
├── ChatCommand+SessionPicker.swift # Interactive session picker menu
├── ChatCommand+UserPrompt.swift    # Interactive question prompt handler
├── TerminalRenderer.swift    # ANSI rendering (banner, spinner, left-border, panel)
├── TerminalCapability.swift  # Terminal capability detection (TTY, color, size)
├── StatusLine.swift          # Bottom-line overlay (token usage, working state)
├── LineEditor.swift          # Thin orchestrator for raw-mode editing
├── TextBuffer.swift          # Value-type text/cursor buffer with word boundaries
├── TerminalInput.swift       # Raw terminal I/O + escape sequence parser
├── EditorRenderer.swift      # Buffer-to-terminal drawing with display-width
├── ComposerState.swift       # Popup mode state machine (/ and @ completions)
├── PasteBurstDetector.swift  # Paste burst detection + placeholder substitution
├── MarkdownRenderer.swift    # Markdown → ANSI (headings, code blocks, tables)
├── InlinePopup.swift         # Popup UI rendering (menu with scroll/highlight)
├── PopupDataSource.swift     # Command + file data sources for popups
├── TerminalDisplayWidth.swift # CJK/emoji-aware terminal column width helpers
├── ColorTheme.swift          # Color theme definitions (default, monochrome)
├── DebugLogger.swift         # JSONL API request/response logging
├── CollapseDetector.swift    # Tool result collapse detection
├── ToolResultCache.swift     # Collapsed result storage for /expand
├── FileSearchIndex.swift     # git ls-files based search index for @-mentions
├── FuzzyMatcher.swift        # Fuzzy matching for popup search
├── TokenANSIRenderer.swift   # Token-level ANSI rendering
├── CodeTheme.swift           # Code syntax highlighting themes
├── ChatToolExecutionScheduler.swift  # Concurrent tool execution
├── ChatToolInputAccumulator.swift    # Streaming tool input JSON accumulator
└── ToolResultCache.swift     # Tool result caching for collapse/expand

Sources/SwiftAgentApp/            # macOS SwiftUI App (DeepSeek-powered)
├── EntryPoint.swift              # @main App entry, windows, commands, error overlay
├── Window/
│   └── MainContentView.swift     # NavigationSplitView three-pane layout
├── Sidebar/
│   ├── SidebarView.swift         # Projects, threads, settings link
│   ├── ProjectRowView.swift      # Project expandable rows
│   └── ThreadRowView.swift       # Thread selectable rows
├── Content/
│   ├── ContentView.swift         # Center pane: toolbar + messages + composer
│   ├── ComposerView.swift        # Message input (text, send, slash commands)
│   ├── MessageListView.swift     # Scrollable message list
│   ├── MessageBubbleView.swift   # Individual message bubbles
│   └── ToolCallCard.swift        # Tool call inline cards
├── RightTabs/
│   ├── RightTabsView.swift       # Multi-tab right workspace container
│   ├── RightTabsStore.swift      # Tab state management
│   ├── TabBarView.swift          # Horizontal tab bar
│   ├── TabLabel.swift            # Individual tab labels
│   ├── TabContentView.swift      # Active tab content switch
│   ├── RightTab.swift            # Tab data model
│   ├── RightTabType.swift        # Tab type enum (review/terminal/browser/files/sideChat)
│   ├── AddTabMenu.swift          # + button popover
│   ├── EmptyTabPlaceholder.swift # Empty state
│   └── panels/
│       └── ReviewPanelView.swift # Diff review panel
├── DeepSeek/
│   ├── DeepSeekClient.swift      # Streaming Chat Completions (SSE)
│   ├── DeepSeekConfig.swift      # API URL, models, key config
│   ├── DeepSeekModel.swift       # Model enum (V3, R1, CoderV2)
│   └── KeychainStore.swift       # Secure API key storage
├── LLM/
│   └── AppLLMProvider.swift      # LLM provider wrapper
├── Storage/
│   ├── StorageManager.swift      # Database lifecycle
│   ├── Database.swift            # SQLite connection
│   ├── Migrations.swift          # Schema migrations
│   ├── Models.swift              # Persisted data models
│   ├── ProjectRepository.swift   # Project CRUD
│   ├── ThreadRepository.swift    # Thread CRUD
│   └── MessageRepository.swift   # Message CRUD
├── ViewModels/
│   ├── AppViewModel.swift        # Root app state (projects, threads, API key)
│   ├── ThreadViewModel.swift     # Thread state + message sending
│   ├── ProjectViewModel.swift    # Project state
│   └── ComposerViewModel.swift   # Composer input state
├── Skills/
│   ├── SkillsView.swift          # Skills library browser
│   ├── SkillCard.swift           # Individual skill card
│   ├── SkillCreatorSheet.swift   # Skill creation wizard
│   └── SkillScope.swift          # Skill scope enum (user/project/system)
├── MCP/
│   ├── MCPConfigView.swift       # MCP servers management
│   ├── MCPConfigStore.swift      # MCP config persistence
│   ├── MCPServerCard.swift       # Server card with status
│   └── AddMCPServerSheet.swift   # Add server form
├── Worktree/
│   ├── WorktreeManager.swift     # Git worktree operations
│   └── WorktreePickerSheet.swift # Worktree picker UI
├── Appshots/
│   ├── GlobalHotkey.swift        # Cmd+Cmd listener + toast state
│   ├── AppshotCapture.swift      # Screen capture via Accessibility API
│   ├── AppshotToastView.swift    # Capture success/failure toast
│   └── AXTextExtractor.swift     # AX text extraction
├── Modals/
│   ├── PermissionModal.swift     # Sandbox permission modal
│   ├── PermissionPicker.swift    # Permission level picker
│   ├── NewProjectSheet.swift     # New project creation
│   ├── ModelPicker.swift         # Model selection sheet
│   ├── SlashCommandPalette.swift # Slash command picker
│   ├── RenameSheet.swift         # Rename thread/project
│   ├── RenameTarget.swift        # Rename target enum
│   ├── AddMenu.swift             # Composer + menu
│   └── PluginsSubmenu.swift      # Plugins submenu
├── URLHandling/
│   └── URLRouter.swift           # swiftagent:// URL routing
├── Settings/                     # Independent Settings window
│   ├── SettingsWindow.swift      # Window with sidebar + content
│   ├── personal/
│   │   ├── GeneralSettings.swift
│   │   ├── AppearanceSettings.swift
│   │   ├── ConfigurationSettings.swift
│   │   ├── PersonalizationSettings.swift
│   │   └── KeyboardShortcutsSettings.swift
│   ├── integrations/
│   │   ├── AppshotsSettings.swift
│   │   ├── MCPServersSettings.swift
│   │   ├── BrowserSettings.swift
│   │   └── ComputerUseSettings.swift
│   ├── coding/
│   │   ├── HooksSettings.swift
│   │   ├── ConnectionsSettings.swift
│   │   ├── GitSettings.swift
│   │   ├── EnvironmentsSettings.swift
│   │   └── WorktreesSettings.swift
│   └── archived/
│       └── ArchivedChatsSettings.swift
├── Animations/
│   ├── AnimationTokens.swift     # Duration/easing token definitions
│   └── ViewExtensions.swift      # Transition helpers
├── Errors/
│   ├── ErrorPresenter.swift      # 16 error states, severity classification
│   ├── ErrorBannerView.swift     # Top banner (retryable errors)
│   ├── ErrorToastView.swift      # Bottom toast (warnings)
│   └── ErrorModalView.swift      # Modal overlay (fatal errors)
├── Accessibility/
│   └── A11yExtensions.swift      # a11y labels, contrast, reduce-motion
├── Shortcuts/
│   └── ShortcutRegistry.swift    # 27+ shortcuts, single source of truth
└── DesignSystem/
    ├── Color.swift               # Design token colors (dark mode)
    ├── Typography.swift          # Font definitions
    ├── Spacing.swift             # Spacing scale
    ├── Radius.swift              # Corner radius tokens
    └── StatusDot.swift           # Status indicator component

Tests/
├── SwiftAgentCoreTests/      # Core library tests (16 suites)
├── SwiftAgentCLITests/       # Terminal rendering and input regression tests
├── SwiftAgentAppTests/       # App unit tests (8 suites)
└── SwiftAgentAppUITests/     # XCUITest suites (5 suites)
```

## App Architecture — SwiftAgentApp

The macOS app uses **MVVM** with SwiftUI, backed by SQLite persistence:

- **AppViewModel** — Root view model, owns all state (projects, threads, API key, LLM provider)
- **ThreadViewModel** — Per-thread state, message list, send/stream lifecycle
- **ProjectViewModel** — Per-project state (name, path, threads)
- **ComposerViewModel** — Input buffer state, slash command parsing

Data flows from Storage (SQLite) → AppViewModel → SwiftUI views via `@Published` / `@EnvironmentObject`.

The Settings window is an **independent NSWindow** (not in-app popup, per §17 #23), opened via `⌘,` or sidebar ⚙ link using URL scheme `swiftagent-settings://`.

## Reference Materials

- [Claude Code Source Study](~/CLI/Claude-Code-Source-Study/) — 25-chapter deep analysis
- [Claude Code System Prompts](~/CLI/claude-code-system-prompts/) — 190+ modular prompts
- [Claude Code Source](~/CLI/claude-code/) — Full TypeScript reference implementation (~512K lines)
