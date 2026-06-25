# Codebase Structure

**Analysis Date:** 2026-06-25

## Directory Layout

```
SwiftAgent/                          # Project root
├── Package.swift                    # SPM manifest (3 targets, 4 test targets)
├── Package.resolved                 # Dependency pinning
├── AGENTS.md                        # AI context (identical to CLAUDE.md)
├── CLAUDE.md                        # Project instructions for AI assistants
├── README.md                        # Human-facing overview
├── CHANGELOG.md                     # Release notes
├── IDENTITY.md                      # Project identity / branding
├── SOUL.md                          # Project philosophy
├── .gitignore                       # Git exclusion rules
├── .mcp.json                        # MCP server configuration
│
├── Sources/                         # All source code (295 .swift files)
│   ├── SwiftAgentCore/              # Reusable agent runtime library
│   │   ├── Types/                   # Domain types (22 files)
│   │   ├── Tools/                   # Built-in tools (60+ files, one per tool)
│   │   ├── Agent/                   # Agent loop engine (11 files)
│   │   ├── LLM/                     # LLM client layer (5 files)
│   │   ├── Safety/                  # Permission & safety (4 files)
│   │   ├── MCP/                     # Model Context Protocol (13 files)
│   │   ├── Config/                  # Configuration loading (3 files)
│   │   ├── State/                   # Application state (2 files)
│   │   ├── Features/                # Feature flags (1 file)
│   │   ├── Hooks/                   # Hook system (1 file)
│   │   ├── Commands/                # Command registry (1 file)
│   │   ├── Plugins/                 # Plugin system (1 file)
│   │   ├── Storage/                 # File-based persistence (8 files)
│   │   ├── Workspace/               # Workspace operations (1 file)
│   │   ├── Utilities/               # Shared utilities (2 files)
│   │   ├── Constants/               # System constants (8 files)
│   │   ├── SyntaxHighlighting/      # Tree-sitter integration (2 files)
│   │   ├── Skills/                  # Skill loading (2 files)
│   │   ├── CoreTypes.swift          # Core version enum
│   │   └── ShellResolver.swift      # Shell path resolution
│   │
│   ├── SwiftAgentCLI/               # Terminal CLI executable
│   │   ├── EntryPoint.swift         # Program entry (@main)
│   │   ├── ChatCommand.swift        # Orchestrator: run() + argument parsing
│   │   ├── ChatCommand+Types.swift  # Shared types extension
│   │   ├── ChatCommand+SystemPrompt.swift  # System prompt builders extension
│   │   ├── ChatCommand+ToolDisplay.swift   # Tool result display extension
│   │   ├── ChatCommand+SessionPicker.swift # Session picker extension
│   │   ├── ChatCommand+UserPrompt.swift    # User prompt handler extension
│   │   ├── ChatToolExecutionScheduler.swift  # Concurrent tool execution
│   │   ├── ChatToolInputAccumulator.swift    # Streaming tool input JSON accumulator
│   │   ├── TerminalRenderer.swift    # ANSI rendering
│   │   ├── TerminalCapability.swift  # Terminal capability detection
│   │   ├── TerminalDisplayWidth.swift # CJK/emoji-aware column widths
│   │   ├── StatusLine.swift          # Bottom overlay
│   │   ├── LineEditor.swift          # Raw-mode editor orchestrator
│   │   ├── TextBuffer.swift          # Value-type text/cursor buffer
│   │   ├── TerminalInput.swift       # Raw terminal I/O + escape sequences
│   │   ├── EditorRenderer.swift      # Buffer-to-terminal drawing
│   │   ├── ComposerState.swift       # Popup mode state machine
│   │   ├── PasteBurstDetector.swift  # Paste burst detection
│   │   ├── MarkdownRenderer.swift    # Markdown -> ANSI
│   │   ├── InlinePopup.swift         # Popup UI rendering
│   │   ├── PopupDataSource.swift     # Command + file data sources
│   │   ├── ColorTheme.swift          # Color themes
│   │   ├── CodeTheme.swift           # Syntax highlight themes
│   │   ├── DebugLogger.swift         # JSONL debug logging
│   │   ├── CollapseDetector.swift    # Tool collapse detection
│   │   ├── ToolResultCache.swift     # Collapsed result cache
│   │   ├── FileSearchIndex.swift     # git ls-files search index
│   │   ├── FuzzyMatcher.swift        # Fuzzy matching
│   │   ├── TokenANSIRenderer.swift   # Token-level ANSI rendering
│   │   └── EvalCommand.swift         # Evaluation subcommand
│   │
│   └── SwiftAgentApp/               # macOS SwiftUI App executable
│       ├── EntryPoint.swift          # @main App entry, scenes, commands
│       ├── AppDelegate.swift         # NSApplicationDelegate
│       ├── NotificationNames.swift   # Notification.Name definitions
│       ├── Info.plist                # Bundle metadata
│       ├── Window/                   # Main window layout
│       │   └── MainContentView.swift # HSplitView 3-pane + toolbar
│       ├── Sidebar/                  # Left sidebar
│       │   └── SidebarView.swift     # Project + thread list
│       ├── Content/                  # Center chat pane
│       │   ├── ContentView.swift     # Toolbar + messages + composer
│       │   ├── ComposerView.swift    # Message input
│       │   ├── ComposerAccessoryView.swift  # Model/Permission pickers
│       │   ├── AppKitChatBridge.swift       # Coordinator: AppKit<->SwiftUI
│       │   ├── ChatTableView.swift          # NSTableView with cell reuse
│       │   ├── ChatTableRowView.swift       # NSStackView row layout
│       │   ├── ChatBlockViews.swift         # Text/thinking/toolUse/toolResult
│       │   ├── ChatFoldModel.swift          # Collapse state
│       │   └── ChatScrollContainer.swift    # Scroll with stickiness
│       ├── RightTabs/               # Right workspace
│       │   ├── RightTabsView.swift   # Multi-tab container
│       │   ├── RightTabsStore.swift  # Tab state ObservableObject
│       │   ├── RightTab.swift        # Tab data model
│       │   ├── RightTabType.swift    # Tab type enum
│       │   ├── TabBarView.swift      # Horizontal tab bar
│       │   ├── TabLabel.swift        # Tab labels
│       │   ├── TabContentView.swift  # Active tab content
│       │   ├── EmptyTabPlaceholder.swift
│       │   ├── DiffService.swift
│       │   └── panels/              # Tab content panels
│       │       ├── ReviewPanelView.swift
│       │       ├── TerminalPanelView.swift
│       │       ├── TerminalView.swift
│       │       ├── BrowserPanelView.swift
│       │       ├── FilesPanelView.swift
│       │       └── SideChatPanelView.swift
│       ├── DeepSeek/                # DeepSeek API integration
│       │   ├── DeepSeekClient.swift  # Streaming Chat Completions
│       │   ├── DeepSeekConfig.swift  # API config
│       │   ├── DeepSeekModel.swift   # Model enum
│       │   └── KeychainStore.swift   # Secure key storage
│       ├── LLM/                     # Provider system
│       │   ├── AppLLMProvider.swift  # Provider wrapper
│       │   ├── LLMProvider.swift     # Provider protocol
│       │   ├── AnthropicProvider.swift
│       │   ├── DeepSeekProvider.swift
│       │   ├── OpenAIProvider.swift
│       │   └── ProviderRegistry.swift
│       ├── Storage/                 # SQLite persistence
│       │   ├── StorageManager.swift  # Database lifecycle
│       │   ├── Database.swift        # SQLite connection
│       │   ├── Migrations.swift      # Schema migrations
│       │   ├── Models.swift          # Persisted data models
│       │   ├── ProjectRepository.swift
│       │   ├── ThreadRepository.swift
│       │   └── MessageRepository.swift
│       ├── ViewModels/              # MVVM ViewModels
│       │   ├── AppViewModel.swift    # Root app state
│       │   ├── ThreadViewModel.swift # Per-thread state
│       │   ├── ProjectViewModel.swift # Per-project state
│       │   ├── ComposerAttachment.swift
│       │   └── EditSummary.swift
│       ├── Settings/                # Independent Settings window
│       │   ├── SettingsWindow.swift  # Sidebar + content
│       │   ├── personal/           # 5 tabs
│       │   ├── integrations/       # 4 tabs
│       │   ├── coding/             # 5 tabs
│       │   └── archived/           # 1 tab
│       ├── Modals/                  # Modal sheets
│       │   ├── PermissionModal.swift
│       │   ├── PermissionPicker.swift
│       │   ├── NewProjectSheet.swift
│       │   ├── ModelPicker.swift
│       │   ├── RenameSheet.swift
│       │   ├── RenameTarget.swift
│       │   ├── AddMenu.swift
│       │   ├── PluginsSubmenu.swift
│       │   └── PluginsSubmenuContent.swift
│       ├── MCP/                     # MCP server UI
│       │   ├── MCPConfigView.swift
│       │   ├── MCPConfigStore.swift
│       │   ├── MCPServerCard.swift
│       │   └── AddMCPServerSheet.swift
│       ├── Skills/                  # Skills library
│       │   ├── SkillsView.swift
│       │   ├── SkillCard.swift
│       │   ├── SkillCreatorSheet.swift
│       │   ├── SkillDescriptor.swift
│       │   └── SkillScope.swift
│       ├── Appshots/               # Screen capture
│       │   ├── GlobalHotkey.swift
│       │   ├── AppshotCapture.swift
│       │   ├── AppshotToastView.swift
│       │   └── AXTextExtractor.swift
│       ├── Worktree/               # Git worktree
│       │   ├── WorktreeManager.swift
│       │   └── WorktreePickerSheet.swift
│       ├── URLHandling/            # swiftagent:// URLs
│       │   └── URLRouter.swift
│       ├── Agent/                  # App-side agent bridge
│       │   ├── AppAgentProvider.swift
│       │   ├── AgentSessionManager.swift
│       │   └── AgentMessages.swift
│       ├── Errors/                  # Error presentation
│       │   ├── ErrorPresenter.swift
│       │   ├── ErrorTaxonomy.swift
│       │   ├── ErrorBannerView.swift
│       │   ├── ErrorToastView.swift
│       │   └── ErrorModalView.swift
│       ├── Accessibility/
│       │   └── A11yExtensions.swift
│       ├── Shortcuts/
│       │   └── ShortcutRegistry.swift
│       ├── Animations/
│       │   ├── AnimationTokens.swift
│       │   └── ViewExtensions.swift
│       ├── DesignSystem/           # Design tokens
│       │   ├── Color.swift
│       │   ├── Typography.swift
│       │   ├── Spacing.swift
│       │   ├── Radius.swift
│       │   ├── CellTokens.swift
│       │   ├── CodeColors.swift
│       │   ├── DragDivider.swift
│       │   ├── HorizontalDragDivider.swift
│       │   ├── HoverHighlight.swift
│       │   └── StatusDot.swift
│       ├── Markdown/
│       │   └── MarkdownRenderer.swift
│       └── Debug/
│           ├── AgentDebugger.swift
│           ├── DebugLog.swift
│           └── DebugPanelView.swift
│
├── Packages/                       # Local Swift packages
│   └── Sources/
│       ├── ClarcCore/              # App-level shared types
│       │   ├── WindowState.swift
│       │   ├── CLISession/
│       │   ├── Models/
│       │   ├── Theme/
│       │   └── Utilities/
│       └── ClarcChatKit/           # Reusable chat UI components
│           ├── ChatBridge.swift
│           ├── ChatView.swift
│           ├── MessageListView.swift
│           ├── MessageBubble.swift
│           ├── InputBarView.swift
│           ├── SlashCommandBar.swift
│           ├── ToolResultView.swift
│           ├── ThinkingBlockView.swift
│           ├── MarkdownView.swift
│           ├── FileDiffView.swift
│           ├── StatusLineView.swift
│           ├── TypingDotsView.swift
│           ├── AskUserQuestionView.swift
│           └── Resources/ (en.lproj, ko.lproj)
│
├── Tests/                          # 258+ tests across 29 files
│   ├── SwiftAgentCoreTests/        # 13 test files (Phases 1-12 + misc)
│   ├── SwiftAgentCLITests/         # 5 test files (terminal/input regression)
│   ├── SwiftAgentAppTests/         # 6 test files (unit)
│   └── SwiftAgentAppUITests/       # 5 test files (XCUITest)
│
├── docs/                           # Documentation directory
│   ├── ARCHITECTURE.md             # Detailed module boundaries & design decisions
│   ├── macApp_ARCHITECTURE.md      # App target architecture
│   ├── TUI_ARCHITECTURE.md         # CLI/TUI rendering engine design
│   ├── ROADMAP.md                  # Phase progress & priorities
│   ├── AI_HANDOFF.md               # Alignment snapshot
│   └── FREEZE_DEBUGGING.md         # UI freeze diagnosis & prevention
│
├── scripts/                        # Build/utility scripts
└── logs/                           # Local logs directory
```

