# SwiftAgent

<p align="center">
  <strong>AI coding agent — pure Swift CLI + macOS Desktop App (DeepSeek)</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/macOS-14+-lightgrey?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/tests-258%20passing-brightgreen" alt="258 tests">
  <img src="https://img.shields.io/badge/build-0%20errors%2C%200%20warnings-success" alt="Build">
</p>

SwiftAgent is a Swift-native coding agent modeled after Claude Code. It ships as **two products**:

1. **CLI** (`swift-agent`) — Full agentic coding CLI with 43 tools, TUI, streaming
2. **macOS App** (`SwiftAgentApp`) — Native SwiftUI desktop app with DeepSeek models, multi-tab workspace, screen capture (Appshots), and Skills/MCP integration

---

## Quick Start

### Prerequisites

- macOS 14+, Swift 6.0+
- An API key for your LLM provider

### Build from Source

```bash
git clone https://github.com/jimlearning/SwiftAgent.git
cd SwiftAgent
swift build --disable-sandbox
```

### Run

```bash
# SwiftAgent resolves API keys from the same sources as Claude Code:
#   1. --api-key flag
#   2. ANTHROPIC_API_KEY environment variable
#   3. ANTHROPIC_AUTH_TOKEN environment variable (OAuth bearer token)
#   4. macOS keychain (service: "Claude Code") 
#   5. ~/.claude.json (primaryApiKey field)
#
# If Claude Code works, SwiftAgent will too — no extra configuration needed.

# Start interactive chat
swift run --disable-sandbox swift-agent chat

# Or override via flags
swift run --disable-sandbox swift-agent chat --api-key "sk-..." --model "gpt-4o"
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | *(auto-resolved)* | API key (env, keychain, or ~/.claude.json) |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro` | Model ID to use |
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` | API base URL (Anthropic-compatible endpoint) |

---

## Commands

| Command | Description |
|---|---|
| `swift-agent chat` | Start an interactive AI coding session |

Run `swift-agent --help` for details.

### Chat Flags

```
--api-key <key>       API key (or set ANTHROPIC_API_KEY)
--model <model>       Model ID (or set ANTHROPIC_MODEL, default: deepseek-v4-pro)
--permission <mode>   Permission mode: default, plan, acceptEdits, bypass
--no-color            Disable ANSI color output
--no-markdown         Disable markdown rendering in responses
--debug, -d           Enable debug logging of all API requests and responses
```

### Slash Commands (in-chat)

| Command | Action |
|---|---|
| `/help` | Show available commands |
| `/clear` | Clear the screen |
| `/exit`, `/quit` | Exit the session |

### macOS App

```bash
# Build the macOS app
swift build --disable-sandbox -c debug

