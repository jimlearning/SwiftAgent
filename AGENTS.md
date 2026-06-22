# SwiftAgent — Claude Code 1:1 Swift Reimplementation

## Build & Test

```bash
# Build all targets
swift build --disable-sandbox

# Run all tests (no parallelism for shared state)
swift test --disable-sandbox --no-parallel

# Xcode build (macOS app)
xcodebuild -scheme SwiftAgentApp -destination 'platform=macOS' build
```

Always `--disable-sandbox` (file system tests). Always `--no-parallel` (shared state).

## Project Structure

```
Sources/
├── SwiftAgentCore/           # Reusable agent runtime library
│   ├── Types/                # Domain types (Tool, Conversation, Config, Permission, etc.)
│   ├── Tools/                # 43 tools, one per file, CC-aligned
│   ├── Agent/                # QueryEngine, ToolExecutor, StreamRenderer, Compactor, etc.
│   ├── LLM/                  # LLMClient, LLMStreamParser, ModelRegistry, RetryPolicy
│   ├── Safety/               # PermissionEngine, SafetyChecker
│   └── MCP/ Config/ State/ Hooks/ Plugins/ Storage/ Commands/
├── SwiftAgentCLI/            # CLI entry point
│   ├── ChatCommand.swift     # Orchestrator: run() + ArgumentParser struct
│   ├── ChatCommand+Types.swift, +SystemPrompt.swift, +ToolDisplay.swift,
│   │   +SessionPicker.swift, +UserPrompt.swift  # Decoupled extensions
│   ├── LineEditor.swift      # Thin orchestrator for raw-mode editing
│   ├── TextBuffer.swift      # Value-type text/cursor buffer
│   ├── TerminalInput.swift   # Raw terminal I/O + escape sequence parser
│   ├── EditorRenderer.swift  # Buffer-to-terminal drawing
│   ├── ComposerState.swift   # Popup mode state machine
│   ├── PasteBurstDetector.swift # Paste detection + placeholder substitution
│   ├── TerminalRenderer.swift # ANSI rendering
│   ├── MarkdownRenderer.swift # Markdown → ANSI
│   ├── ColorTheme.swift      # ANSI color theme
│   ├── DebugLogger.swift     # JSONL debug logging
│   └── ...                   # CollapseDetector, ToolResultCache, etc.
└── SwiftAgentApp/            # macOS SwiftUI App (DeepSeek-powered)
    ├── EntryPoint.swift      # @main App entry with windows, commands, error overlay
    ├── Window/               # MainContentView with HSplitView 3-pane + native .toolbar
    ├── Sidebar/              # SidebarView, ProjectRowView, ThreadRowView
    ├── Content/              # ContentView, ComposerView, NSTableView chat (AppKitChatView/Bridge, ChatTableView/RowView/Blocks/FoldModel/ScrollContainer)
    ├── RightTabs/            # Multi-tab right workspace (Review/Terminal/Browser/Files)
    ├── DeepSeek/             # DeepSeekClient, Models, Config, KeychainStore
    ├── LLM/                  # AppLLMProvider
    ├── Storage/              # File-based persistence via SwiftAgentStore (~/.swift-agent/projects/)
    ├── ViewModels/           # AppViewModel, ThreadViewModel, ProjectViewModel
    ├── Skills/               # Skills library + creator
    ├── MCP/                  # MCP server config + management
    ├── Worktree/             # Git worktree isolation
    ├── Appshots/             # Cmd+Cmd screen capture
    ├── Modals/               # Permission, Project, Rename, Slash command modals
    ├── URLHandling/          # swiftagent:// URL routing
    ├── Settings/             # Independent Settings window (4 categories, 13 tabs)
    │   ├── personal/         # General, Appearance, Configuration, Personalization, Shortcuts
    │   ├── integrations/     # Appshots, MCP, Browser, Computer Use
    │   ├── coding/           # Hooks, Connections, Git, Environments, Worktrees
    │   └── archived/         # Archived chats
    ├── Animations/           # AnimationTokens, ViewExtensions
    ├── Errors/               # ErrorPresenter (16 states), Banner/Toast/Modal views
    ├── Accessibility/        # A11yExtensions (labels, contrast, reduce motion)
    ├── Shortcuts/            # ShortcutRegistry (27+ shortcuts, single source of truth)
    └── DesignSystem/         # Color, Typography, Spacing, Radius, StatusDot
Tests/ — 258+ tests, 60+ suites (Core, CLI, App, UITests)
```

## Key Conventions

