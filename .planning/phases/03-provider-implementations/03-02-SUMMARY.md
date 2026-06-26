---
phase: 03-provider-implementations
plan: 02
subsystem: providers
tags: [deepseek, llm, language-model, sse, anthropic-compat, openai-compat]

# Dependency graph
requires:
  - phase: 01-agentruntime-core-protocols
    provides: LanguageModel, LanguageModelExecutor, GenerationChannel, LanguageModelCapabilities
  - phase: 02-session-streaming-structured-output
    provides: SessionEvent, Transcript, Usage, AgentRuntimeError
  - phase: 03-provider-implementations
    plan: 01
    provides: AnthropicContentAccumulator, AnthropicSSEParser (used by AnthropicCompat path)

provides:
  - DeepSeekProvider (public struct, LanguageModel + LanguageModelExecutor)
  - APICompatibility (public enum, .anthropicCompatible / .openAICompatible)
  - DeepSeekTranscriptTranslator (internal, dual-mode Transcript -> wire format)
  - DeepSeekToolTranslator (internal, dual-mode RuntimeToolDefinition -> wire format)
  - DeepSeekSSEParser (actor, dual-mode SSE -> SessionEvent)
  - 27 integration tests covering both compat paths

affects: [03-03-openai-provider, 03-04-sqlite-memory-store, 04-migration-wiring-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Provider-as-LanguageModel+LExecutor: single struct conforms to both protocols"
    - "APICompatibility switch: one provider, two wire formats, identical SessionEvent output"
    - "SSE parser as actor: async parse method with compatibility dispatch"
    - "Tool accumulator reuse: AnthropicContentAccumulator reused for AnthropicCompat path"

key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekAPICompatibility.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekTranscriptTranslator.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekToolTranslator.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift
    - Tests/SwiftAgentCoreTests/DeepSeekProviderTests.swift
  modified: []

key-decisions:
  - "APICompatibility made public (not internal as planned) — required because DeepSeekProvider.init accepts it as a parameter and the provider is public (Rule 3 blocking fix)"
  - "DeepSeekSSEParser implemented as actor per plan specification; AnthropicCompat path reuses AnthropicContentAccumulator for tool call accumulation"

patterns-established:
  - "Dual-path provider: single struct with internal APICompatibility switch, both paths produce identical SessionEvent output"
  - "AnthropicCompat mitigation: NO anthropic-beta header, NO cache_control markers, NO thinking budget_tokens — all three rejected silently by DeepSeek"
  - "OpenAICompat SSE: multi-chunk tool call accumulation via OpenAIToolCallAccumulator, R1 reasoning_content -> thinkingDelta snapshots"
  - "Snapshot semantics: accumulated text/thinking sent each emission, not incremental deltas"

requirements-completed: [MODEL-03]

# Metrics
duration: 35min
completed: 2026-06-25
---

# Phase 03 Plan 02: DeepSeekProvider Summary

**DeepSeekProvider implementing LanguageModel + LanguageModelExecutor with dual API compatibility paths for Anthropic-compat and OpenAI-compat endpoints**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2
- **Files created:** 6 (5 source + 1 test)
- **Files modified:** 0
- **Tests written:** 27 (all passing, zero failures)

## Accomplishments

- Unified DeepSeek dual-code-path into single `DeepSeekProvider` struct conforming to both `LanguageModel` and `LanguageModelExecutor`
- `APICompatibility` enum with `.anthropicCompatible` (targets `/anthropic/v1/messages`) and `.openAICompatible` (targets `/v1/chat/completions`) cases
- AnthropicCompat path: strips anthropic-beta headers, cache_control markers, and thinking budget_tokens — all three DeepSeek silent-failure mitigations (PITFALLS.md Pitfall 1)
- OpenAICompat path: Chat Completions SSE parsing with R1 `reasoning_content` -> `thinkingDelta` snapshot mapping and multi-chunk tool call accumulation
- Cross-path equivalence: same `Transcript` input produces equivalent `SessionEvent` sequences from both compat modes
- AgentRuntimeImpl integration: `DeepSeekProvider` accepted as `modelProvider` without any provider-specific branching
- 27 fixture-based tests (no live API calls) — 13+ test methods covering init, translation, SSE parsing, tool translators, cross-path equivalence, and runtime integration

## Task Commits

Each task was committed atomically:

1. **Task 1: DeepSeekProvider struct, APICompatibility switch, and Anthropic-compat path** — `5437205` (feat)
2. **Task 2: DeepSeekProvider integration tests with fixture data for both compat paths** — `5e8c1e0` (test)

## Files Created

- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekAPICompatibility.swift` (28 lines) — Public enum with `.anthropicCompatible` and `.openAICompatible` cases, `endpointPath` and `defaultBaseURL` computed properties
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift` (218 lines) — Public struct conforming to `LanguageModel` + `LanguageModelExecutor` with model capability lookup, dual-path `respond()`, and shared `streamAndParse()`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekTranscriptTranslator.swift` (182 lines) — Internal struct with `translateAnthropicCompat()` (strips cache_control, maps thinking to text) and `translateOpenAICompat()` (ChatMessage format)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekToolTranslator.swift` (69 lines) — Internal struct with `translateAnthropicCompat()` (Anthropic format) and `translateOpenAICompat()` (OpenAI function-calling format)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift` (259 lines) — Actor with dual-mode `parse()` dispatching to AnthropicCompat (reuses `AnthropicContentAccumulator`) and OpenAICompat (custom `OpenAIToolCallAccumulator`) handlers
- `Tests/SwiftAgentCoreTests/DeepSeekProviderTests.swift` (774 lines) — 27 test methods covering both compat paths with fixture SSE data and `TestGenerationChannel` actor

## Decisions Made

- **APICompatibility made public**: The plan specified `internal enum` but `DeepSeekProvider.init(compatibility:)` is public — Swift requires public parameters to use public types. Changed to `public enum` (Rule 3 blocking fix).
- **Reused AnthropicContentAccumulator**: For the AnthropicCompat SSE path, reused the existing `AnthropicContentAccumulator` rather than duplicating its double-stringified JSON handling, `safeParseJSON`, and `parseUsage` logic
- **DeepSeekSSEParser as actor**: Followed the plan's specification of `actor` for the SSE parser, even though a `struct` pattern (like `AnthropicSSEParser`) would also work. The actor provides internal state isolation for the per-path parsing methods

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] APICompatibility enum visibility**
- **Found during:** Task 1 (initial build)
- **Issue:** Swift compiler error — public `DeepSeekProvider.init(compatibility:)` parameter used internal type `APICompatibility`. A public API cannot expose internal types.
- **Fix:** Changed `enum APICompatibility` to `public enum APICompatibility`. Updated doc comment from "Internal enum" to "Controls which DeepSeek API endpoint the provider targets."
- **Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekAPICompatibility.swift`
- **Verification:** `swift build --target SwiftAgentCore` exits 0, all 27 tests pass
- **Committed in:** `5437205` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minimal — visibility change on a type that was already part of the public API surface through the provider's initializer. No scope creep.

## Issues Encountered

- `[String: Any?]` dictionary type cannot be used in array literals where `[String: Any]` is expected — fixed by explicitly constructing fixture dictionaries as `[String: Any]` and omitting nil keys rather than using `nil as String?` values

## Verification Summary

All plan acceptance criteria met:

- `grep -rn "StreamEvent" Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/` — zero matches
- `grep -rn "anthropic-beta" ...` — zero code references (comment-only documentation)
- `grep -rn "cache_control" ...` — zero code references (comment-only documentation)
- `grep -c "nonisolated(unsafe)" ...` — zero annotations across all 5 files
- `swift build --target SwiftAgentCore` — exits 0, zero errors, zero warnings
- `swift test --filter DeepSeekProviderTests` — 27 tests, 0 failures
- Cross-path equivalence: test verifies both compat paths produce equivalent SessionEvent sequences
- `DeepSeekProvider` conforms to both `LanguageModel` and `LanguageModelExecutor` — verified by `AgentRuntimeImpl.init(modelProvider:)` accepting it

## User Setup Required

None — no external service configuration required. API key is passed at construction time via `DeepSeekProvider.init(apiKey:)`.

## Next Phase Readiness

- DeepSeek provider fully implemented and tested — ready for Plan 03-03 (OpenAIProvider) and Plan 03-04 (SQLiteMemoryStore + PermissionEngine bridge)
- Zero modifications to existing files — all code is additive in new `DeepSeek/` directory
- Legacy dual paths (`Sources/SwiftAgentApp/LLM/DeepSeekProvider.swift` and `Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift`) remain untouched for Phase 4 migration

---
*Phase: 03-provider-implementations*
*Completed: 2026-06-25*

## Self-Check: PASSED

- [x] All 6 created files exist on disk
- [x] Both commits confirmed: `5437205` (Task 1 feat), `5e8c1e0` (Task 2 test)
- [x] `swift build --target SwiftAgentCore` exits 0 with zero errors
- [x] `swift test --filter DeepSeekProviderTests` — 27 tests, 0 failures
- [x] Zero StreamEvent references in DeepSeek/ directory
- [x] Zero nonisolated(unsafe) annotations in DeepSeek/ directory
