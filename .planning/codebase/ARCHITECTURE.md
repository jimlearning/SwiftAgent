<!-- refreshed: 2026-06-25 -->
# Architecture

**Analysis Date:** 2026-06-25

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         Entry Points                                     │
├──────────────────┬──────────────────┬───────────────────────────────────┤
│  SwiftAgentCLI   │  SwiftAgentApp   │     SwiftAgentCore (Library)      │
│  `Sources/       │  `Sources/       │     `Sources/SwiftAgentCore/`      │
│   SwiftAgentCLI/`│   SwiftAgentApp/`│                                    │
└────────┬─────────┴────────┬─────────┴──────────────┬────────────────────┘
         │                  │                         │
         ▼                  ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    SwiftAgentCore — Agent Runtime                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │  Types/  │ │  Tools/  │ │  Agent/  │ │  LLM/    │ │  Safety/ │     │
│  │ 22 files │ │ 60+ tools│ │ 11 files │ │ 5 files  │ │ 4 files  │     │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤     │
│  │  MCP/    │ │  Config/ │ │  State/  │ │ Storage/ │ │ Hooks/   │     │
│  │ 13 files │ │ 3 files  │ │ 2 files  │ │ 8 files  │ │ 1 file   │     │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `SwiftAgentCore` | Reusable agent runtime: types, tools, LLM adapters, permissions, MCP, hooks, plugins, persistence | `Sources/SwiftAgentCore/` |
| `SwiftAgentCLI` | Terminal-based interactive coding agent: ArgumentParser CLI, ANSI rendering, raw-mode editor, streaming output | `Sources/SwiftAgentCLI/` |
| `SwiftAgentApp` | macOS GUI app: SwiftUI MVVM, HSplitView 3-pane, NSWindow-based Settings, SQLite persistence | `Sources/SwiftAgentApp/` |
| `ClarcCore` (local pkg) | Shared app-level types: WindowState, CLISession, theme models | `Packages/Sources/ClarcCore/` |
| `ClarcChatKit` (local pkg) | Reusable chat UI components: ChatBridge, MessageBubble, ToolResultView, ThinkingBlockView, MarkdownView, InputBar | `Packages/Sources/ClarcChatKit/` |

## Pattern Overview

**Overall:** Modular monorepo with clean Core/UI separation

**Key Characteristics:**
- Core library (SwiftAgentCore) is UI-free and reusable by both CLI and App targets
- CLI owns the agent loop inline (ChatCommand orchestrator), matching Claude Code's pattern
- App uses MVVM with SwiftUI and an NSTableView-based chat renderer for performance
- Tool system uses protocol + struct conformance, one tool per file
- Actor-based state management for shared mutable state
- All Claude Code concepts (permission modes, compaction, MCP, sub-agents, hooks) modeled as Swift domain types

## Layers

### Core Types Layer
- Purpose: Domain types shared across all layers
- Location: `Sources/SwiftAgentCore/Types/` (22 files)
- Contains: Tool protocol, Conversation/Message models, Permission types, Config types, StreamEvent, Session, IDs, SlashCommand, JSONSchema, ToolUseContext, ToolOutput, and more
- Depends on: Foundation only, no internal deps
- Used by: All other Core modules, CLI, App

### Tools Layer
- Purpose: 60+ built-in tools implementing the Tool protocol
- Location: `Sources/SwiftAgentCore/Tools/` (one file per tool)
- Contains: BashTool, FileReadTool, FileWriteTool, FileEditTool, GlobTool, GrepTool, WebSearchTool, WebFetchTool, AgentTool, SkillTool, Task*Tool (6 tools), TodoWriteTool, LSPTool, Cron*Tool (3 tools), MCPTool, DynamicMCPTool, PlanMode tools, Worktree tools, and more
- Depends on: Types layer, LLM layer (for sub-agents), Safety layer
- Used by: Agent layer (via ToolRegistry)

### Agent Layer
- Purpose: Core agent loop engine
- Location: `Sources/SwiftAgentCore/Agent/` (11 files)
- Contains:
  - `QueryEngine.swift` — Main query loop: user turn -> stream -> tool exec -> loop. Mirrors CC's `query.ts` + `QueryEngine.ts`
  - `ToolExecutor.swift` — Tool execution (validation, permission check, invocation, result persistence, concurrency)
  - `MessageNormalizer.swift` — 17-pass message normalization for API submission
  - `SystemPromptBuilder.swift` — System prompt construction from modular .md templates
  - `Compactor.swift` — Context compaction when approaching token limits
  - `SubAgentManager.swift` — Sub-agent lifecycle (foreground and background)
  - `TaskManager.swift` — Background task lifecycle as `actor`
  - `StreamRenderer.swift` — Terminal streaming output formatting
  - `ContextManager.swift` — Context window management
  - `WorktreeManager.swift` — Git worktree isolation
  - `TaskProgressFormatter.swift` — Progress formatting
  - `ToolInputSummaryFormatter.swift` — Tool input summary formatting