# Or via Xcode
xcodebuild -scheme SwiftAgentApp -destination 'platform=macOS' build
```

The macOS app requires macOS 15+ and supports Dark/Light themes, 27+ keyboard shortcuts, a full Settings window (4 categories × 13 tabs), and 16 handled error states.

**Key features:**
- Three-pane layout (Sidebar / Conversation / Multi-tab workspace)
- DeepSeek integration (V3, R1, V3-0324, Coder-V2) with streaming
- Multi-project, multi-thread with SQLite persistence
- Right multi-tab workspace (Review, Terminal, Browser, Files, Side chat)
- Skills library + MCP server management
- Worktree isolation (git worktree automation)
- Appshots — Cmd+Cmd screen capture for visual context
- 4-tier sandbox permissions
- Accessibility: VoiceOver labels, High Contrast, Reduce Motion, Dynamic Type

---

## Features

### Agentic Loop
Inline agent loop (ported from TUIApp): user input → stream LLM with thinking display → parse tool calls → execute tools → loop back. Supports up to 25 iterations per turn with full conversation history.

### Tools (43 built-in, CC-aligned)
Full Claude Code tool ecosystem: Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, Agent, Skill, TaskCreate/Get/List/Output/Update/Stop, TodoWrite, NotebookEdit, LSP, MCP, Config, Brief, AskUserQuestion, EnterPlanMode, ExitPlanMode, EnterWorktree, ExitWorktree, SendMessage, ToolSearch, PowerShell, CronCreate/List/Delete, Sleep, SyntheticOutput, RemoteTrigger, TeamCreate/Delete.

### CLI Experience
- **Nanobot-style REPL** with raw-mode line editor (arrow keys, history, UTF-8, Ctrl+A/E/K/U/W)
- **Paste detection** — multi-line pastes show `[Pasted text #N +M lines]` while submitting the original pasted text
- **Multi-line input** — Option+Enter and Shift+Enter insert literal newlines with cursor alignment
- **Wide-character alignment** — Chinese/CJK input, wrapped prompts, code blocks, and markdown tables use terminal display width
- **ESC to cancel** — press Escape during agent processing to immediately stop and restore your input
- **Markdown rendering** — headings, bold/italic, fenced code blocks (boxed), tables, blockquotes, links
- **`--no-markdown` flag** to disable rendering and display raw text
- **Braille spinner** with live tool name display during execution
- **Streaming thinking display** — model reasoning shown in dim ANSI style
- **Left-border response** — clean output with `│` prefix, no box noise
- **Debug logging** — `--debug` flag writes all API requests/responses to `~/.swift-agent/logs/`

### Permission & Safety (7-step pipeline)
1. Bypass check (bypassPermissions mode)
2. Allow rules
3. Plan mode guard
4. Accept edits guard
5. Safety check (dangerous shell patterns)
6. Default policy
7. Ask user

**Modes:** `default`, `plan`, `acceptEdits`, `bypassPermissions`

### Configuration (5-layer merge)
```
1. Plugin config
2. User config     → ~/.swift-agent/config.json
3. Project config  → .swift-agent/config.json
4. Local config
5. CLI flags
```

### Session & Memory
- Session persistence as JSON files in `~/.swift-agent/sessions/`
- CLAUDE.md reader/writer with YAML frontmatter parsing

### MCP (Model Context Protocol)
- `MCPClient` with stdio transport (actor-based)
- JSON-RPC 2.0 message encoding/decoding
- Tool bridge: MCP tools → ToolDefinition

### Sub-Agent System
- `SubAgentManager` for isolated agent execution; REPL `Agent` calls can run foreground sub-agents synchronously or launch background sub-agents with `runInBackground`
- Foreground sub-agent progress is surfaced in the spinner/status line; background sub-agent progress and final output are available through `TaskOutput`
- `TaskManager` (actor) for background task lifecycle, including local agent task metadata
- `WorktreeManager` for git worktree isolation

### Hooks & Plugins
- Lifecycle event hooks: `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, etc.
- Plugin manifest validation and loading

### Feature Flags
- Runtime feature toggles with compile-time dead-code elimination support
- Default flags: `mcp`, `worktree_isolation`, `streaming_output`, `auto_compact`

---

## Project Structure

```
SwiftAgent/
├── Package.swift
├── Sources/
│   ├── SwiftAgentCore/         # Reusable agent runtime library
│   │   ├── Types/              # Domain types (Conversation, Tool, Permission, etc.)
│   │   ├── State/              # AppState (actor) + AppStateStore
│   │   ├── LLM/                # LLM client, SSE stream parser, retry
│   │   ├── Agent/              # QueryEngine, prompt builder, context, tool executor
│   │   ├── Tools/              # Read, Write, Edit, Bash, Glob, Grep
│   │   ├── Safety/             # PermissionEngine, SafetyChecker, PermissionStore
│   │   ├── Config/             # 5-layer config loader, schema validation
│   │   ├── Commands/           # Command registry
│   │   ├── Storage/            # SessionStore (JSON), MemoryStore (CLAUDE.md)
│   │   ├── MCP/                # MCPClient, StdioTransport, tool bridge
│   │   ├── Hooks/              # HookSystem (lifecycle events)
│   │   ├── Plugins/            # PluginManager (manifest validation)
│   │   └── Features/           # FeatureFlags (compile-time + runtime)
│   ├── SwiftAgentCLI/          # CLI executable (ArgumentParser)
│   │   ├── EntryPoint.swift
│   │   ├── ChatCommand.swift   # Inline agent loop + all 43 tools
│   │   ├── TerminalRenderer.swift # ANSI rendering
│   │   ├── LineEditor.swift    # Raw-mode line editor
│   │   └── ...
│   └── SwiftAgentApp/          # macOS SwiftUI App (DeepSeek-powered)
│       ├── EntryPoint.swift    # @main App entry, windows, commands
│       ├── Window/             # NavigationSplitView layout
│       ├── Sidebar/            # Projects, threads, settings
│       ├── Content/            # Chat view, composer, messages
│       ├── RightTabs/          # Multi-tab right workspace
│       ├── DeepSeek/           # API client, models, Keychain
│       ├── Storage/            # SQLite persistence
│       ├── Settings/           # Independent settings window
│       │   ├── personal/       # General, Appearance, Config, Personalization, Shortcuts
│       │   ├── integrations/   # Appshots, MCP, Browser, Computer Use
│       │   ├── coding/         # Hooks, Connections, Git, Environments, Worktrees
│       │   └── archived/       # Archived chats
│       ├── Animations/         # Duration tokens, easing, transitions
│       ├── Errors/             # 16 error states (banner/toast/modal)
│       ├── Accessibility/      # a11y labels, contrast, reduce-motion
│       └── Shortcuts/          # 27+ keyboard shortcuts registry
├── Tests/
│   ├── SwiftAgentCoreTests/    # Core library tests (16 suites)
│   ├── SwiftAgentCLITests/     # Terminal rendering / input tests
│   ├── SwiftAgentAppTests/     # App unit tests (8 suites)
│   └── SwiftAgentAppUITests/   # XCUITest suites (5 suites)
├── specs/                      # Phase specifications
├── docs/                       # Architecture & roadmap docs
└── scripts/                    # Build & test scripts
```

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module boundaries, design decisions
- [docs/ROADMAP.md](docs/ROADMAP.md) — phase progress and priorities
- [docs/AI_HANDOFF.md](docs/AI_HANDOFF.md) — comprehensive alignment snapshot

## Development

```bash
swift build --disable-sandbox
swift test --disable-sandbox --no-parallel
```

---

## License

MIT © SwiftAgent Contributors
