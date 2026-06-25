# Project: SwiftAgent FoundationModels API Reorganization

## What This Is

Reorganize SwiftAgent's AI Agent API to follow Apple's FoundationModels Agent Runtime architecture (WWDC25→WWDC26→WWDC27 trajectory). The current API is Anthropic-specific with provider abstraction at the wrong level. The target is an **Agent Runtime** where models are swappable plugins behind a `LanguageModel` protocol, with `LanguageModelSession` as the unified public API surface.

## Core Value

**Models become plugins, not the architecture.** Today SwiftAgent has Anthropic-specific wire types (`ContentBlock`, `StreamEvent`) leaking through the public API, two separate DeepSeek code paths, and a 30-member `Tool` protocol. The reorganized API treats FoundationModels/Claude/OpenAI/DeepSeek as interchangeable inference providers behind a single `LanguageModel` abstraction — exactly as Apple's WWDC26 `LanguageModel` protocol enables.

## Context

- **Brownfield refactoring** of `/Users/jim/SwiftAgent` (Swift 6, SPM, 3 targets)
- **Current state:** `SwiftAgentCore/LLM/` (LLMClient, LLMStreamParser, ModelRegistry, RetryPolicy), `SwiftAgentCore/Agent/` (QueryEngine, ToolExecutor, StreamRenderer), `SwiftAgentCore/Types/` (Tool, Conversation, StreamEvent), `SwiftAgentApp/LLM/` (LLMProvider, ProviderRegistry, AnthropicProvider, DeepSeekProvider, OpenAIProvider), `SwiftAgentApp/DeepSeek/` (DeepSeekClient, standalone)
- **Codebase mapped:** `.planning/codebase/` (7 docs, 1846 lines total)
- **258+ tests, 60+ suites** — must keep passing
- **References:** Apple FoundationModels docs (WWDC25-286, WWDC25-301, WWDC26-339), `AboutAppleFoundationModels.md`

## Target Architecture

```
App / CLI
  │
  ▼
LanguageModelSession          ← unified public API
  │
  ├── Instructions
  ├── Transcript (history)
  ├── Tools
  ├── Profile (agent identity)
  │
  ▼
LanguageModel protocol        ← model abstraction
  │
  ├── AnthropicExecutor       ← Claude (maps to Anthropic Messages API)
  ├── DeepSeekExecutor        ← DeepSeek (unified single path)
  ├── OpenAIExecutor          ← GPT/O-series
  └── (future: AppleExecutor, MLXExecutor, GeminiExecutor)
```

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Design for Agent Runtime, not LLM SDK | FoundationModels WWDC26→27 trajectory; Apple itself is abstracting models into plugins | Architecture centers on `LanguageModelSession`, not model-specific types |
| `LanguageModel` protocol as model boundary | Matches Apple's WWDC26 direction; enables swappable backends | All provider-specific code lives behind this protocol |
| Simplify `Tool` protocol to ~4 members | FoundationModels `Tool` has name, description, Arguments, call() | Current 30+ member protocol radically reduced |
| Snapshot streaming over token deltas | FoundationModels uses `AsyncSequence<PartiallyGenerated<T>>` | Higher-level streaming model, hides per-provider wire format |
| Unify DeepSeek paths | Currently two separate code paths (Anthropic-compat + standalone) | Single `DeepSeekExecutor` implementing `LanguageModel` |
| `@Generable`-style structured output | FoundationModels derives schema from Swift types at compile time | Replace manual `JSONSchema` with type-driven approach |

## Requirements

### Validated

- ✓ Tool system with 43+ tools, one per file — existing
- ✓ Permission engine with allow/deny/ask rules — existing
- ✓ File-based CC-compatible persistence — existing
- ✓ Streaming with thinking/redacted thinking support — existing
- ✓ MCP server integration — existing
- ✓ Hook system — existing
- ✓ Model registry with aliases — existing
- ✓ Retry with exponential backoff — existing
- ✓ Context compaction — existing
- ✓ 258+ tests, 60+ suites — existing

### Active

- [ ] REQ-API-01: `LanguageModel` protocol defining model capabilities and execution interface
- [ ] REQ-API-02: `LanguageModelSession` as unified public API replacing `QueryEngine` + `LLMClient` as primary surface
- [ ] REQ-API-03: `LanguageModelExecutor` protocol for backend implementations (Anthropic, DeepSeek, OpenAI)
- [ ] REQ-API-04: Simplified `Tool` protocol (~4 members matching FoundationModels shape)
- [ ] REQ-API-05: Snapshot streaming via `AsyncSequence<PartiallyGenerated<T>>`
- [ ] REQ-API-06: Type-driven structured output replacing manual `JSONSchema`
- [ ] REQ-API-07: Unified DeepSeek backend (single `DeepSeekExecutor`, not two code paths)
- [ ] REQ-API-08: `LanguageModelCapabilities` struct replacing dual `ModelInfo` types
- [ ] REQ-API-09: `LanguageModelError` enum replacing fragmented error types
- [ ] REQ-API-10: Agent `Profile` concept (identity + tools + instructions bundle)
- [ ] REQ-API-11: Wire-format isolation — `StreamEvent`/`ContentBlock` become internal per-executor details
- [ ] REQ-API-12: All 258+ existing tests pass after reorganization

### Out of Scope

- Building `@Generable`/`@Guide` Swift macros — use runtime equivalent initially
- On-device Apple model integration (SystemLanguageModel) — future phase
- Multi-Agent orchestration (AgentGraph) — future phase
- Vision/multimodal support — future phase
- RAG/Spotlight integration — future phase
- Modifying CLI or App UI layer — API surface only

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

---
*Last updated: 2026-06-25 after initialization*
