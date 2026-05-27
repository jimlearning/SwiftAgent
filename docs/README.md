# SwiftAgent Documentation

SwiftAgent is a Swift-native AI coding agent CLI, the Swift/Apple-platform counterpart to Claude Code.

## Architecture

Two-module structure:
- **SwiftAgentCore** — Shared agent runtime, LLM adapters, tools, workspace/config/conversation state
- **SwiftAgentCLI** — ArgumentParser commands, chat loop orchestration, terminal rendering, user interaction

## Quick Links

- [ARCHITECTURE.md](ARCHITECTURE.md) — Module boundaries and design decisions
- [ROADMAP.md](ROADMAP.md) — Phase priorities and progress
- [../specs/](../specs/) — Feature specifications with acceptance criteria

## Getting Started

```bash
swift build --disable-sandbox     # 0 errors, 0 warnings
swift test --disable-sandbox --no-parallel   # 171 tests pass
swift run --disable-sandbox swift-agent chat
```