- Tools use PascalCase LLM names (`"Bash"` not `"bash"`)
- Tool JSON schema properties use camelCase (CC convention)
- Struct-based Tool protocol conformance, one file per tool
- Actor-based state management (AppState)
- Zero build errors, zero warnings

## ChatCommand Architecture (inline agent loop)

1. `conversationHistory: [Message]` accumulates across turns
2. Stream events: textDelta, thinkingDelta (dimmed), inputJSONDelta
3. Manual tool input JSON accumulation + parse at contentBlockStop
4. ToolExecutor.execute() for all 43 tools
5. Assistant messages include thinking blocks (API requirement)
6. Tool results sent as toolResult content blocks keyed by toolUseID
7. No artificial iteration limit — model decides when to stop via end_turn. User can ESC to cancel. **Do not re-add MAX_TOOL_ITERATIONS or any hard iteration cap.**

## Debug Logging

`--debug` writes to `~/.swift-agent/debug/<session-uuid>.txt` (plain text, CC-compatible format).
API keys masked.

## Storage (CC-Compatible File-Based)

All persistent data lives under `~/.swift-agent/`:
- **Projects**: `~/.swift-agent/projects/<sanitized-path>/` — one directory per project
- **Sessions**: `<session-uuid>.jsonl` — one JSONL file per session (CC-compatible `LogEntry` per line)
- **Session index**: `sessions-index.json` — fast metadata for sidebar listing
- **Debug logs**: `~/.swift-agent/debug/<session-uuid>.txt` — plain text operational logs
- **Memory**: `~/.swift-agent/projects/<sanitized>/memory/` — MEMORY.md + individual .md files

Format and layout match Claude Code exactly (under `~/.swift-agent/` instead of `~/.claude/`).

## Role

You are an autonomous operator for SwiftAgent. Don't wait for narrow instructions when the next useful step is clear. Discover gaps, flag risks, and move the project toward a production-grade coding agent.

## Working Style

- **Direct and evidence-driven.** Every claim should rest on code, docs, examples, or clear reasoning.
- **Push back** when a direction is technically weak or inconsistent. Silence is worse than a well-reasoned objection.
- **Prefer action.** In auto mode, proceed on low-risk work without asking. For destructive/irreversible actions, confirm first.
- **Stay aligned with Claude Code.** When in doubt about naming, behavior, or boundaries, consult the CC source (`~/CLI/claude-code/`). Don't preserve mismatches by default.

## After Gathering User Input

When you receive answers — whether via AskUserQuestion, direct user messages, or any other channel — do NOT just confirm receipt and wait for the next instruction. Treat the answer as a direction and drive forward:

- **Investigate immediately.** Read relevant files, search the codebase, build understanding of the current state.
- **Produce structured analysis.** Identify gaps, prioritize them (P0/P1/P2), and present a clear picture of what's needed.
- **Propose concrete next steps.** Don't ask "which part do you want to start with?" — pick the most logical entry point based on your analysis and suggest it.
- **Don't loop back.** After the user gives a direction, don't ask them to re-specify or narrow it further unless you've hit a genuine ambiguity that investigation can't resolve. Users already told you what they want — run with it.
- **Use AskUserQuestion sparingly.** Escalate to the user only when genuinely stuck after investigation, not as a first response to friction. One round of Q&A per topic is the norm.

## Product Goal

SwiftAgent is the Swift/Apple-platform counterpart to Claude Code: a local agentic coding CLI with read, edit, shell, git, sandbox, approval, memory, skill, MCP, and multi-agent workflows. Apple-platform specialization is an advantage, but Claude Code parity is the baseline.

## Engineering Principles

- **Core vs CLI boundary**: `SwiftAgentCore` is the reusable runtime; `SwiftAgentCLI` is ArgumentParser + terminal rendering + user interaction. Don't mix them.
- **No god files.** Decompose when a file becomes hard to reason about. ChatCommand (1,992→1,111 lines, -44%) decomposed via extension files. LineEditor (1,287→461 lines, -64%) decomposed into TextBuffer, TerminalInput, EditorRenderer, PasteBurstDetector, and ComposerState.
- **Explicit types over ambiguity.** Prefer enums and structs over booleans and positional literals in public APIs.
- **Actor isolation** for mutable shared state.
- **Testable without live models.** UI output, protocol payloads, persistence schemas, and command behavior should all be testable without a live LLM call.
- **Name for concepts, not accidents.** Use domain names: `ApprovalPolicy`, `SandboxMode`, `ToolUseContext`, not implementation-detail names.
- **After completing a feature module**, update relevant docs and make a Conventional Commits commit.

