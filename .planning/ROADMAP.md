# Roadmap: SwiftAgent FoundationModels API Reorganization

**21 requirements** | **8 phases** | Standard granularity | Parallel execution enabled

## Phase Dependency Graph

```
Phase 1: Foundation Types
  ↓
Phase 2: LanguageModelSession
  ↓
Phase 3: Simplified Tool Protocol
  ↓
┌─────────────────┬─────────────────┐
Phase 4:           Phase 5:           Phase 6:
AnthropicExecutor  Other Executors    Streaming & Structured Output
  ↓                  ↓                  ↓
└─────────────────┴─────────────────┘
  ↓
Phase 7: Tool Migration (depends on 3)
  ↓
Phase 8: Consumer Wiring & Cleanup (depends on all)
```

Phases 4, 5, 6 can run in parallel after Phase 2. Phase 7 can start after Phase 3.

---

### Phase 1: Foundation Types
**Goal:** Define all new public types with zero behavioral change. All 258+ existing tests pass.
**Mode:** mvp

**Requirements:** API-01, API-02, API-04, API-06, API-21

**Deliverables:**
- `LanguageModel` protocol in `Sources/SwiftAgentCore/LLM/LanguageModel.swift`
- `LanguageModelCapabilities` struct replacing dual `ModelInfo` types
- `LanguageModelError` enum (8 cases)
- `Transcript` struct with typed entries
- `AgentProfile` struct

**Success Criteria:**
1. All new types compile and are `Sendable`
2. Existing `ModelInfo` types marked `@available(*, deprecated)` with migration comment
3. All 258+ existing tests pass unchanged
4. New types have unit tests for Codable conformance, Sendable, and equality

**Critical Pitfalls (from PITFALLS.md):**
- Do NOT remove old `ModelInfo` types yet — deprecation only
- `Transcript` entries must map cleanly to existing `ContentBlock` for the transition period

---

### Phase 2: LanguageModelSession
**Goal:** Build the unified public API that replaces `QueryEngine` + `LLMClient` as primary consumer surface.
**Mode:** mvp

**Requirements:** API-03, API-05, API-14

**Deliverables:**
- `LanguageModelSession` actor with transcript, tool registry, streaming state
- `SessionEvent` enum (provider-agnostic events)
- `GenerationChannel` protocol
- Session-level `respond(to:generating:tools:)` method

**Success Criteria:**
1. Session can accept a prompt and return typed `SessionEvent` values
2. Transcript accumulates entries correctly across multi-turn conversation
3. Session can be initialized with `AgentProfile` (name, instructions, tools)
4. Unit tests for session lifecycle, transcript accumulation, event ordering
5. No dependency on `QueryEngine` or `LLMClient` in public API surface

**Critical Pitfalls:**
- Actor reentrancy: re-check state after every `await` suspension point
- Session must handle concurrent `respond()` calls gracefully (reject or queue)

---

### Phase 3: Simplified Tool Protocol
**Goal:** Reduce `Tool` protocol from 30+ members to ~6. Cross-cutting concerns move to `ToolMetadata`.

**Requirements:** API-07, API-08, API-09

**Deliverables:**
- Simplified `Tool` protocol (name, description, Input associatedtype, inputSchema, call)
- `ToolMetadata` struct (searchHint, isEnabled, isReadOnly, isConcurrencySafe, isDestructive, etc.)
- `ToolOutput` enum replacing `ToolResult` in public API
- `ToolRegistry` updated to accept metadata at registration time

**Success Criteria:**
1. New `Tool` protocol has ≤8 required members (target: 6)
2. `ToolMetadata` captures all 10+ cross-cutting members from old protocol
3. Existing tools can be registered with metadata, no tool code changes required
4. `ToolRegistry.toolDefinitions()` produces valid API-ready definitions from new protocol
5. All tool-related tests pass or are updated to new API

**Critical Pitfalls (P0):**
- `searchHint` has 55 overrides → must migrate to `ToolMetadata` BEFORE protocol change
- `isEnabled` (39 overrides) tied to feature flags → gating mechanism must work post-migration
- `shouldDefer` (33 overrides) → deferral logic preserved in `ToolMetadata.deferBehavior`

---

### Phase 4: AnthropicExecutor
**Goal:** Build first `LanguageModelExecutor` implementation wrapping existing `LLMClient` internals.

**Requirements:** API-10, API-11

**Deliverables:**
- `LanguageModelExecutor` protocol (Core internal)
- `AnthropicExecutor` implementing executor protocol
- `LLMClient`, `LLMStreamParser`, `StreamEvent`, `ContentBlockAccumulator` moved inside executor

**Success Criteria:**
1. `AnthropicExecutor` produces `SessionEvent` values from Anthropic Messages API responses
2. `safeParseJSON` and `ContentBlockAccumulator` preserved verbatim internally
3. Streaming works: Claude Opus/Sonnet/Haiku all produce correct events
4. Thinking/redacted thinking blocks translated correctly
5. Test suite for executor against recorded API responses (no live API calls)

**Critical Pitfalls:**
- Do NOT rewrite `safeParseJSON` — it handles double-stringified JSON edge cases
- Thinking block translation: Anthropic → SessionEvent mapping must preserve signature

---

### Phase 5: Other Executors
**Goal:** Unify DeepSeek into single executor, build OpenAI executor.
**Mode:** mvp (runs in parallel with Phase 4)

**Requirements:** API-12, API-13

**Deliverables:**
- `DeepSeekExecutor` — unified single code path replacing dual paths
- `OpenAIExecutor` — replacing current stub with full implementation
- Both implement `LanguageModelExecutor` protocol