- Depends on: Types, Tools, LLM, Safety, MCP, Hooks
- Used by: CLI (ChatCommand), App (AgentSessionManager)

### LLM Layer
- Purpose: API client for LLM providers (Anthropic Messages API)
- Location: `Sources/SwiftAgentCore/LLM/` (5 files)
- Contains:
  - `LLMClient.swift` — HTTP client (auth, model normalization, retry)
  - `LLMStreamParser.swift` — SSE stream parser (manual JSON accumulation, content block parsing)
  - `ModelRegistry.swift` — Model metadata and context window sizes
  - `RetryPolicy.swift` — Exponential backoff with jitter
  - `TokenCounter.swift` — Token estimation
  - `SortedJSON.swift` — Deterministic JSON serialization for tool input
- Depends on: Foundation, CryptoKit
- Used by: Agent layer

### Safety Layer
- Purpose: Permission decision pipeline and safety checks
- Location: `Sources/SwiftAgentCore/Safety/` (4 files)
- Contains:
  - `PermissionEngine.swift` — 10-step permission decision pipeline (mirrors CC's `hasPermissionsToUseToolInner`)
  - `SafetyChecker.swift` — AST-aware bash command safety analysis
  - `PermissionStore.swift` — Persistent permission rules
  - `PermissionClassifier.swift` — Auto-mode security classification
- Depends on: Types
- Used by: Agent layer

### MCP Layer
- Purpose: Model Context Protocol integration
- Location: `Sources/SwiftAgentCore/MCP/` (13 files)
- Contains: MCPClient (actor), MCPTransport (SSE/HTTP), MCPToolBridge (MCP tools -> ToolDefinition), MCPConnectionManager, MCPBootstrapper, MCPResourceTypes, OAuth flow (4 files), SecureStorage, MCPWebSocketTransport
- Depends on: Types, LLM
- Used by: Agent layer

### CLI Layer
- Purpose: Terminal-based user interaction
- Location: `Sources/SwiftAgentCLI/` (31 files)
- Contains: ChatCommand (orchestrator + 5 extensions), TerminalRenderer (ANSI), LineEditor (thin orchestrator), TextBuffer (value-type text/cursor), TerminalInput (raw I/O + escape sequences), EditorRenderer (buffer-to-terminal drawing), ComposerState (popup mode state machine), PasteBurstDetector, MarkdownRenderer (Markdown -> ANSI), InlinePopup, PopupDataSource, ColorTheme, DebugLogger, StatusLine, and more
- Depends on: SwiftAgentCore, ArgumentParser
- Used by: Terminal users

### App Layer
- Purpose: macOS native GUI application
- Location: `Sources/SwiftAgentApp/` (100+ files across 20+ subdirectories)
- Contains: MVVM ViewModels (AppViewModel, ThreadViewModel, ProjectViewModel), SwiftUI Views (Sidebar, Content, Window, RightTabs, Modals, Settings, DesignsSystem), Storage (SQLite), URL routing, Shortcuts, Accessibility, Animations, Errors
- Depends on: SwiftAgentCore, ClarcCore, ClarcChatKit, SwiftTerm, KeychainAccess, KeyboardShortcuts
- Used by: macOS desktop users

### Settings Layer (App)
- Purpose: Independent Settings window separate from main window
- Location: `Sources/SwiftAgentApp/Settings/` (17 files across 4 categories)
- Categories: personal (General, Appearance, Configuration, Personalization, Shortcuts), integrations (Appshots, MCP, Browser, ComputerUse), coding (Hooks, Connections, Git, Environments, Worktrees), archived (Archived Chats)
- Opened via: `⌘,` shortcut (SwiftUI native) or sidebar gear icon

## Data Flow

### Primary CLI Request Path

1. User types prompt in `LineEditor` (`Sources/SwiftAgentCLI/LineEditor.swift`) which uses `TextBuffer` + `TerminalInput` + `EditorRenderer` for raw-mode editing
2. `ChatCommand.run()` receives the prompt string
3. Builds `ToolUseContext` with session state, permission mode, working directory, available tools
4. Calls `QueryEngine.run()` (`Sources/SwiftAgentCore/Agent/QueryEngine.swift:61`) with user input, conversation, app state, and tool definitions
5. `QueryEngine` builds system prompt, constructs API request, calls `LLMClient.stream()`
6. `LLMStreamParser` processes SSE stream events: `messageStart`, `contentBlockStart`, `textDelta`, `thinkingDelta`, `inputJSONDelta`, `contentBlockStop`, `messageDelta`
7. For each `tool_use` block: `ToolExecutor.execute()` validates input, checks permissions via `PermissionEngine`, calls `tool.call()`, persists large results to disk
8. Tool results sent back to API as `tool_result` content blocks
9. Model processes results and either issues more tool calls or returns final `end_turn`
10. Loop continues until model issues `end_turn` or user presses ESC
11. `StreamRenderer` formats streaming events for terminal display

### Primary App Request Path

1. User types in `ComposerView` (`Sources/SwiftAgentApp/Content/ComposerView.swift`) with `InputBarView` from ClarcChatKit
2. `ThreadViewModel.sendMessage()` creates an `AgentMessage` with `.user` role
3. `AppAgentProvider` (wrapping `AgentSessionManager`) calls into Core's agent loop
4. Streaming events from `LLMClient` are bridged to `ChatBridge` (AppKit-SwiftUI)
5. `ChatTableView` (NSTableView) renders messages with cell reuse via `ChatTableRowView`
6. `ChatTableRowView` uses `NSStackView` to stack `ChatBlockView` instances (text, thinking, toolUse, toolResult, system)
7. Tool results are cached in `ChatFoldModel` (`FoldTarget.toolResult` keyed on `toolUseID`)
8. Conversation persisted to SQLite via `StorageManager` -> `ThreadRepository` -> `MessageRepository`

### Tool Execution Flow

1. `ToolExecutor.execute(name:input:context:onProgress:)` (`Sources/SwiftAgentCore/Agent/ToolExecutor.swift:14`)
2. Step 1: Validate input via `tool.inputSchema.validate(input)`
3. Step 2: Check permissions via `tool.checkPermissions(input:context:)` or `PermissionEngine.check()`
4. Step 3: Execute `tool.call(input:context:canUseTool:parentMessage:onProgress:)`
5. Step 4: For large results, persist to disk via `ToolResultStorage.processToolResult()` and set `persistedToDisk` flag

### MCP Bootstrap Flow

1. `MCPBootstrapper` scans `~/.claude.json`, `.mcp.json` for server configs
2. Connects to MCP servers via `MCPTransport` (SSE/HTTP or WebSocket)
3. Discovers tools from each server, wraps as `DynamicMCPTool` instances
4. Registers dynamic tools into `ToolRegistry`
5. MCP server instructions injected into cached system prompt

## State Management

- **Core state**: `AppState` actor (`Sources/SwiftAgentCore/State/AppState.swift`) — central mutable state with actor isolation
- **Core pub/sub**: `AppStateStore` (`Sources/SwiftAgentCore/State/AppStateStore.swift`) — pub/sub bridge to observers
- **App state**: `AppViewModel` (`Sources/SwiftAgentApp/ViewModels/AppViewModel.swift`) — `@MainActor` ObservableObject, owns projects, threads, layout toggles, LLM provider
- **App per-thread**: `ThreadViewModel` — Per-thread messages, send/stream lifecycle
- **CLI session**: `ChatCommand` struct — mutable session state (ExpandState, MCP clients, model reference) held inline
- **Fold state**: `FoldState` ObservableObject in `AppKitChatBridge.Coordinator` — survives thread switches
- **Right tabs**: `RightTabsStore` ObservableObject — tab open/close state

## Key Abstractions

**Tool Protocol:**
- Purpose: Core contract every tool implements — mirrors Claude Code's builder pattern
- Location: `Sources/SwiftAgentCore/Types/Tool.swift` (1,157 lines, includes protocol, defaults, JSONSchema, ToolUseContext, ToolOutput, ToolResult, and all supporting types)
- Pattern: Protocol with extensive default implementations, struct-based conformance, one tool per file

**ToolUseContext:**
- Purpose: Monolithic execution context passed to every tool — mirrors CC's ToolUseContext with 80+ fields
- Location: `Sources/SwiftAgentCore/Types/Tool.swift:547-881`
- Pattern: Value type (struct) with closures for state mutation callbacks

**Conversation/Message Model:**
- Purpose: Turn-based conversation representation matching Anthropic API structure
- Location: `Sources/SwiftAgentCore/Types/Conversation.swift`
- Pattern: `Conversation` has `[Turn]`, each `Turn` has `Message`. Tool results are inline blocks within assistant messages.

**MessageNormalizer:**
- Purpose: 17-pass message normalization before API submission
- Location: `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift`
- Pattern: Functional pipeline — each pass filters, deduplicates, merges, or sanitizes messages

## Entry Points

**CLI Entry:**
- Location: `Sources/SwiftAgentCLI/EntryPoint.swift`
- Triggers: `swift-agent` command from terminal
- Responsibilities: ArgumentParser root command (`@main`), dispatches to `ChatCommand` or `EvalCommand`

**App Entry:**
- Location: `Sources/SwiftAgentApp/EntryPoint.swift`
- Triggers: macOS app launch (Dock, Finder, Xcode Run)
- Responsibilities: `@main` SwiftUI App, creates windows, commands, error overlay, settings scene, URL handling

**ChatCommand:**
- Location: `Sources/SwiftAgentCLI/ChatCommand.swift`
- Triggers: `swift-agent chat` with optional flags
- Responsibilities: Orchestrates the full interactive agent session — API key resolution, MCP bootstrap, tool registration, system prompt build, user input loop, streaming, tool execution

**AppDelegate:**
- Location: `Sources/SwiftAgentApp/AppDelegate.swift`
- Triggers: NSApplication lifecycle
- Responsibilities: Sets activation policy to `.regular` (Dock icon, menu bar), activates frontmost window, enables termination after last window closed

## Architectural Constraints

- **Threading:** Swift Concurrency (async/await, actors). `@MainActor` for SwiftUI ViewModels. Actors for mutable shared state (`AppState`, `TaskManager`). No raw GCD or NSThread usage.
- **Global state:** `AppState` actor (`Sources/SwiftAgentCore/State/AppState.swift`) — central mutable state. `AppViewModel` (`Sources/SwiftAgentApp/ViewModels/AppViewModel.swift`) — `@MainActor` singleton ObservableObject.
- **Circular imports:** Not detected. Core has no deps on CLI or App. CLI and App both depend on Core but not on each other.
- **Sendable compliance:** All types crossing actor boundaries are `Sendable`. Closures use `@Sendable`. `ToolUseContext` is `Sendable` with closure-based state mutation.
- **Avoid NavigationSplitView for 3-pane layout:** The App uses `HSplitView` (AppKit `NSSplitView` wrapped in SwiftUI) because `NavigationSplitViewVisibility`'s 4-case enum cannot express 3 independent toggles (sidebar, content, right). Focus mode (collapse content) has no `NavigationSplitViewVisibility` equivalent.

## Error Handling

**Strategy:** Discriminated error taxonomy with severity classification

**Patterns:**
- `ErrorPresenter` (`Sources/SwiftAgentApp/Errors/ErrorPresenter.swift`) — 16 error states with severity (retryable, warning, fatal)
- Three overlay tiers: banner (top, retryable), toast (bottom, warnings), modal (center, fatal)
- Tool errors: `ToolResult(content:isError:true)` returned inline (no throws for tool failures)
- API errors: `LLMClient` handles auth errors (401 -> trigger settings) and server errors (5xx -> retry with backoff)
- Validation: `tool.inputSchema.validate(input)` returns error string before execution

## Cross-Cutting Concerns

**Logging:** Debug logging via `DebugLogger` (CLI, JSONL format to `~/.swift-agent/debug/<uuid>.txt`) and `SessionDebugLog` (Core, structured categories matching CC conventions: [API:request], [ToolExecutor], [MCP], etc.)

**Validation:** JSONSchema validation in `Tool.validateInput()` step. Message normalization in 17-pass pipeline before API submission.

**Authentication:** API key resolution chain: `--api-key` flag -> `ANTHROPIC_API_KEY` env -> `ANTHROPIC_AUTH_TOKEN` env -> macOS keychain -> `~/.claude.json` (primaryApiKey). Resolved in `APIKeyResolver` (`Sources/SwiftAgentCore/Config/APIKeyResolver.swift`).

**Configuration:** 5-layer priority merge in `ConfigLoader` (`Sources/SwiftAgentCore/Config/ConfigLoader.swift`): defaults -> global settings -> project settings -> environment vars -> CLI flags.

**Persistence:** Two systems:
- Core: File-based CC-compatible under `~/.swift-agent/` (JSONL sessions, JSON session index, JSON settings, Markdown memory) via `SwiftAgentStore` (`Sources/SwiftAgentCore/Storage/SwiftAgentStore.swift`)
- App: SQLite via `StorageManager`/`Database` (`Sources/SwiftAgentApp/Storage/`) with schema migrations

---

*Architecture analysis: 2026-06-25*
