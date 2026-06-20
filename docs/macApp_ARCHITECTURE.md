# SwiftAgent macApp — Production Architecture

> **Target:** Codex macOS App parity as a production-grade agentic coding IDE for macOS.
> **Current state:** v0.5.0 (demo-level) — this document describes the **target architecture** for v1.0+.
> **Living docs:** [ARCHITECTURE.md](ARCHITECTURE.md) (module boundaries), [TUI_ARCHITECTURE.md](TUI_ARCHITECTURE.md) (CLI rendering engine), [ROADMAP.md](ROADMAP.md) (phase progress).

---

## 1. Architecture Philosophy

### 1.1. Design Axioms

| Axiom | Rationale |
|-------|-----------|
| **AppKit shell, SwiftUI content** | SwiftUI for declarative UI within `NSSplitView`/`NSTabView` containers. AppKit for window management, menu bar, custom text system, PTY. The boundary is `NSViewRepresentable` / `NSViewControllerRepresentable` for views SwiftUI can't express. |
| **Actor-isolated state, @MainActor views** | All mutable shared state lives in Swift actors or `@MainActor` ObservableObjects. No `DispatchQueue` spaghetti. The `@MainActor` constraint on all ViewModels is deliberate — UI state mutations must be synchronous to the main runloop. Background work uses `Task.detached` with actor-hop back. |
| **Core/App boundary is inviolable** | `SwiftAgentCore` has zero AppKit/SwiftUI imports. The App layer adapts Core types into ViewModels. This boundary enables: (a) CLI shares the same agent runtime, (b) headless/CI mode reuses the engine, (c) testing without UI dependencies. |
| **One ViewModel per domain concept** | Not one ViewModel per View. `ThreadViewModel` owns the full agent-loop lifecycle for one thread. `ComposerViewModel` owns the input buffer. Views read from these ViewModels via `@Published` — a View is a function of ViewModel state. |
| **Streaming is a first-class citizen** | Every byte from the LLM is an event. The UI reacts to text deltas, thinking deltas, tool-use start/complete, and turn boundaries. No buffering-to-completion. The streaming pipeline must survive backgrounding, network drops, and 10-minute tool executions. |
| **Permission is not a dialog — it's a mode** | Users set a permission posture (Ask / Approve / Full / Custom) that governs the entire session. Individual tool denials surface as inline banners, not modal interruptions. This matches how developers actually use these tools: set once, adjust rarely. |

### 1.2. What Makes This "Production Grade"

| Concern | Demo Level | Production Level |
|---------|-----------|-----------------|
| **State** | `@Published` on one ViewModel, lost on restart | Actor tree, persisted + restored, survives force-quit |
| **Error handling** | `print()` on failure | Typed error taxonomy, retry with backoff, user-visible banners with actions |
| **Streaming** | Fire-and-forget Task, UI freezes on slow network | Cancellable, resumable, backpressure-aware, progress-indicated |
| **Window management** | Single window, no state restoration | Multi-window, `NSWindowRestoration`, per-window session isolation |
| **Persistence** | SQLite with manual INSERT/UPDATE | WAL mode, migration system, FTS5 search, write-ahead log for crash safety |
| **Accessibility** | `.accessibilityLabel()` on some views | Full VoiceOver navigation tree, dynamic type, reduce motion, high contrast, keyboard-only operation |
| **Performance** | Load all messages into Array | Virtual scrolling, lazy block decoding, incremental diff updates, memory pressure handling |
| **Testing** | A few XCUITest recordings | Unit tests for every ViewModel, integration tests for streaming, snapshot tests for UI, XCUITest for critical paths |

---

## 2. Module Map