## Directory Purposes

**`Sources/SwiftAgentCore/`:**
- Purpose: Shared, UI-free agent runtime library. The foundation both CLI and App targets build on.
- Contains: Domain types, Tool implementations, Agent loop engine, LLM client, Permission system, MCP integration, Config, State, Storage, Hooks, Plugins, Syntax highlighting
- Key files: `CoreTypes.swift`, `Types/Tool.swift`, `Agent/QueryEngine.swift`, `Agent/ToolExecutor.swift`, `LLM/LLMClient.swift`, `Safety/PermissionEngine.swift`

**`Sources/SwiftAgentCLI/`:**
- Purpose: Terminal-based interactive coding agent. All terminal UI lives here.
- Contains: ArgumentParser command structure, terminal rendering (ANSI), raw-mode input handling, streaming output, markdown -> ANSI conversion
- Key files: `EntryPoint.swift`, `ChatCommand.swift`, `LineEditor.swift`, `TerminalRenderer.swift`, `MarkdownRenderer.swift`

**`Sources/SwiftAgentApp/`:**
- Purpose: macOS native GUI application with SwiftUI + AppKit.
- Contains: MVVM ViewModels, SwiftUI Views, NSTableView chat, SQLite storage, Settings, URL handling, Error system
- Key files: `EntryPoint.swift`, `ViewModels/AppViewModel.swift`, `Window/MainContentView.swift`, `Content/ChatTableView.swift`

