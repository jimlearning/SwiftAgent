# SwiftAgent — Claude Code 1:1 Swift Reimplementation

## Build & Test

```bash
swift build --disable-sandbox
swift test --disable-sandbox --no-parallel
```

Always use `--disable-sandbox` (file system tests). Use `--no-parallel` (shared state).

## Project Structure

- `Sources/SwiftAgentCore/` — reusable agent runtime library
  - `Types/` — domain types (Tool, Conversation, Config, Permission, etc.)
  - `Tools/` — 43 tools, one per file, CC-aligned
  - `Agent/` — QueryEngine, ToolExecutor, StreamRenderer, Compactor, etc.
  - `LLM/` — LLMClient, LLMStreamParser, ModelRegistry, RetryPolicy
  - `Safety/` — PermissionEngine, SafetyChecker
  - `MCP/`, `Config/`, `State/`, `Hooks/`, `Plugins/`, `Storage/`, `Commands/`
- `Sources/SwiftAgentCLI/` — CLI entry point
  - `ChatCommand.swift` — inline agent loop + 43 tool registrations
  - `TerminalRenderer.swift` — ANSI rendering (banner, left-border, panel, spinner)
  - `LineEditor.swift` — raw-mode terminal line editor with history
  - `DebugLogger.swift` — JSONL debug logging for API interactions

## Key Conventions

- Tools use PascalCase LLM names (e.g. `"Bash"`, not `"bash"`)
- Tool JSON schema properties use camelCase (CC convention)
- Struct-based Tool protocol conformance, one file per tool
- Actor-based state management (AppState)
- Build passes with zero errors, 164 tests in 43 suites all green

## ChatCommand Architecture

The inline agent loop (not QueryEngine) handles:
1. `conversationHistory: [Message]` accumulates across turns
2. Stream events: textDelta, thinkingDelta (dimmed display), inputJSONDelta
3. Manual tool input JSON accumulation + parse at contentBlockStop
4. ToolExecutor.execute() for all 43 tools
5. Assistant messages include thinking blocks (API requirement)
6. Tool results sent as toolResult content blocks keyed by toolUseID
7. Max 25 iterations per turn, auto-completion detection

## Debug Logging

`--debug` flag writes to `~/.swift-agent/logs/debug-YYYYMMDD-HHmmss.jsonl`.
Contains: request body, response status, raw SSE events. API keys masked.