```
Sources/SwiftAgentApp/
├── EntryPoint.swift                 # @main App, Scene declarations, .commands
├── AppDelegate.swift                # NSApplicationDelegate, lifecycle, URL handling
│
├── Shell/                           # Window & workspace shell
│   ├── MainWindowController.swift   # NSWindowController — multi-window, restoration
│   ├── MainWindow.swift             # NSWindow subclass — titlebar, tabbing, size
│   ├── WorkspaceSplitView.swift     # NSSplitView wrapper — 3-pane layout
│   ├── WindowRestoration.swift      # NSWindowRestoration protocol conformance
│   └── WindowTabManager.swift       # Per-window tab state (NSWindowTabGroup)
│
├── Panes/                           # The three main panes
│   ├── Sidebar/
│   │   ├── SidebarViewController.swift      # NSViewController host for SwiftUI sidebar
│   │   ├── ProjectOutlineView.swift         # NSOutlineView-based project tree
│   │   ├── ThreadListView.swift             # SwiftUI thread list with search/filter
│   │   ├── SidebarSearchController.swift    # Quick-open-style fuzzy search
│   │   └── SidebarState.swift               # Expansion, selection, filter state
│   ├── Content/
│   │   ├── ContentViewController.swift      # Host for message list + composer
│   │   ├── MessageListView.swift            # Virtual-scrolling message list
│   │   ├── MessageBubbleView.swift          # Individual message rendering
│   │   ├── ThinkingBlockView.swift          # Expandable reasoning display
│   │   ├── ToolCallCardView.swift           # Tool execution card (collapsed/expanded)
│   │   ├── DiffPreviewView.swift            # Inline unified diff with syntax highlighting
│   │   ├── Composer/
│   │   │   ├── ComposerViewController.swift # NSTextView-backed rich composer
│   │   │   ├── ComposerTextView.swift       # NSTextView subclass — syntax-aware
│   │   │   ├── MentionCompletion.swift      # @-mention autocomplete window
│   │   │   ├── SlashCommandCompletion.swift # /-command autocomplete
│   │   │   ├── ImagePasteHandler.swift      # Clipboard image → attachment
│   │   │   ├── FileDropHandler.swift        # Drag-drop file insertion
│   │   │   └── ComposerControlsView.swift   # SwiftUI control row (model, permission, send)
│   │   └── ContextChipsView.swift           # Active context pills (files, skills, MCP)
│   └── Right/
│       ├── RightTabsViewController.swift    # NSTabViewController — tab management
│       ├── panels/
│       │   ├── Review/
│       │   │   ├── ReviewPanelView.swift    # Diff review with file list + inline preview
│       │   │   ├── DiffFileList.swift       # Changed files sidebar within review
│       │   │   ├── DiffContentView.swift    # Side-by-side or unified diff view
│       │   │   └── DiffViewModel.swift      # Git diff computation, caching
│       │   ├── Terminal/
│       │   │   ├── TerminalPanelView.swift  # SwiftUI wrapper
│       │   │   ├── PTYTerminalController.swift # PTY fork + I/O via DispatchIO
│       │   │   ├── TerminalEmulator.swift   # VT100/xterm state machine
│       │   │   └── TerminalGridView.swift   # Metal-accelerated grid renderer
│       │   ├── Browser/
│       │   │   ├── BrowserPanelView.swift   # WKWebView wrapper
│       │   │   ├── BrowserToolbar.swift     # URL bar, nav buttons, devtools toggle
│       │   │   └── BrowserViewModel.swift   # URL state, history, devtools bridge
│       │   ├── Files/
│       │   │   ├── FilesPanelView.swift     # File browser with git status overlay
│       │   │   ├── FileOutlineView.swift    # NSOutlineView — lazy directory expansion
│       │   │   ├── FileContextMenu.swift    # Right-click: open, reveal, git log, diff
│       │   │   └── FilePreviewView.swift    # QuickLook-style file preview
│       │   └── SideChat/
│       │       ├── SideChatPanelView.swift  # Independent chat in right pane
│       │       └── SideChatViewModel.swift  # Scoped conversation state
│       └── RightTabsStore.swift             # Tab state, order, persistence
│
├── Agent/                           # Agent runtime bridge
│   ├── AgentSessionManager.swift    # Subsystem bootstrap, run(), cancel()
│   ├── AppAgentProvider.swift       # LLM provider factory + model resolution
│   ├── AgentMessageAdapter.swift    # Core Message ↔ App AgentMessage conversion
│   ├── StreamingEventBus.swift      # AsyncSequence of UI events from agent loop
│   ├── PermissionUIBridge.swift     # Maps PermissionEngine requests → SwiftUI alerts
│   ├── AgentMessages.swift          # UI-layer message model (blocks, streaming state)
│   └── AgentDebugger.swift          # In-app debug panel + JSONL logging
│
├── LLM/                             # Multi-provider LLM layer
│   ├── LLMProvider.swift            # Protocol: stream(), models(), capabilities()
│   ├── AnthropicProvider.swift      # Anthropic Messages API (Claude models)
│   ├── OpenAIChatProvider.swift     # OpenAI Chat Completions (GPT, o-series)
│   ├── DeepSeekProvider.swift       # DeepSeek Chat Completions (V3, R1)
│   ├── LocalModelProvider.swift     # llama.cpp / MLX server bridge
│   ├── ProviderRegistry.swift       # Discover, validate, select providers
│   ├── ModelResolver.swift          # Model name → provider + capabilities
│   ├── StreamPipeline.swift         # SSE → StreamEvent pipeline with retry
│   └── TokenCounter.swift           # Per-model token counting (tiktoken + fallback)
│
├── Tools/                           # Tool visualization & interaction
│   ├── ToolExecutionTracker.swift   # Per-tool state: pending → running → done/error
│   ├── ToolResultRenderer.swift     # Content-type dispatch for tool output display
│   ├── ToolDiffGenerator.swift      # Computes unified diffs for Edit/Write tools
│   ├── ToolApprovalSheet.swift      # SwiftUI sheet for individual tool approval
│   └── ToolOutputTruncation.swift   # Smart truncation of massive outputs
│
├── Storage/                         # Persistence layer
│   ├── StorageManager.swift         # Database lifecycle, migrations, vacuum
│   ├── Database.swift               # SQLite connection pool (WAL mode, serialized)
│   ├── Migrations.swift             # Versioned schema migrations (forward-only)
│   ├── Models.swift                 # PersistedModel, PersistedThread, etc.
│   ├── ProjectRepository.swift      # CRUD + FTS search
│   ├── ThreadRepository.swift       # CRUD + batch operations
│   ├── MessageRepository.swift      # Block-level storage, FTS5 indexing
│   ├── ConversationExporter.swift   # Export to JSON/Markdown/PDF
│   ├── BackupManager.swift          # Automatic SQLite backup + integrity check
│   └── SpotlightIndexer.swift       # CSSearchableIndex integration
│
├── Sync/                            # Multi-device sync
│   ├── SyncEngine.swift             # iCloud + custom sync orchestration
│   ├── CloudKitStore.swift          # CKContainer-based conversation sync
│   ├── ConflictResolver.swift       # Last-write-wins + merge strategies
│   └── SyncStatusMonitor.swift      # Network availability, sync progress
│
├── Editor/                          # Code editor integration
│   ├── EditorBridge.swift           # Protocol for external editor integration
│   ├── XcodeEditorSource.swift      # Xcode editor integration via Accessibility
│   ├── VSCodeEditorSource.swift     # VS Code integration via extension
│   ├── BuiltInEditorView.swift      # Basic built-in code editor (NSTextView)
│   └── EditingSessionTracker.swift  # Tracks active editor, cursor, selection
│
├── Workspace/                       # Project workspace
│   ├── WorkspaceManager.swift       # Multi-root workspace, .swiftagent/ config
│   ├── FileWatcher.swift            # FSEvents-based file change detection
│   ├── GitService.swift             # Git operations (status, diff, log, blame)
│   ├── LSPClient.swift              # Language Server Protocol client
│   └── ProjectIndexer.swift         # Background code indexing for @-mentions
│
├── Settings/                        # Settings (4 categories × 13+ tabs)
│   ├── SettingsWindowController.swift
│   ├── SettingsState.swift          # Published settings, persistence, validation
│   ├── personal/                    # General, Appearance, Configuration, Personalization, Shortcuts
│   ├── integrations/                # Appshots, MCP, Browser, Computer Use
│   ├── coding/                      # Hooks, Connections, Git, Environments, Worktrees
│   └── archived/                    # Archived chats
│
├── Shortcuts/                       # Keyboard shortcut system
│   ├── ShortcutRegistry.swift       # Single source of truth (Command + KeyBinding)
│   ├── ShortcutRecorderView.swift   # Custom shortcut recording control
│   └── CommandPalette.swift         # ⌘⇧P-style command palette
│
├── Permissions/                     # Permission UI
│   ├── PermissionBannerView.swift   # Inline banner for denied operations
│   ├── PermissionModePicker.swift   # Quick mode switcher in composer
│   ├── PermissionRulesEditor.swift  # Custom rule editor (Settings)
│   └── PermissionAuditLog.swift     # What was allowed/denied + when
│
├── Accessibility/
│   ├── A11yExtensions.swift         # Labels, hints, values on every interactive element
│   ├── VoiceOverNavigator.swift     # Custom rotor actions for conversation navigation
│   ├── DynamicTypeObserver.swift    # Responds to content size category changes
│   └── KeyboardNavigator.swift      # Full keyboard operation (no mouse required)
│
├── Errors/
│   ├── ErrorPresenter.swift         # Centralized error state machine
│   ├── ErrorBannerView.swift        # Top-anchored retryable error banner
│   ├── ErrorToastView.swift         # Bottom-anchored transient warning
│   ├── ErrorModalView.swift         # Modal for unrecoverable errors
│   └── ErrorTaxonomy.swift          # AppError enum — every error path enumerated
│
├── Appshots/
│   ├── GlobalHotkeyManager.swift    # Cmd+Cmd listener + CGEvent tap
│   ├── AppshotCapture.swift         # Screen capture + AX text extraction
│   ├── AppshotAnnotator.swift       # Drawing tools overlay on captures
│   ├── AppshotHistoryView.swift     # Gallery of recent captures
│   └── AppshotToastView.swift       # Capture confirmation overlay
│
├── Notifications/
│   ├── NotificationManager.swift    # UNUserNotificationCenter delegate
│   ├── NotificationScheduler.swift  # Thread completion, permission requests
│   └── NotificationPreferences.swift # Granular notification settings
│
├── DesignSystem/
│   ├── Color.swift                  # Semantic color tokens (dark mode native)
│   ├── Typography.swift             # Dynamic-type-aware font definitions
│   ├── Spacing.swift                # 4pt grid spacing scale
│   ├── Radius.swift                 # Corner radius tokens
│   ├── StatusDot.swift              # Animated status indicator
│   ├── Icons.swift                  # SF Symbol catalog (which symbol for which concept)
│   └── AnimationTokens.swift        # Duration + easing presets
│
└── Utilities/
    ├── Debouncer.swift              # Typing debounce for search/filter
    ├── Throttler.swift              # Rate limiter for file watcher events
    ├── ClipboardManager.swift       # Pasteboard monitoring + image extraction
    ├── LoggingInfrastructure.swift  # OSLog integration with log levels + categories
    └── TelemetryOptIn.swift         # Anonymous usage stats (strictly opt-in)
```

---

## 3. Data Flow Architecture

### 3.1. State Hierarchy