**`Packages/`:**
- Purpose: Local Swift packages shared between App targets but not the Core library.
- Contains: ClarcCore (shared types, window state, theme), ClarcChatKit (reusable chat UI components)
- Key files: `Sources/ClarcChatKit/ChatBridge.swift`, `Sources/ClarcCore/WindowState.swift`

**`Tests/`:**
- Purpose: All test targets organized by module.
- Contains: CoreTests (13 files, phased), CLITests (5 files), AppTests (6 files), AppUITests (5 XCUITest files)
- Key files: `SwiftAgentCoreTests/Phase1TypesTests.swift` through `Phase12AdvancedTests.swift`

**`docs/`:**
- Purpose: Design documents and architecture references.
- Contains: ARCHITECTURE.md, macApp_ARCHITECTURE.md, TUI_ARCHITECTURE.md, ROADMAP.md, AI_HANDOFF.md, FREEZE_DEBUGGING.md

**.dot directories (`.claude/`, `.codegraph/`, `.codex/`, `.mavis/`, `.omc/`, `.omo/`, `.planning/`, `.reasonix/`, `.vscode/`):**
- Purpose: Tool-specific configuration and state directories. Mostly git-ignored.
- `.planning/codebase/` is where this document lives — consumed by other GSD commands.

## Key File Locations

