# SwiftAgent

<p align="center">
  <strong>AI coding agent CLI — pure Swift implementation of Claude Code</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/macOS-14+-lightgrey?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/tests-133%20passing-brightgreen" alt="133 tests">
</p>

SwiftAgent is a Swift-native coding agent CLI modeled after Claude Code. It provides the full agentic coding experience: read, write, edit, search, shell, git, permission control, MCP integration, multi-agent delegation, and more.

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
```

### Slash Commands (in-chat)

| Command | Action |
|---|---|
| `/help` | Show available commands |
| `/clear` | Clear the screen |
| `/exit`, `/quit` | Exit the session |

---

## Features

### Agentic Loop
User input → stream LLM response → parse tool calls → execute tools → loop back. Context auto-compaction with token budget awareness.

### Tools (6 built-in)
| Tool | Description |
|---|---|
| `ReadTool` | Read files with offset/limit |
| `WriteTool` | Write/create files |
| `EditTool` | Exact string replacement editing |
| `BashTool` | Shell execution with dangerous pattern detection |
| `GlobTool` | File pattern matching (`**/*.swift`) |
| `GrepTool` | Regex content search |

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
- `SubAgentManager` for isolated agent execution
- `TaskManager` (actor) for background task lifecycle
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
│   │   ├── LLM/                # Anthropic API client, SSE stream parser, retry
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
│   └── SwiftAgentCLI/          # CLI executable (ArgumentParser)
│       ├── EntryPoint.swift
│       ├── ChatCommand.swift
│       ├── TerminalRenderer.swift
│       ├── TerminalCapability.swift
│       ├── StatusLine.swift
│       └── ColorTheme.swift
├── Tests/
│   └── SwiftAgentCoreTests/    # 133 tests, 39 suites
├── specs/                      # Phase specifications
├── docs/                       # Architecture & roadmap docs
└── scripts/                    # Build & test scripts
```

---

## Development

### Building

```bash
swift build --disable-sandbox
```

### Testing

```bash
swift test --disable-sandbox --no-parallel
```

### Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module boundaries and design decisions.
See [docs/ROADMAP.md](docs/ROADMAP.md) for phase progress and priorities.

---

## License

MIT © SwiftAgent Contributors