```
                    ┌─────────────────────────────┐
                    │     AppViewModel             │
                    │  (root @MainActor state)      │
                    │                               │
                    │  • API key status             │
                    │  • Agent session bootstrap     │
                    │  • Layout toggles              │
                    │  • Projects[] + globalThreads[]│
                    │  • pendingAttachments          │
                    └──────────┬──────────────────────┘
                               │
            ┌──────────────────┼──────────────────────┐
            ▼                  ▼                       ▼
   ┌────────────────┐  ┌──────────────┐  ┌────────────────────┐
   │ ProjectViewModel│  │ThreadViewModel│  │ SettingsViewModel  │
   │ (per project)   │  │ (per thread)  │  │ (shared, 1 window) │
   │                 │  │               │  │                    │
   │ • name, path    │  │ • messages[]  │  │ • 80+ settings     │
   │ • threads[]     │  │ • state       │  │ • keychain I/O     │
   │ • isExpanded    │  │ • model       │  │ • persistence      │
   └─────────────────┘  │ • agent loop  │  └────────────────────┘
                         │ • streaming   │
                         │ • queue count │
                         └──────┬────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
          ┌──────────────┐ ┌─────────┐ ┌──────────────┐
          │ComposerVM    │ │MessageVM│ │ToolTracker   │
          │ (per thread) │ │(per msg)│ │ (per run)    │
          └──────────────┘ └─────────┘ └──────────────┘
```

### 3.2. Agent Loop Data Flow

```
User types "fix the login bug" → Enter
  │
  ▼
ComposerView.sendAction()
  ├─ ComposerViewModel.text → thread.send(userText:)
  │
  ▼
ThreadViewModel.startAgentRun()
  ├─ Append AgentMessage.user(text) to messages[]
  ├─ Append AgentMessage.assistantStreaming() placeholder
  ├─ state = .executing
  ├─ Build Conversation from messages[]
  │   └─ AgentMessageAdapter.toCoreMessages()
  │
  ▼
AgentSessionManager.run()
  ├─ Resolve working directory from Project
  ├─ Resolve model + tools from current settings
  ├─ Build system prompt (CLAUDE.md, MEMORY.md, MCP context)
  ├─ Call QueryEngine.run()
  │   │
  │   ▼  (per turn — repeats until end_turn or user cancel)
  │   ┌─────────────────────────────────────────────┐
  │   │ LLMClient.send(messages) → SSE stream       │
  │   │   ├─ textDelta          → streaming event   │
  │   │   ├─ thinkingDelta      → streaming event   │
  │   │   ├─ toolUse start/stop → tool execution    │
  │   │   └─ usage metadata     → token counters    │
  │   │                                              │
  │   │ ToolExecutor.execute()                       │
  │   │   ├─ Permission check → may suspend          │
  │   │   ├─ Run tool (Bash/Read/Edit/...)           │
  │   │   └─ ToolResult → conversation history       │
  │   └─────────────────────────────────────────────┘
  │
  ▼
StreamingEventBus (AsyncSequence)
  ├─ ThreadViewModel.handleStreamEvent()
  │   ├─ .textDelta → update message.blocks[i].text
  │   ├─ .thinkingDelta → update message.blocks[i].thinking
  │   ├─ .toolStarted → create ToolUseBlock(status: .executing)
  │   ├─ .toolCompleted → update ToolUseBlock(status: .completed/.error)
  │   └─ .turnComplete → persist intermediate state
  │
  ▼
Agent loop ends (end_turn, error, or cancel)
  ├─ ThreadViewModel.handleRunResult()
  │   ├─ Rebuild messages from completed turns
  │   ├─ Persist all messages to SQLite
  │   ├─ state = .done / .failed(msg)
  │   └─ onStreamComplete?() → refresh diff summary
  │
  ▼
UI updates reactively
  ├─ MessageListView re-renders (new messages)
  ├─ ReviewPanelView refreshes (DiffService.refresh)
  ├─ SidebarView updates thread title + time
  └─ ComposerView auto-focuses for next input
```

### 3.3. Streaming Pipeline (Production Requirements)

```
SSE bytes from network
  │
  ▼
LLMStreamParser (Core)
  ├─ Accumulate partial lines
  ├─ Parse SSE events: "data: {...}"
  ├─ Decode JSON → StreamEvent enum
  │   (textDelta | thinkingDelta | contentBlockStart | contentBlockStop |
  │    inputJSONDelta | toolUse | toolResult | error | messageDelta)
  │
  ▼
StreamPipeline (App — adds resilience)
  ├─ RetryPolicy: exponential backoff on 429/5xx
  ├─ ConnectionMonitor: NWPathMonitor for reachability
  ├─ ResumeToken: save last message ID for resume after disconnect
  └─ Backpressure: yield events at UI-friendly rate (max 60fps)
  │
  ▼
StreamingEventBus (App — fan-out)
  ├─ Published properties on ThreadViewModel (main actor)
  ├─ ToolExecutionTracker (tool-specific updates)
  ├─ DebugLogger (JSONL dump for developer)
  └─ NotificationManager (on completion)
```

---

## 4. Critical User Experience Paths

### 4.1. Composer (The Primary Interaction Surface)

The composer is the single most-touched UI element. It must feel native, responsive, and powerful.

**Rich Text Editing (NSTextView-based):**
- The current SwiftUI `TextEditor` is insufficient: no syntax highlighting, no inline completions, no @-mention chips, no image paste.
- Replace with `NSTextView` wrapped in `NSViewRepresentable`.
- `ComposerTextView` subclass adds: (a) syntax-highlighted code blocks via TextKit 2, (b) inline @-mention pill rendering via `NSTextAttachment`, (c) `/` command ghost text, (d) adaptive height (min 1 line, max 8 lines with scroll).

**@-Mention System:**
- **Files**: Triggered by `@` → fuzzy search over workspace files → insert as mention chip (resolves to full path on send).
- **Skills**: `@skill-name` → search installed skills → insert skill invocation.
- **MCP tools**: `@mcp/server/tool` → insert MCP tool call.
- **Threads**: `@thread-name` → link to another thread (for context sharing).
- Mention chips render inline as rounded pills, deletable via backspace.

**Slash Command System:**
- `/` opens a floating command palette above the composer.
- Commands: `/help`, `/clear`, `/compact`, `/model`, `/permission`, `/plan`, `/goal`, `/skills`, `/mcp`, `/status`, `/export`, `/settings`, `/debug`, `/retry`, `/fork`, `/summarize`.
- Each command has a description, argument hints, and keyboard shortcut.
- Arguments auto-complete (e.g., `/model` → shows available models with current selection).

**Image & File Paste:**
- `NSPasteboard` monitoring for image types (PNG, JPEG, HEIC).
- Paste image → auto-upload to model (if multimodal) or save to temp file and attach as `[Image: filename.png]`.
- Drag-drop files from Finder → insert as file mention chips.

**Send Behavior:**
- Enter: send immediately.
- Shift+Enter: insert newline.
- Send during agent execution: queue message (show badge count).
- Stop button (■) appears during execution → calls `thread.cancel()`.

**Composer State Machine:**
```
  idle ──┬── typing → dirty ── Enter → sending → idle
         │                      └─ Shift+Enter → dirty (append \n)
         │
         ├── / → slashCommand (palette open)
         │      └─ select → insert command text → dirty
         │      └─ dismiss → dirty (keep typed text)
         │
         ├── @ → mentionCompletion (popover open)
         │      └─ select → insert mention chip → dirty
         │      └─ dismiss → dirty
         │
         └── executing (agent running)
                ├─ Enter → queueMessage → increment queueCount
                └─ click ■ → cancel → idle
```

### 4.2. Streaming Message Display

**Per-Message State Machine:**
```
pending (placeholder)
  → streaming (partial content arriving)
    → complete (assistant finished)
    → error (stream failed)
    → cancelled (user interrupted)
```