**Entry Points:**
- `Sources/SwiftAgentCLI/EntryPoint.swift`: CLI `@main` — ArgumentParser root, dispatches to ChatCommand/EvalCommand
- `Sources/SwiftAgentApp/EntryPoint.swift`: App `@main` — SwiftUI App, creates MainContentView + Settings + commands
- `Sources/SwiftAgentApp/AppDelegate.swift`: NSApplicationDelegate — activation policy, window management

**Configuration:**
- `Package.swift`: SPM manifest — defines 3 products, 5 dependencies, 3 targets, 4 test targets
- `Package.resolved`: Dependency version pinning
- `.mcp.json`: MCP server configurations
- `Sources/SwiftAgentApp/Info.plist`: App bundle metadata

**Core Logic (Agent Loop):**
- `Sources/SwiftAgentCore/Agent/QueryEngine.swift`: Main query loop — user turn -> stream -> execute tools -> loop
- `Sources/SwiftAgentCore/Agent/ToolExecutor.swift`: Tool validation, permission, execution, result persistence
- `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift`: 17-pass message normalization for API
- `Sources/SwiftAgentCLI/ChatCommand.swift`: CLI orchestrator — wires all subsystems, owns the inline agent loop

**Terminal Rendering:**
- `Sources/SwiftAgentCLI/TerminalRenderer.swift`: ANSI rendering — banners, spinners, borders, panels
- `Sources/SwiftAgentCLI/MarkdownRenderer.swift`: Markdown -> ANSI — headings, code blocks, tables, lists
- `Sources/SwiftAgentCLI/LineEditor.swift`: Raw-mode editor orchestrator (thin, ~461 lines)
- `Sources/SwiftAgentCLI/TextBuffer.swift`: Value-type text/cursor buffer
- `Sources/SwiftAgentCLI/TerminalInput.swift`: Raw terminal I/O + escape sequence parser
- `Sources/SwiftAgentCLI/EditorRenderer.swift`: Buffer-to-terminal drawing with display-width awareness