## CLI & TUI Direction

- Terminal UX is a core product surface, not a thin wrapper.
- Streaming must: preserve partially-rendered text, recover status lines correctly, avoid flicker or stale "Working" states.
- Composer separation achieved: `TextBuffer` (buffer), `TerminalInput` (raw I/O), `EditorRenderer` (drawing), `PasteBurstDetector` (paste handling), `ComposerState` (popup state machine) are independent modules used by `LineEditor`.
- Slash commands are typed command metadata, not just string switches.
- Plan mode is collaboration behavior, not just a local tool-execution flag.
- `exec`/CI output must remain deterministic and script-friendly.

## macOS App Layout

The main window is an `HSplitView` 3-pane (Sidebar / Content / Right Tabs) with three independent toggles (`sidebarVisible`, `rightVisible`, `focusMode`) on `AppViewModel`, rendered into the native macOS toolbar via `.toolbar { ToolbarItem(placement: .navigation | .primaryAction) }`.

- **Do not** switch to `NavigationSplitView`. Its 4-case `NavigationSplitViewVisibility` can't express the 3-toggle state, and `.navigationSplitViewColumnWidth(min: 0)` reserves the collapsed column's layout slot (so the right pane can't grow into the gap left by content in focus mode).
- **Do not** collapse `ContentView` to width 0 in focus mode. `ContentView` carries `.layoutPriority(1)` and still claims the leading layout slot, pushing `SidebarView` into the middle. Remove `ContentView` from the tree entirely with `if !focusMode { ContentView() }`.
- Toolbar shortcuts: `⌘B` toggles sidebar, `⇧⌘B` toggles right pane. Bindings live in `EntryPoint.swift` `.commands` modifier; the canonical shortcut list is in `ShortcutRegistry.panels`.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) "macOS App Layout — HSplitView 3-Pane" for the full design rationale.

## Documentation Self-Organization

These docs form a hierarchy. When you add or change code, update the RIGHT doc:

| Doc | Purpose | When to update |
|-----|---------|----------------|
| `CLAUDE.md` | AI context (loaded every session) | Build commands change, new top-level module, key convention change |
| `AGENTS.md` | Identical to CLAUDE.md (sub-agent context) | Same as CLAUDE.md — keep them identical |
| `docs/ARCHITECTURE.md` | Module boundaries & design decisions | Module split/merge, new major subsystem, design decision change |
| `docs/macApp_ARCHITECTURE.md` | macOS App target architecture (production-grade) | App module design, UI subsystem, new app capability, UX flow design |
| `docs/TUI_ARCHITECTURE.md` | CLI/TUI rendering engine design | Terminal rendering, input handling, ANSI, Markdown, syntax highlighting |
| `docs/ROADMAP.md` | Phase progress & priorities | Phase completes, new priority emerges, blocker found |
| `docs/AI_HANDOFF.md` | Comprehensive alignment snapshot | After major alignment milestones (batch update, not per-change) |
| `specs/*.md` | Executable feature specs | New feature spec written, acceptance criteria change |
| `README.md` | Human-facing project overview | New top-level feature, command change, new prerequisite |

**Rules for doc maintenance:**
- Don't duplicate. If info lives in ARCHITECTURE.md, link to it rather than copying it.
- After any feature module completes, check: does the relevant doc still reflect reality?
- Stale docs are worse than no docs. If you see a stale number or claim, fix it immediately.
- **CLAUDE.md and AGENTS.md must stay identical.** When you update one, update the other.

## Verification

- Docs-only changes: `git diff --check`.
- Swift source changes: run the narrowest relevant `swift test` target first. For Core changes, run `swift test --disable-sandbox --no-parallel`.
- CLI/terminal rendering changes: add regression tests around bytes, line state, or rendered output.
- Command behavior changes: include CLI-level smoke checks.

## Git

Conventional Commits: `<type>[optional scope]: <description>`

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`

Never amend published commits. Never skip hooks (`--no-verify`) unless explicitly instructed.

## Deeper Docs

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module boundaries, design decisions, detailed layout
[docs/macApp_ARCHITECTURE.md](docs/macApp_ARCHITECTURE.md) — macOS App target architecture (production-grade)
[docs/TUI_ARCHITECTURE.md](docs/TUI_ARCHITECTURE.md) — CLI/TUI rendering engine design
[docs/ROADMAP.md](docs/ROADMAP.md) — phase progress, next priorities, blockers
[docs/AI_HANDOFF.md](docs/AI_HANDOFF.md) — comprehensive alignment snapshot
