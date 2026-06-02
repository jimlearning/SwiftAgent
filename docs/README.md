# SwiftAgent Documentation

## Index

| Doc | For | Read when... |
|-----|-----|--------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module boundaries, design decisions, detailed layout | You need to understand how modules fit together or where code should live |
| [ROADMAP.md](ROADMAP.md) | Phase progress, next priorities, blockers | You need to know what's done and what to work on next |
| [AI_HANDOFF.md](AI_HANDOFF.md) | Comprehensive CC-alignment snapshot | You're a new AI/developer onboarding, or need the full gap analysis |
| [PROMPT_CACHE_HIT_RATE.md](PROMPT_CACHE_HIT_RATE.md) | Prompt cache request-shape parity, measurements, and pitfalls | You're changing LLM request formatting or investigating cache hit rate |
| [../specs/](../specs/) | Executable feature specifications | You're implementing a specific feature and need acceptance criteria |

## Quick Start

```bash
swift build --disable-sandbox     # 0 errors, 0 warnings
swift test --disable-sandbox --no-parallel   # 171 tests, 47 suites
swift run --disable-sandbox swift-agent chat
```

## Current CLI Runtime Notes

- Background sub-agents are tracked through `TaskManager` with structured progress snapshots. `TaskOutput(block: true)` emits live progress while it waits, so the chat spinner can summarize running background tasks instead of showing only `Running TaskOutput...`.
- Terminal rendering tests cover CJK width, markdown tables, paste placeholders, parallel tool scheduling, and compact background task progress status.

## Project At a Glance

SwiftAgent is a Swift-native Claude Code reimplementation. Two modules:

- **SwiftAgentCore** — Agent runtime: types, tools, LLM adapter, agent loop, safety, config, MCP, hooks, plugins
- **SwiftAgentCLI** — Terminal: ArgumentParser commands, chat loop, ANSI rendering, line editor, markdown renderer

CC source reference: `~/CLI/claude-code/`