**Chat Rendering (App):**
- `Sources/SwiftAgentApp/Content/ChatTableView.swift`: NSTableView with cell reuse, height caching
- `Sources/SwiftAgentApp/Content/ChatTableRowView.swift`: NSStackView block stacking
- `Sources/SwiftAgentApp/Content/ChatBlockViews.swift`: Block views (text, thinking, toolUse, toolResult, system)
- `Sources/SwiftAgentApp/Content/AppKitChatBridge.swift`: Coordinator bridging AppKit table view to SwiftUI state

**Persistence:**
- `Sources/SwiftAgentCore/Storage/SwiftAgentStore.swift`: CC-compatible file-based store (~/.swift-agent/)
- `Sources/SwiftAgentCore/Storage/SessionStore.swift`: JSONL session persistence
- `Sources/SwiftAgentCore/Storage/MemoryStore.swift`: Memory file storage
- `Sources/SwiftAgentApp/Storage/StorageManager.swift`: App SQLite database lifecycle
- `Sources/SwiftAgentApp/Storage/Database.swift`: SQLite connection management

**App State:**
- `Sources/SwiftAgentApp/ViewModels/AppViewModel.swift`: `@MainActor` ObservableObject — root app state, layout toggles, LLM provider
- `Sources/SwiftAgentApp/ViewModels/ThreadViewModel.swift`: Per-thread messages, send/stream lifecycle
- `Sources/SwiftAgentCore/State/AppState.swift`: Actor-based shared state

**Testing:**
- `Tests/SwiftAgentCoreTests/`: 13 test files covering types, LLM, agent, tools, safety, config, commands, storage, MCP, sub-agents, advanced
- `Tests/SwiftAgentCLITests/`: 5 test files covering terminal rendering, line editor readline/history/ghost, composer popups
- `Tests/SwiftAgentAppTests/`: 6 test files covering permissions, persistence, right tabs, skills, thread repo
- `Tests/SwiftAgentAppUITests/`: 5 XCUITest files covering launch/layout, new thread, settings, panel switch, theme

## Naming Conventions

**Files:**
- PascalCase: `ChatCommand.swift`, `QueryEngine.swift`, `BashTool.swift` — matches Swift convention
- One tool per file: `BashTool.swift`, `FileReadTool.swift`, `GlobTool.swift` — matches CC organization
- Extension files use `FileName+ExtensionName.swift`: `ChatCommand+Types.swift`, `ChatCommand+SystemPrompt.swift` — decomposition pattern
- Test files use `Phase[N][Area]Tests.swift` pattern: `Phase1TypesTests.swift`, `Phase2LLMTests.swift`

**Directories:**
- PascalCase: `Agent/`, `Types/`, `Tools/`, `ViewModels/`, `DesignSystem/` — matches Swift convention
- No nesting deeper than 3 levels under Sources
- Category grouping: `Settings/personal/`, `Settings/coding/`, `Settings/integrations/`, `RightTabs/panels/`