**Success Criteria:**
1. `DeepSeekExecutor` handles both v4-pro and v4-flash models via single code path
2. `OpenAIExecutor` supports GPT-5.2, GPT-5.2-mini, o4 models
3. Both executors produce correct `SessionEvent` values
4. Test suite for each executor against recorded API responses

**Critical Pitfalls:**
- DeepSeek currently has two paths (Anthropic-compat `/anthropic/v1/messages` and standalone `/v1/chat/completions`) — pick ONE canonical path
- OpenAI o-series models have different API behavior (no system prompt in some modes)

---

### Phase 6: Streaming & Structured Output
**Goal:** Replace token-delta streaming with snapshot streaming. Add type-driven structured output.
**Mode:** mvp (runs in parallel with Phases 4-5)

**Requirements:** API-15, API-16

**Deliverables:**
- `PartiallyGenerated<T>` struct for snapshot streaming
- Runtime schema generation from `Codable` types via `Mirror` + `CodingKeys`
- `GenerationSchema` protocol for type-driven output
- Shadow-mode comparison: old token-delta path runs alongside new snapshot path

**Success Criteria:**
1. `PartiallyGenerated<T>` produces correct incremental snapshots for a `Codable` struct
2. Runtime schema generation produces valid JSON Schema from `Codable` types
3. Shadow mode: new snapshot output matches old token-delta output for all 258+ tests
4. No "HelloHello" double-rendering bug (snapshots not treated as deltas)

**Critical Pitfalls:**
- The "HelloHello" bug: consumers treating snapshots as deltas → double output
- Shadow mode required BEFORE cutting over any consumer
- `Mirror`-based approach may not handle all Codable edge cases (enums with associated values)

---

### Phase 7: Tool Migration
**Goal:** Migrate all 60+ tools to simplified protocol. Metadata extracted without per-tool code changes.

**Requirements:** API-17

**Deliverables:**
- `ToolMetadata` populated for all 60+ tools in `ToolRegistry`
- `searchHint` (55), `isEnabled` (39), `shouldDefer` (33) handled first
- Protocol extension on old `Tool` protocol mapping members to metadata (transitional)
- All 60+ tools compile and work with new session

**Success Criteria:**
1. All 60+ tools registered in `ToolRegistry` with complete metadata
2. `searchHint` values preserved for all 55 overrides
3. `isEnabled` feature-flag gating works for all 39 overrides
4. No tool behavior change — only API surface change
5. Tool-related tests all pass

**Critical Pitfalls:**
- `getActivityDescription` (12 overrides) — decide: metadata or keep as optional protocol member
- `getToolUseSummary` (11 overrides) — same decision needed
- Hook system coupled to `call()` signature — may need adapter during transition

---

### Phase 8: Consumer Wiring & Cleanup
**Goal:** Wire CLI and App to new API, remove deprecated types, all tests pass.

**Requirements:** API-18, API-19, API-20

**Deliverables:**
- `ChatCommand` (CLI) wired to `LanguageModelSession` (feature-flagged)
- `AppViewModel` (macOS App) wired to `LanguageModelSession` (feature-flagged)
- Old types removed: `LLMClient`, `StreamEvent` (public), `LLMStreamParser` (public), `ProviderRegistry`, dual `ModelInfo`
- Legacy adapter removed with hard deadline
- All 258+ tests pass, new test suites for all new types

**Success Criteria:**
1. CLI `--use-new-api` flag enables `LanguageModelSession` path; without flag, old path works
2. macOS App feature flag gates new session path
3. No `StreamEvent` reference outside executor implementations
4. Single `ModelInfo` type (via `LanguageModelCapabilities`)
5. Single DeepSeek code path
6. All 258+ existing tests pass + new test suites added
7. No `LLMClient` public API references remain

**Critical Pitfalls:**
- Legacy adapter must have a hard removal deadline (not indefinite backward compat)
- `MessageNormalizer` (17-pass pipeline) operates on `ContentBlock[]` — needs adaptation for `Transcript`

---

## Requirement Coverage

| REQ-ID | Phase | Requirement |
|--------|-------|-------------|
| API-01 | 1 | LanguageModel protocol |
| API-02 | 1 | LanguageModelCapabilities |
| API-03 | 2 | LanguageModelSession |
| API-04 | 1 | LanguageModelError |
| API-05 | 2 | SessionEvent |
| API-06 | 1 | Transcript |
| API-07 | 3 | Simplified Tool protocol |
| API-08 | 3 | ToolMetadata |
| API-09 | 3 | ToolOutput |
| API-10 | 4 | LanguageModelExecutor protocol |
| API-11 | 4 | AnthropicExecutor |
| API-12 | 5 | DeepSeekExecutor |
| API-13 | 5 | OpenAIExecutor |
| API-14 | 2 | GenerationChannel |
| API-15 | 6 | Snapshot streaming |
| API-16 | 6 | Type-driven structured output |
| API-17 | 7 | Tool migration (60+ tools) |
| API-18 | 8 | Consumer wiring |
| API-19 | 8 | Remove deprecated types |
| API-20 | 8 | All tests pass |
| API-21 | 1 | AgentProfile |

**Coverage: 21/21 requirements mapped (100%)**

## Parallel Execution Plan

| Wave | Phases | Dependency |
|------|--------|------------|
| Wave 1 | Phase 1 | None |
| Wave 2 | Phase 2 | Phase 1 |
| Wave 3 | Phase 3 | Phase 2 |
| Wave 4 | Phases 4, 5, 6 | Phase 2 (all three in parallel) |
| Wave 5 | Phase 7 | Phase 3 |
| Wave 6 | Phase 8 | Phases 4, 5, 6, 7 |

---
*Last updated: 2026-06-25*
