# Project State

**Project:** SwiftAgent FoundationModels API Reorganization
**Initialized:** 2026-06-25
**Last Updated:** 2026-06-25

## Current Phase

**Phase:** 0 — Project initialized, ready to start Phase 1

## Phase Progress

| Phase | Status | Requirements | Key Deliverable |
|-------|--------|-------------|-----------------|
| 1: Foundation Types | ⬜ Pending | API-01,02,04,06,21 | LanguageModel protocol, Capabilities, Error, Transcript |
| 2: LanguageModelSession | ⬜ Pending | API-03,05,14 | Session actor, SessionEvent, GenerationChannel |
| 3: Simplified Tool Protocol | ⬜ Pending | API-07,08,09 | New Tool protocol (~6 members), ToolMetadata |
| 4: AnthropicExecutor | ⬜ Pending | API-10,11 | First executor, wraps LLMClient internals |
| 5: Other Executors | ⬜ Pending | API-12,13 | DeepSeekExecutor (unified), OpenAIExecutor |
| 6: Streaming & Output | ⬜ Pending | API-15,16 | Snapshot streaming, type-driven output |
| 7: Tool Migration | ⬜ Pending | API-17 | 60+ tools to new protocol |
| 8: Wiring & Cleanup | ⬜ Pending | API-18,19,20 | Consumer wiring, deprecation removal, tests |

## Active Decisions

- FoundationModels framework requires macOS 26+ → build own equivalent protocols
- `@Generable` macro deferred → runtime Mirror-based approach for now
- DeepSeek dual paths unified into single executor
- Anthropic wire types become executor-internal
- Tool protocol reduces from 30+ to ~6 members; metadata moves to registry

## Blockers

None

## Next Actions

1. `/gsd-plan-phase 1` — Plan Phase 1: Foundation Types
2. Define `LanguageModel` protocol shape
3. Define `LanguageModelCapabilities` fields
4. Define `LanguageModelError` cases
5. Define `Transcript` entry types
6. Define `AgentProfile` struct

---
*Last updated: 2026-06-25*