**Types:**
- PascalCase: `ToolUseContext`, `PermissionEngine`, `AppViewModel`, `QueryEngine` — standard Swift naming
- Protocols: PascalCase with no prefix/suffix: `Tool`, `DebugLogSink`, `LLMDebugLogger`
- Enums: PascalCase: `PermissionMode`, `StreamEvent`, `QuerySource`, `RightTabType`

**Functions:**
- camelCase: `run()`, `execute()`, `streamChat()`, `normalizeMessagesForAPI()`
- Tool `call()` method matches CC's `call(input, context, canUseTool, parentMessage, onProgress)`
- Tool `description(input:options:)` matches CC's `description(input, options)`

**Variables/Properties:**
- camelCase: `conversationHistory`, `toolExecutor`, `apiKey`, `workingDirectory`
- Published properties: `sidebarVisible`, `rightVisible`, `focusMode`
- State actor fields follow CC naming: `settings`, `conversation`, `tokens`

## Where to Add New Code

**New Core Tool:**
- Primary code: `Sources/SwiftAgentCore/Tools/<ToolName>Tool.swift` (one file per tool)
- Register in: `Sources/SwiftAgentCLI/ChatCommand.swift` `registerBuiltinTools(into:)` or a dedicated registry file
- Tests: `Tests/SwiftAgentCoreTests/Phase4ToolsTests.swift` (or create new phase file)

**New Core Agent Module:**
- Implementation: `Sources/SwiftAgentCore/Agent/<ModuleName>.swift`
- Tests: `Tests/SwiftAgentCoreTests/<NewPhaseFile>.swift`

**New Core Domain Type:**
- Implementation: `Sources/SwiftAgentCore/Types/<TypeName>.swift`
- Tests: `Tests/SwiftAgentCoreTests/Phase1TypesTests.swift`

**New CLI Feature (terminal UI):**
- Implementation: `Sources/SwiftAgentCLI/<FeatureName>.swift`
- If extending ChatCommand: `Sources/SwiftAgentCLI/ChatCommand+<FeatureName>.swift`
- Tests: `Tests/SwiftAgentCLITests/<FeatureName>Tests.swift`

**New App View (macOS native):**
- Primary view: `Sources/SwiftAgentApp/<Feature>/<FeatureName>View.swift`
- ViewModel: `Sources/SwiftAgentApp/ViewModels/<FeatureName>ViewModel.swift` (if stateful)
- Settings tab: `Sources/SwiftAgentApp/Settings/<category>/<FeatureName>Settings.swift`
- Tests: `Tests/SwiftAgentAppTests/<FeatureName>Tests.swift`

**New App Modal/Sheet:**
- Implementation: `Sources/SwiftAgentApp/Modals/<ModalName>.swift`

**New App Storage Entity:**
- Model: `Sources/SwiftAgentApp/Storage/Models.swift` (add to existing)
- Repository: `Sources/SwiftAgentApp/Storage/<EntityName>Repository.swift`
- Migration: `Sources/SwiftAgentApp/Storage/Migrations.swift` (add migration step)
- Tests: `Tests/SwiftAgentAppTests/<EntityName>RepositoryTests.swift`

**New Shared UI Component (reusable across app):**
- If chat-specific: `Packages/Sources/ClarcChatKit/<ComponentName>.swift`
- If app-shared: `Packages/Sources/ClarcCore/` appropriate subdirectory
- Avoid adding to ClarcChatKit if Core-only; avoid adding to ClarcCore if chat-specific

**Utilities:**
- Shared helpers (Core): `Sources/SwiftAgentCore/Utilities/<UtilityName>.swift`
- CLI-only helpers: `Sources/SwiftAgentCLI/<UtilityName>.swift`

## Special Directories

**`.build/`:**
- Purpose: SPM build artifacts
- Generated: Yes (by `swift build`)
- Committed: No (git-ignored)

**`Packages/.build/`:**
- Purpose: Local package build artifacts
- Generated: Yes
- Committed: No

**`.planning/`:**
- Purpose: Planning artifacts for GSD workflow
- Generated: Yes (by `/gsd-map-codebase` and `/gsd-plan-phase`)
- Committed: No (git-ignored)

**`logs/`:**
- Purpose: Local runtime logs
- Generated: Yes (at runtime)
- Committed: No

---

*Structure analysis: 2026-06-25*