**Block Types within a Message:**
| Block | Display |
|-------|---------|
| `text(String)` | Markdown-rendered body text |
| `thinking(String)` | Collapsed by default: "Thought for 12s ▸". Click to expand dim/italic text. |
| `toolUse(ToolUseBlock)` | Tool call card: spinner → checkmark + summary. Click to expand full input/output. |
| `toolResult(ToolResultBlock)` | Inline result or collapsed preview with line count. |
| `diff(DiffBlock)` | Unified diff with syntax highlighting, +N -M line counts. |
| `error(ErrorBlock)` | Red-bordered error card with retry/dismiss actions. |

**Streaming Performance Requirements:**
- Text deltas must render at 60fps — use `NSTextView.textStorage?.append()` with batch updates.
- Thinking deltas render dimmed and may be throttled to 15fps (they're secondary content).
- Tool call cards appear immediately on `toolStarted`, animate status change on `toolCompleted`.
- Markdown re-parsing: debounced at 200ms during streaming, full re-render on completion.
- Virtual scrolling: only render messages within ±2 screenfuls of viewport. `MessageListView` uses `LazyVStack` with explicit ID-based diffing.

### 4.3. Message List (Virtual Scrolling)

**Problem:** A 500-turn conversation with tool outputs may contain 200,000+ lines of text. Rendering all messages in a `ScrollView` → `VStack` will OOM.

**Solution:**
- `MessageListView` uses `UICollectionView`-style view recycling via `ScrollViewReader` + manual visibility tracking.
- Each message's rendered height is estimated from block count + text length, then measured on first layout.
- `MessageBubbleView` decodes blocks lazily: only decode the block types visible in the current viewport.
- Tool outputs >100 lines are collapsed by default with "Show full output (N lines)" expander.
- Message storage keeps raw text + metadata; Markdown → AttributedString conversion is cached per message ID.

### 4.4. Right Panel Tabs

The right panel is a multi-tab workspace. Tabs are created via keyboard shortcuts or the + menu.

| Tab | Shortcut | Implementation | Key UX Concern |
|-----|----------|---------------|----------------|
| **Review** | `⌃⇧G` | SwiftUI + `git diff` via `GitService` | Must update in real-time as agent edits files. Uses `FileWatcher` + debounced `git diff --stat` refresh. |
| **Terminal** | `⌃`` ` | Custom PTY + VT100 emulator + Metal grid renderer | Full terminal emulation — not `Terminal.app` embedding. Must support colors, cursor positioning, interactive TUIs. |
| **Browser** | `⌘T` | `WKWebView` with devtools bridge | Local docs browsing. URL bar, back/forward, devtools toggle. |
| **Files** | `⌘P` | `NSOutlineView` with lazy loading + `FileWatcher` for live updates | Git status overlay (modified/added/deleted icons). Right-click context menu for git operations. |
| **Side Chat** | `⌥⌘S` | Independent `ThreadViewModel` scoped to current file/selection | Parallel conversation that doesn't pollute main thread. Useful for "explain this file" questions. |

**Tab Lifecycle:**
- Tabs persist per-window, restored on relaunch.
- Maximum 10 tabs per window; opening an 11th prompts to close least-recently-used.
- Tab state (scroll position, terminal cwd, browser URL) is persisted in `UserDefaults` per-tab.

### 4.5. Diff Review Panel (Critical Path)

This is the most technically demanding panel — it must show real-time file changes with correct diff computation.

**Architecture:**
```
Agent completes a turn
  │
  ▼
ThreadViewModel.onStreamComplete()
  ├─ AppViewModel.refreshDiffSummary()
  │   └─ DiffService.refresh(for: appViewModel)
  │       ├─ Run `git diff --stat` → file list with +N -M
  │       ├─ Run `git diff --unified=3 <file>` per changed file
  │       ├─ Parse unified diff → structured DiffHunk[]
  │       ├─ Cache results in memory (invalidate on next turn)
  │       └─ Publish DiffSummary to @Published lastReviewEntries
  │
  ▼
ReviewPanelView (bound to lastReviewEntries)
  ├─ Left sidebar: file list with change counts + status icons
  ├─ Right content: selected file's diff
  │   ├─ Diff header (--- a/ +++ b/)
  │   ├─ Hunk headers (@@ -L,S +L,S @@)
  │   ├─ Added lines (green background)
  │   ├─ Removed lines (red background)
  │   └─ Context lines (unchanged)
  └─ Bottom bar: "Accept all" / "Revert all" / "Stage selected"
```

**Diff Computation Strategy:**
- Primary: `git diff` (fast, accurate, handles renames).
- Fallback (no git repo): Myers diff algorithm on before/after file contents.
- Cache invalidation: `FileWatcher` detects external writes → invalidate cache for that file.
- Large files (>10K lines): stream diff in chunks, show first 500 hunks with "Showing 500 of N changes" warning.

---

## 5. Multi-Window Architecture

### 5.1. Window Model

Each window is an independent workspace with its own state:
- Own `AppViewModel` instance (or scoped subset)
- Own project selection
- Own thread selection
- Own right-pane tab state

Windows are created via:
- `⌘N` → new window with empty state (user picks project/thread)
- `File > New Window` → same
- `Window > Duplicate` → clone current window state
- `Dock menu > New Window` → new empty window
- State restoration on relaunch → reopen all windows from last session

### 5.2. NSWindowRestoration

```swift
// Each window encodes its state for restoration:
struct WindowRestorationState: Codable {
    let windowFrame: CGRect
    let selectedProjectID: String?
    let selectedThreadID: String?
    let sidebarVisible: Bool
    let sidebarWidth: CGFloat
    let rightVisible: Bool
    let rightWidth: CGFloat
    let rightTabs: [RestoredTabState]
}

// On relaunch:
// 1. NSApplication.restoreWindow(withIdentifier:state:) is called
// 2. Decode WindowRestorationState
// 3. Create MainWindowController
// 4. Restore layout + selection + tabs
// 5. If project/thread no longer exists, show empty state
```

### 5.3. Window Tab Groups (macOS 15+)

Native `NSWindowTabGroup` support:
- `⌘T` in a window with tabs → new tab within same window
- Each tab has independent thread selection but shares the window's project
- Tab title = thread title
- Tear-off: drag tab out → becomes independent window

---

## 6. Persistence Layer

### 6.1. SQLite Schema (Target)

```sql
-- Projects
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    metadata TEXT  -- JSON blob: custom settings, excluded paths
);

-- Threads
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    title TEXT NOT NULL DEFAULT 'Untitled',
    state TEXT NOT NULL DEFAULT 'idle',
    mode TEXT NOT NULL DEFAULT 'code',
    sandbox_mode TEXT NOT NULL DEFAULT 'workspace-write',
    execution_env TEXT NOT NULL DEFAULT 'local',
    model TEXT NOT NULL,
    system_prompt_hash TEXT,     -- detect prompt changes
    token_usage_in INTEGER DEFAULT 0,
    token_usage_out INTEGER DEFAULT 0,
    turn_count INTEGER DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    archived_at REAL             -- NULL = active
);
CREATE INDEX idx_threads_project ON threads(project_id);
CREATE INDEX idx_threads_updated ON threads(updated_at DESC);
CREATE INDEX idx_threads_archived ON threads(archived_at);

-- Messages (block-level storage)
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    role TEXT NOT NULL,           -- 'user', 'assistant', 'system'
    turn_index INTEGER,           -- which agent turn (NULL for user)
    blocks_json TEXT NOT NULL,    -- JSON array of ContentBlock
    token_usage_in INTEGER,
    token_usage_out INTEGER,
    created_at REAL NOT NULL
);
CREATE INDEX idx_messages_thread ON messages(thread_id, created_at);
CREATE INDEX idx_messages_role ON messages(thread_id, role);

-- FTS5 for full-text search across all messages
CREATE VIRTUAL TABLE messages_fts USING fts5(
    thread_id, content, tokenize='porter unicode61'
);

-- Attachments (images, files)
CREATE TABLE attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    storage_path TEXT NOT NULL,   -- relative to app container
    thumbnail_path TEXT,          -- for images
    created_at REAL NOT NULL
);

-- Settings (key-value with type)
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);

-- Permissions (user decisions)
CREATE TABLE permissions (
    id TEXT PRIMARY KEY,
    rule_type TEXT NOT NULL,      -- 'tool', 'path', 'domain', 'command'
    pattern TEXT NOT NULL,        -- tool name, file glob, domain pattern
    decision TEXT NOT NULL,       -- 'allow', 'deny', 'ask'
    scope TEXT NOT NULL DEFAULT 'session',  -- 'session', 'project', 'global'
    created_at REAL NOT NULL
);

-- Sync metadata
CREATE TABLE sync_metadata (
    entity_type TEXT NOT NULL,    -- 'thread', 'message', 'setting'
    entity_id TEXT NOT NULL,
    cloudkit_record_id TEXT,
    last_modified REAL NOT NULL,
    last_synced REAL,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    PRIMARY KEY (entity_type, entity_id)
);
```

### 6.2. Migration Strategy

- Forward-only, versioned migrations.
- `Migrations.swift` contains an ordered array of `Migration` structs.
- Each migration: `version: Int, up: (Database) throws -> Void`.
- Migrations run in a transaction. Failure → rollback, log error, alert user.
- Automatic backup before migration: copy database file to `~/Library/Application Support/SwiftAgent/Backups/`.

### 6.3. Performance

- WAL mode (default): concurrent reads during writes.
- `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`
- `PRAGMA cache_size=-8000;` (8MB page cache).
- Message blocks stored as single JSON blob per message (not one row per block) to minimize row count.
- FTS5 content synchronized via triggers on messages table.
- Periodic `PRAGMA optimize;` on app backgrounding.
- Automatic VACUUM when free pages exceed 50MB.

---

## 7. Permission & Safety Architecture

### 7.1. Permission Modes

| Mode | Behavior |
|------|----------|
| **Ask for Approval** | Every tool invocation pauses and shows a permission dialog. User can Allow Always / Allow Once / Deny. |
| **Approve for Me** | Tools run automatically, but a summary banner appears after execution. Denials surface inline. |
| **Full Access** | No interruptions. All tools run. Review panel shows what happened. |
| **Custom** | Per-tool, per-path, per-domain rules. Configured in Settings → Permissions. |

### 7.2. Permission Pipeline (Bridged from Core)

```
ToolExecutor.execute(tool, input)
  │
  ▼
PermissionEngine.evaluate(tool, input, mode)
  ├─ checkDenyList(tool) → block immediately
  ├─ checkAllowList(tool) → allow immediately
  ├─ checkCustomRules(tool, input) → match against user rules
  ├─ checkASTSafety(input) → detect dangerous patterns
  │   ├─ rm -rf / → block
  │   ├─ curl | bash → warn
  │   └─ git push --force origin main → warn
  ├─ evaluateMode:
  │   ├─ .fullAccess → allow
  │   ├─ .approveForMe → allow with banner
  │   ├─ .askForApproval → prompt user
  │   └─ .custom → apply matched rule
  │
  ▼
PermissionUIBridge.prompt(tool, message)
  │
  ▼ (if mode == .askForApproval)
PermissionUIBridge.pendingPermission published
  → SwiftUI alert or inline banner
  → User taps Allow / Deny / Always Allow
  → continuation.resume(returning: .allow / .deny)
```

### 7.3. Permission UI

- **Not a modal dialog.** Modal permission dialogs break flow for developers who type fast and use the keyboard.
- **Inline banner** below the composer: "Bash would like to run `npm install`. [Allow] [Deny] [Always allow npm]".
- **Keyboard operable:** Tab to select button, Space/Enter to activate. ESC = Deny.
- **Audit trail:** All permission decisions logged to `~/.swiftagent/permissions.log` and visible in Settings → Permissions → Audit Log.

---

## 8. LLM Provider Architecture

### 8.1. Multi-Provider Abstraction

```swift
protocol LLMProvider {
    var providerID: String { get }           // "anthropic", "openai", "deepseek"
    var displayName: String { get }          // "Anthropic", "OpenAI", "DeepSeek"
    var availableModels: [ModelInfo] { get } // dynamic model list
    var capabilities: ProviderCapabilities { get }

    func stream(
        messages: [Message],
        model: String,
        tools: [ToolDefinition],
        systemPrompt: String,
        temperature: Double?
    ) -> AsyncThrowingStream<StreamEvent, Error>

    func countTokens(_ text: String, model: String) -> Int
}

struct ProviderCapabilities {
    let supportsThinking: Bool         // extended reasoning
    let supportsVision: Bool           // image input
    let supportsTools: Bool            // native tool use
    let supportsCaching: Bool          // prompt caching
    let supportsStreaming: Bool        // SSE
    let maxContextWindow: Int          // token limit
    let maxOutputTokens: Int
}
```

### 8.2. Provider Registry

- Providers registered at startup via `ProviderRegistry`.
- Built-in providers: Anthropic (Claude), OpenAI (GPT, o-series), DeepSeek (V3, R1).
- Local providers: llama.cpp server, MLX server, Ollama — discovered via localhost port scan or manual URL entry.
- API keys stored in Keychain, per-provider.
- Model switching mid-conversation: allowed but warns if context window differs significantly.

### 8.3. API Key Management

- Stored in macOS Keychain with `kSecAttrService = "com.swiftagent.api"`.
- `kSecAttrAccount` = provider ID.
- `kSecAttrLabel` = user-visible name.
- Keychain access is prompted on first use (macOS entitlement).
- Keys can be imported from environment variables, `~/.claude.json`, or manual entry.

---

## 9. Tool Execution & Visualization

### 9.1. Tool Execution Tracking

```swift
@MainActor
final class ToolExecutionTracker: ObservableObject {
    struct RunningTool: Identifiable {
        let id: String          // toolUseID
        let name: String        // "Bash", "Read", "Edit"
        let summary: String     // "npm install react" or "src/App.tsx:42-45"
        let startTime: Date
        var status: ToolStatus  // .running, .completed, .error(String)
        let isCollapsible: Bool // true for Read/Glob/Grep
    }

    @Published var runningTools: [RunningTool] = []
    @Published var collapsedGroups: [CollapsedToolGroup] = []

    // Computed display for status bar:
    // 1 tool: "Running Bash → npm install"
    // 2-3: "3 tools running | Bash; Read; Grep"
    // 4+: "5 tools running | Bash; Read +3 more"
    var statusLine: String { ... }
}
```

### 9.2. Tool Result Rendering

Tool output is content-type dispatched:

| Output Type | Detection | Display |
|-------------|-----------|---------|
| Short text (<200 lines) | Line count | Inline code block with syntax highlighting |
| Long text (>200 lines) | Line count | Collapsed preview: "Output: 1,247 lines (3.2MB) ▸ Show" |
| Diff output | Starts with `diff --git` or `--- a/` `+++ b/` | Unified diff view with syntax highlighting |
| File tree | Lines matching `├──` or `│   ` pattern | Formatted tree view |
| JSON | Valid JSON parseable | Collapsible JSON tree (like browser devtools) |
| Error | Non-zero exit code or stderr content | Red-bordered error card with stderr |
| Image | Binary data with image magic bytes | Inline image preview (if multimodal model used) |
| Empty | Zero-length output | Gray "(no output)" text |

### 9.3. Tool Approval UI

For modes that require approval, the approval sheet is NOT a blocking `NSAlert`:

```
┌──────────────────────────────────────────────────────────────┐
│  ⚡ Bash wants to execute a command                           │
│                                                              │
│  $ npm install react react-dom                               │
│                                                              │
│  Working directory: /Users/jim/my-project                    │
│  Estimated duration: < 30s                                   │
│                                                              │
│  [Always allow npm]   [Allow once]   [Deny]   [View diff]   │
└──────────────────────────────────────────────────────────────┘
```

- Presented as a SwiftUI sheet or inline banner below the composer.
- Keyboard: Tab navigates, Space/Enter confirms.
- ESC or ⌘. = Deny.
- "Always allow" creates a persistent permission rule.

---

## 10. Terminal Panel (Production PTY)

The right-pane Terminal tab must be a real terminal emulator, not `Terminal.app` embedded via `NSWorkspace`. Embedding a second Terminal.app has security boundaries, is visually jarring, and can't share state.

### 10.1. PTY Architecture

```
RightTabsViewController
  └─ TerminalPanelView (SwiftUI)
       └─ PTYTerminalController (AppKit controller)
            ├─ fork() + exec() child process (user's shell)
            ├─ PTY master FD → DispatchIO channel (read)
            ├─ DispatchIO channel (write) → PTY master FD
            │
            ▼
       TerminalEmulator (VT100/xterm state machine)
            ├─ Parse escape sequences: CSI, OSC, DCS, APC
            ├─ Maintain cursor position, scroll region, character attributes
            ├─ Support: 256-color, true color, mouse (SGR), bracketed paste
            │   kitty keyboard protocol, synchronized output
            │
            ▼
       TerminalGridView (Metal-accelerated grid renderer)
            ├─ 2D character grid (rows × cols)
            ├─ Metal shader for glyph rendering (GPU-accelerated)
            ├─ Cell attributes: foreground, background, bold, italic, underline
            ├─ Damage tracking: only redraw changed cells
            └─ Cursor blink via CADisplayLink
```

### 10.2. Design Decisions

- **Custom emulator, not libvterm.** libvterm is C, has memory management challenges in Swift. Writing a VT100 parser in Swift is ~1500 lines and gives full control over performance and integration.
- **Metal rendering, not NSTextView.** NSTextView cannot handle terminal throughput (100K+ updates/sec during `find .`). A Metal grid renderer can display millions of cells at 60fps.
- **Damage tracking.** Only transmit changed cells to GPU. Unchanged regions reuse the previous frame's texture.
- **Synchronized output (DECSET 2026).** Batch terminal updates to eliminate visual tearing during rapid output.
- **Shell integration.** Inject shell hooks via `PROMPT_COMMAND`/`precmd` to track working directory and command start/end. Enables: "Re-run in terminal" from chat, working directory sync between agent and terminal.

### 10.3. Fallback

If Metal is unavailable (VM, old hardware): fall back to `NSTextView`-based renderer with throttled updates.

---

## 11. File Watcher & Git Integration

### 11.1. FileWatching

- Uses `FSEvents` API (not polling).
- One `FSEventStream` per project root.
- Debounced at 200ms: batch multiple filesystem events, then fire once.
- Event types tracked: Created, Modified, Removed, Renamed.
- On change: invalidate relevant caches (diff cache, file tree node, syntax highlighting).

### 11.2. Git Service

```swift
protocol GitServiceProtocol {
    func status() async throws -> GitStatus          // git status --porcelain
    func diff(file: String) async throws -> String   // git diff --unified=3
    func diffStat() async throws -> [DiffStatEntry]  // git diff --stat
    func log(file: String, limit: Int) async throws -> [GitCommit]
    func blame(file: String, line: Int) async throws -> GitBlame
    func branches() async throws -> [GitBranch]
    func currentBranch() async throws -> String
}

// Implementation wraps /usr/bin/git via Process()
// 5-second timeout on all git operations
// Results cached with TTL: status = 2s, diff = until next edit, log = 30s
```

- `GitService` runs on a background actor (not `@MainActor`).
- Results are published via `@Published` on `ProjectViewModel`.
- `FileWatcher` → git status cache invalidation → UI refresh.

---

## 12. Search Architecture

### 12.1. Full-Text Search (FTS5)

```
Search query: "fix login bug"
  │
  ▼
FTS5 search on messages_fts
  ├─ Match messages containing "fix", "login", "bug"
  ├─ Sort by thread, then chronologically
  ├─ Return: [(threadId, threadTitle, messageId, snippet, rank)]
  │
  ▼
SearchResultsView
  ├─ Group by thread
  ├─ Show snippet with highlighted matches
  ├─ Click result → navigate to that message in the thread
  └─ ⌘F in thread → filter to search-within-thread mode
```

### 12.2. Quick Open (⌘⇧O)

Command-palette-style fuzzy search:
- Files in workspace (via `git ls-files` + fuzzy match)
- Threads (by title)
- Settings pages
- Slash commands
- Recent agent actions

### 12.3. Spotlight Integration

`CSSearchableIndex` indexes:
- Thread titles and summaries
- Key decisions/outcomes (extracted from `/goal` completions)
- File edits (thread + file + timestamp)

User can search from macOS Spotlight: "login fix" → opens SwiftAgent to that thread.

---

## 13. Accessibility (Production Grade)

### 13.1. VoiceOver

Every interactive element must have:
- `.accessibilityLabel(_:)` — what this element is
- `.accessibilityHint(_:)` — what happens when activated
- `.accessibilityValue(_:)` — current state (for toggles, pickers)
- `.accessibilityAction(named:)` — custom actions beyond tap

**Conversation-specific VoiceOver support:**
- Custom rotor actions: "Next Message", "Previous Message", "Next Tool Call", "Copy Code Block"
- Message role announcements: "User message: How do I..." / "Assistant message: Here's how..."
- Thinking block: "Thought for 12 seconds — expanded" / "Thought for 12 seconds — collapsed, double-tap to expand"
- Tool call: "Bash tool running: npm install. Double-tap for details"
- Streaming: announce "Response streaming" once, then silence during text deltas (avoid verbosity). Announce "Response complete" on end.

### 13.2. Dynamic Type

- All fonts use `.font(.body)` / `.font(.headline)` etc., not fixed point sizes.
- Layout adapts to accessibility text sizes (up to `XXXLarge`).
- Sidebar minimum width increases proportionally with text size.
- Composer height scales with text size.

### 13.3. Reduce Motion

- `.animation(..., value:)` guarded by `@Environment(\.accessibilityReduceMotion)`.
- When reduce motion is on: no layout animations, instant transitions.
- Spinner uses static "..." instead of animated braille characters.

### 13.4. Keyboard-Only Operation

- Full keyboard navigation: Tab/Shift+Tab, arrow keys, Space/Enter to activate.
- ⌘F for search, ⌘⇧F for global search.
- ⌘⇧O for quick open.
- All toolbar buttons accessible via keyboard shortcuts.
- Composer: always focusable, Enter to send, Shift+Enter for newline.
- Permission prompts: Tab to navigate buttons, Space/Enter to select.

---

## 14. Error Handling Strategy

### 14.1. Error Taxonomy

```swift
enum AppError: Error, Identifiable {
    // Network (retryable)
    case networkTimeout
    case networkDisconnected
    case networkProxy(String)

    // API (some retryable)
    case rateLimited429(retryAfter: Int?)
    case serverError5xx(status: Int)
    case invalidAPIKey401
    case lowBalance402
    case modelOverloaded

    // Permission
    case sandboxDenied(tool: String, path: String)
    case permissionRequired(tool: String)

    // Data
    case databaseCorrupted
    case migrationFailed(version: Int, reason: String)
    case threadNotFound(id: String)
    case projectNotFound(id: String)

    // External
    case worktreeConflict(branch: String)
    case diffMergeFailed(file: String)
    case mcpDisconnected(server: String)
    case skillLoadFailed(name: String, reason: String)

    // System
    case appshotPermissionDenied
    case appshotCaptureFailed(reason: String)
    case keychainAccessDenied
    case diskSpaceLow(availableBytes: Int64)
}
```

### 14.2. Error Presentation Strategy

| Severity | UI | Example |
|----------|----|---------|
| **Retryable** | Top banner with action button. Auto-dismiss after 8s if not interacted. | "Network timeout — [Retry]" / "Rate limited — retrying in 12s" |
| **Warning** | Bottom toast. Auto-dismiss after 5s. | "MCP server 'filesystem' disconnected — reconnecting" |
| **Fatal** | Modal overlay with explanation + action. Cannot dismiss without action. | "Database corrupted — [Restore from backup] [Quit]" |
| **Inline** | Red text inside the relevant component. | Permission denied inline on a tool call card |

### 14.3. Recovery Strategies

- **Network errors:** Exponential backoff retry (1s, 2s, 4s, 8s, 16s, then give up).
- **Rate limit (429):** Honor `Retry-After` header. Display countdown timer.
- **Stream disconnect:** Save last received message ID. Offer "Resume" button that reconnects and continues from last checkpoint.
- **Database corruption:** Automatic integrity check on launch. If corrupt: offer restore from latest automatic backup.
- **Tool execution failure:** Show error on tool card, continue agent loop. Agent can decide to retry or take alternative approach.

---

## 15. Notifications

### 15.1. User-Visible Notifications

| Event | Notification |
|-------|-------------|
| Agent turn complete | "Agent finished — 3 files changed" with action to show diff |
| Permission required (when app is backgrounded) | "Bash wants to run a command — tap to review" |
| Long-running tool completes | "npm install finished (took 2m 15s)" |
| Rate limit approaching | "API usage at 80% of limit" |

### 15.2. Notification Preferences

Settings → Notifications lets users toggle:
- Notify on completion (on/off)
- Notify on permission required (on/off)
- Notify on long runs > N seconds (slider: 30s / 1m / 5m / never)
- Quiet mode: suppress all notifications for N minutes / until tomorrow
- Per-project notification overrides

---

## 16. Performance Budget

| Metric | Target | Measurement |
|--------|--------|-------------|
| App launch (cold) | < 1.5s to interactive | `NSApplicationDidFinishLaunching` → first frame of UI |
| App launch (warm, from Dock) | < 0.5s | Same |
| Window open | < 200ms | `window.makeKeyAndOrderFront()` → first frame |
| Thread switch | < 100ms | Click thread → messages visible |
| Message send → first token | < 500ms (excluding LLM latency) | Enter → textDelta |
| Text delta → UI update | < 16ms (60fps) | textDelta event → rendered character |
| Tool start → card visible | < 50ms | toolStarted event → ToolCallCard appears |
| Message list scroll (500 messages) | 60fps sustained | FPS during fast scroll |
| Memory: idle | < 150MB | `NSProcessInfo.physicalMemory` delta |
| Memory: 200-turn conversation | < 400MB | Same, after loading full conversation |
| SQLite query (thread list) | < 5ms | `CFAbsoluteTime` around query |
| FTS5 search (100K messages) | < 50ms | Same |

---

## 17. Testing Strategy

### 17.1. Test Pyramid

```
            ┌──────┐
            │ UITest│  5% — XCUITest for critical paths (send message, open settings,
            │       │       switch threads, create project, diff review)
            ├──────┤
            │Integra│ 15% — Streaming pipeline, persistence round-trip,
            │ tion  │       permission flow, multi-window state
            ├──────┤
            │ View  │ 30% — ViewModel state transitions, message rendering,
            │ Model │       tool tracking, error handling, search
            ├──────┤
            │  Unit │ 50% — Individual types, adapters, parsers, formatters,
            │       │       diff computation, VT100 parser, FTS tokenizer
            └──────┘
```

### 17.2. Key Test Suites (Target)

| Suite | What it tests | Count |
|-------|---------------|-------|
| `MessageAdapterTests` | Core Message ↔ App AgentMessage round-trip | 20+ |
| `StreamingEventBusTests` | Event delivery order, backpressure, cancellation | 15+ |
| `ThreadViewModelTests` | State machine: idle→executing→done, error, cancel, queue | 25+ |
| `ComposerViewModelTests` | Text manipulation, mention parsing, slash detection | 20+ |
| `PermissionUIBridgeTests` | Mode resolution, custom rules, audit trail | 15+ |
| `DiffServiceTests` | Git diff parsing, Myers fallback, caching | 20+ |
| `VT100ParserTests` | Escape sequence parsing, cursor positioning, scroll regions | 30+ |
| `TerminalEmulatorTests` | Full terminal state machine (DEC STD 070 sequences) | 40+ |
| `StorageTests` | CRUD, migrations, FTS search, backup/restore | 30+ |
| `SyncEngineTests` | Conflict resolution, CloudKit record mapping | 20+ |
| `AccessibilityTests` | Labels present, rotor actions, dynamic type layout | 15+ |
| `PersistenceRoundTripTests` | Write conversation → restart → read back → matches | 10+ |
| `MultiWindowTests` | Two windows, independent state, no cross-talk | 10+ |
| `XCUITestCriticalPaths` | Send message, see response, open review, switch thread | 15+ |

---

## 18. Implementation Phasing

### Phase 1: Foundation Upgrade (The Skeleton)

**Objective:** Replace demo-level components with production foundations. The app should still work end-to-end, but each subsystem is now built on the right architecture.

| # | Task | Why |
|---|------|-----|
| 1.1 | Multi-provider LLM layer (`LLMProvider` protocol + Anthropic/OpenAI/DeepSeek providers) | Decouple from DeepSeek-only; enable Claude and GPT |
| 1.2 | `AgentSessionManager` refactor with proper error propagation and cancellation | Current bootstrap is fragile; errors are `print()` |
| 1.3 | Message persistence with FTS5 + WAL mode optimizations | Current storage works but has no search and may corrupt on crash |
| 1.4 | `Migration` system (versioned, forward-only, transactional) | Schema will evolve; need safe migration path |
| 1.5 | `AppError` taxonomy + `ErrorPresenter` state machine upgrade | 16 errors exist but coverage is incomplete |
| 1.6 | Proper `NSTextView`-based `ComposerTextView` replacing SwiftUI `TextEditor` | Unlocks @-mentions, image paste, syntax highlighting |

### Phase 2: Core UX (Where Users Live)

**Objective:** The primary interaction loop (composer → message list → tool cards → diff review) becomes production-quality.

| # | Task | Why |
|---|------|-----|
| 2.1 | @-Mention system (files, skills, MCP tools, threads) | Power user feature; differentiates from basic chat |
| 2.2 | Slash command palette with argument completion | Discoverability; matches Codex/CC expectations |
| 2.3 | Virtual-scrolling `MessageListView` | Conversations grow large; current ScrollView won't scale |
| 2.4 | Thinking block expand/collapse with dim rendering | Reasoning models (R1, o-series) output long thinking chains |
| 2.5 | Tool call cards: progress animation, expand/collapse, diff preview | Current cards are static; need live progress |
| 2.6 | `DiffService` with git-diff integration and caching | Review panel is the #1 differentiator for coding agents |
| 2.7 | `ReviewPanelView` with file list + unified diff + accept/revert | Same as above |

### Phase 3: Right Panel Production

**Objective:** The right panel tabs become real tools, not placeholders.

| # | Task | Why |
|---|------|-----|
| 3.1 | PTY terminal with VT100 emulator + Metal grid renderer | Terminal is essential for dev workflow; embedding Terminal.app is wrong |
| 3.2 | `FileWatcher` (FSEvents) + live file tree with git status | Current FilesPanelView is static; needs live updates |
| 3.3 | File context menu (open in editor, reveal in Finder, git log, diff) | Right-click actions expected by developers |
| 3.4 | `BrowserPanelView` with WKWebView + URL bar + devtools | Local docs, API references, deployed app preview |
| 3.5 | `SideChatPanelView` with scoped conversation (current file context) | "Explain this file" without polluting main thread |

### Phase 4: Multi-Window & Persistence

**Objective:** Professional app behavior — windows, restoration, search, and sync.

| # | Task | Why |
|---|------|-----|
| 4.1 | `MainWindowController` with NSWindowRestoration | State lost on restart is amateur |
| 4.2 | Multi-window support (independent workspaces) | Power users work on multiple projects simultaneously |
| 4.3 | FTS5 full-text search with results UI | "Where did I discuss the login bug?" |
| 4.4 | Quick Open palette (⌘⇧O) with fuzzy file/thread/settings search | Fast navigation; matches VS Code/Xcode expectations |
| 4.5 | Spotlight indexing (`CSSearchableIndex`) | macOS-native; conversations findable from system Spotlight |
| 4.6 | Conversation export (JSON, Markdown, PDF) | Sharing, compliance, backup |

### Phase 5: Polish & Hardening

**Objective:** Accessibility, performance, reliability, and visual refinement.

| # | Task | Why |
|---|------|-----|
| 5.1 | Full VoiceOver support with custom rotors | Required for accessibility certification |
| 5.2 | Dynamic type + reduce motion + high contrast | Required for accessibility certification |
| 5.3 | Keyboard-only operation audit (every action reachable) | Power users; accessibility |
| 5.4 | Performance profiling: Instruments (Allocations, Time Profiler, Metal) | Hit the performance budget targets |
| 5.5 | Memory pressure handling (`NSNotification.Name.DidReceiveMemoryWarning`) | Long-running agent sessions can consume memory |
| 5.6 | Crash recovery: restore unsent composer text, re-open last thread | Data loss prevention |
| 5.7 | Animation audit: timing, easing, reduced-motion compatibility | Visual polish |
| 5.8 | Error recovery for all 16 `AppError` cases | Current error handling is partial |

### Phase 6: Advanced Features

| # | Task | Why |
|---|------|-----|
| 6.1 | iCloud sync for conversations and settings | Multi-device users |
| 6.2 | Custom shortcut recorder (editable key bindings) | Power user customization |
| 6.3 | Computer Use (agent controls macOS apps via Accessibility API) | Unique macOS advantage over web-based agents |
| 6.4 | Voice input (microphone → Whisper → composer text) | Alternative input modality |
| 6.5 | LSP integration (code intelligence: jump-to-def, references, diagnostics) | Real IDE features within agent context |
| 6.6 | Plugin/extension API for third-party tool and provider extensions | Ecosystem growth |

---

## 19. Risk Register

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **SwiftUI immaturity for complex text editing** | High | Use `NSTextView` via `NSViewRepresentable` for composer. SwiftUI for surrounding chrome only. |
| **Terminal emulator complexity** | High | VT100 subset first (80% of real-world usage). Fall back to `NSTextView`-based renderer if Metal unavailable. |
| **LLM provider API instability** | Medium | `LLMProvider` protocol isolates provider-specific code. Each provider in its own file. Version-pinned API endpoints. |
| **SQLite corruption on force-quit** | Medium | WAL mode + automatic integrity check + backup + recovery flow. |
| **Memory growth during long conversations** | Medium | Compaction in Core already handles this. App layer adds: lazy block decoding, virtual scrolling, memory pressure response. |
| **Permission bypass via tool chaining** | High | AST-aware safety checker in Core. App layer adds: audit logging, suspicious pattern detection, rate limiting on dangerous tools. |
| **Streaming disconnect without recovery** | Medium | `ResumeToken` in `StreamPipeline`. Connection monitor via `NWPathMonitor`. Auto-retry with exponential backoff. |
| **Multi-window state corruption** | Low | Actor-isolated state per window. Each window has independent `AppViewModel` or scoped state slice. |
| **accessibility rot** | Medium | Accessibility audit as a CI gate. `A11yExtensions` provides lintable API surface. XCUITest with accessibility inspector. |

---

## 20. Key Design Decisions (Living)

| # | Decision | Rationale | Revisit When |
|---|----------|-----------|-------------|
| 1 | AppKit shell with SwiftUI content, not pure SwiftUI | SwiftUI cannot express: custom text system (composer), PTY terminal, Metal rendering, `NSOutlineView` lazy loading, window tab groups, `NSWindowRestoration` | SwiftUI 7+ gains these capabilities |
| 2 | `@MainActor` on all ViewModels | UI state mutations must be synchronous. Background work uses detached tasks with actor-hop. Simpler than ad-hoc queue management. | Performance profiling shows main thread contention |
| 3 | Custom VT100 emulator, not libvterm | libvterm is C, has memory management friction in Swift. VT100 parser is ~1500 lines of well-understood state machine code. | libvterm gets official Swift bindings |
| 4 | SQLite with FTS5, not Core Data | Core Data's performance profile degrades with large text blobs. SQLite gives direct control over WAL, FTS, and migrations. | Core Data gains first-class FTS support |
| 5 | Metal terminal rendering, not NSTextView | NSTextView cannot handle terminal throughput (100K+ char/sec). Metal grid renderer is 10-100x faster for this use case. | NSTextView gains GPU acceleration |
| 6 | Single `AppViewModel` per window, not global singleton | Multi-window requires independent state. Each window has its own project/thread selection. | Only single-window use case matters |
| 7 | `LLMProvider` protocol with per-provider implementations | Decouples model access from UI. Enables local models, custom endpoints. | All providers converge on OpenAI-compatible API |
| 8 | Forward-only SQLite migrations | Rollback is rarely tested and often fails. Forward-only with pre-migration backup is safer. | Need to support downgrade after failed upgrade |
| 9 | Permission as a mode, not per-action dialog | Modal dialogs break developer flow. Mode-based permission with inline approvals respects the user's established trust posture. | User research shows preference for per-action dialogs |
| 10 | Block-level message storage (JSON blob per message) | One row per block would explode row count (each message can have 20+ blocks). JSON blob keeps storage compact. FTS5 extracts searchable text. | Need to query individual blocks across messages |

---

## 21. Appendix: Current State Gap Analysis

| Current (v0.5.0) | Target (v1.0) | Phase |
|-------------------|---------------|-------|
| DeepSeek-only LLM | Multi-provider (Anthropic, OpenAI, DeepSeek, local) | 1 |
| SwiftUI `TextEditor` composer | `NSTextView` with @-mentions, slash commands, image paste | 1 |
| Simple `ScrollView` + `VStack` messages | Virtual-scrolling message list with lazy block decoding | 2 |
| Static tool call cards | Animated progress, expand/collapse, diff preview | 2 |
| Placeholder right panel tabs | Real terminal (PTY), live file browser, real diff review | 3 |
| No window restoration | `NSWindowRestoration` + multi-window support | 4 |
| Demo-level error handling | Typed error taxonomy with retry/recovery for all cases | 1 |
| Basic SQLite | WAL mode, FTS5, migrations, backup/restore | 1 |
| Minimal accessibility labels | Full VoiceOver, dynamic type, reduce motion, keyboard-only | 5 |
| No search | FTS5 full-text search + Quick Open + Spotlight | 4 |
| Single window | Multi-window with independent workspaces | 4 |
| No notifications | User notifications for completion, permissions, long runs | 5 |
| 258 tests (mostly Core/CLI) | 400+ tests with App-specific suites | All |
