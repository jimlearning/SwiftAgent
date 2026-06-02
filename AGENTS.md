# SwiftAgent — Claude Code 1:1 Swift Reimplementation

## Build & Test

```bash
swift build --disable-sandbox
swift test --disable-sandbox --no-parallel
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
└── SwiftAgentCLI/            # CLI entry point
    ├── ChatCommand.swift     # Orchestrator: run() + ArgumentParser struct
    ├── ChatCommand+Types.swift, ChatCommand+SystemPrompt.swift,
    │   ChatCommand+ToolDisplay.swift, ChatCommand+SessionPicker.swift,
    │   ChatCommand+UserPrompt.swift  # Decoupled extensions
    ├── LineEditor.swift      # Thin orchestrator for raw-mode editing
    ├── TextBuffer.swift      # Value-type text/cursor buffer
    ├── TerminalInput.swift   # Raw terminal I/O + escape sequence parser
    ├── EditorRenderer.swift  # Buffer-to-terminal drawing
    ├── ComposerState.swift   # Popup mode state machine
    ├── PasteBurstDetector.swift # Paste detection + placeholder substitution
    ├── TerminalRenderer.swift # ANSI rendering (banner, left-border, panel, spinner)
    ├── MarkdownRenderer.swift # Markdown → ANSI
    ├── TerminalCapability.swift # TTY/color/size detection
    ├── TerminalDisplayWidth.swift # CJK-aware display width
    ├── InlinePopup.swift     # Popup UI rendering
    ├── PopupDataSource.swift # Command + file data sources for popups
    ├── StatusLine.swift      # Bottom-line overlay
    ├── ColorTheme.swift      # ANSI color theme
    ├── DebugLogger.swift     # JSONL debug logging
    └── ...                   # CollapseDetector, ToolResultCache, FileSearchIndex,
                                FuzzyMatcher, TokenANSIRenderer, CodeTheme
Tests/ — 232 tests, 57 suites
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
7. Max 25 iterations per turn, auto-completion detection

## Debug Logging

`--debug` writes to `~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl`.
Request body, response status, raw SSE events logged. API keys masked.

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

## Documentation Self-Organization

These docs form a hierarchy. When you add or change code, update the RIGHT doc:

| Doc | Purpose | When to update |
|-----|---------|----------------|
| `CLAUDE.md` | AI context (loaded every session) | Build commands change, new top-level module, key convention change |
| `AGENTS.md` | Identical to CLAUDE.md (sub-agent context) | Same as CLAUDE.md — keep them identical |
| `docs/ARCHITECTURE.md` | Module boundaries & design decisions | Module split/merge, new major subsystem, design decision change |
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
[docs/ROADMAP.md](docs/ROADMAP.md) — phase progress, next priorities, blockers
[docs/AI_HANDOFF.md](docs/AI_HANDOFF.md) — comprehensive alignment snapshot
