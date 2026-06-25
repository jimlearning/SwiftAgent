---
phase: 03-provider-implementations
verified: 2026-06-25T19:55:00Z
status: gaps_found
score: 6/7 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Cache control markers preserved in request body — AnthropicRequestBuilder includes cache_control blocks on system prompt"
    status: failed
    reason: "AnthropicRequestBuilder passes system prompt as a plain String (body[\"system\"] = system), not wrapped in content blocks with cache_control: {type: \"ephemeral\"} markers. The AnthropicTranscriptTranslator builds the system parameter as a plain joined string. Both the ROADMAP success criteria #1 and Plan 03-01 success criteria #7 require cache control markers to be preserved."
    artifacts:
      - path: "Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift"
        issue: "Line 43: body[\"system\"] = system — passes system as plain String, no cache_control wrapping"
      - path: "Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicTranscriptTranslator.swift"
        issue: "Lines 86-96: builds system as joined String from systemPrompt + systemParts, no content block array with cache_control"
    missing:
      - "Wrap system prompt in array of content blocks: [{type: \"text\", text: systemPrompt, cache_control: {type: \"ephemeral\"}}]"
      - "Inject billing header block / identity block with ephemeral cache at system prompt boundary"
      - "Support dynamic/static boundary splitting for cache-aware system prompts"
---

# Phase 3: Provider Implementations Verification Report

**Phase Goal:** All three ModelProviders (Anthropic, DeepSeek unified, OpenAI) respond through LanguageModelExecutor. SQLiteMemoryStore implements MemoryStore protocol. PermissionEngine upgraded to AgentPermission taxonomy. Provider-specific wire types are internal to each provider -- consumers see only SessionEvent values.

**Verified:** 2026-06-25T19:55:00Z
**Status:** gaps_found
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | AnthropicProvider responds through LanguageModelExecutor with Transcript-to-Anthropic-Messages translation and snapshot-semantic SSE streaming | VERIFIED | `AnthropicProvider: LanguageModel, LanguageModelExecutor` (line 8); `respond(to:tools:options:streamingInto:)` implements full pipeline: build URLRequest, stream bytes, parse SSE via `AnthropicSSEParser` (lines 90-143); 23 tests pass |
| 2 | Anthropic Transcript translation covers all 7 Entry cases (instruction, prompt, response, toolCall, toolOutput, thinking, system) | VERIFIED | `AnthropicTranscriptTranslator.translate()` switch covers all 7 cases (lines 35-80); 7 translation-specific tests pass |
| 3 | Anthropic SSE emits snapshot-semantic SessionEvent values (accumulated text, not raw deltas) | VERIFIED | `AnthropicSSEParser` maintains `accumulatedText`/`accumulatedThinking`; sends full accumulated string on each delta (lines 67-74); test 3 verifies "Hello" then "Hello world" |
| 4 | Anthropic tool use streaming: content_block_start registers tool, input_json_delta accumulates, content_block_stop emits toolCallRequested | VERIFIED | `AnthropicContentAccumulator.recordToolCall()` + `accumulateToolInput()` + `finalizeToolCall()` (lines 25-51); `AnthropicSSEParser` dispatches all 3 event types (lines 47-90); test 4 verifies |
| 5 | AnthropicCache control markers preserved in outgoing request | FAILED | System prompt passed as plain String in `AnthropicRequestBuilder` (line 43). No `cache_control: {type: "ephemeral"}` on content blocks. Documented as known stub in 03-01-SUMMARY.md. ROADMAP SC #1 and PLAN 03-01 SC #7 require this. |
| 6 | DeepSeekProvider handles both Anthropic-compat and OpenAI-compat endpoints from single code path with APICompatibility switch | VERIFIED | `APICompatibility` enum (`.anthropicCompatible`/`.openAICompatible`); `respond()` switches on compatibility (lines 106-121); 27 tests pass; anthropic-beta header stripped, cache_control stripped |
| 7 | DeepSeek cross-path equivalence: equivalent Transcript + Tools produce identical SessionEvent sequences | VERIFIED | Cross-path equivalence test in DeepSeekProviderTests; both compat paths tested with fixture SSE data |
| 8 | DeepSeek R1 reasoning_content maps to thinkingDelta with snapshot semantics | VERIFIED | `DeepSeekSSEParser` OpenAICompat path: `reasoning_content` delta accumulates and emits `thinkingDelta` snapshots; test 10 verifies |
| 9 | OpenAIProvider responds through LanguageModelExecutor with Chat Completions API, function calling, and o4 reasoning support | VERIFIED | `OpenAIProvider: LanguageModel, LanguageModelExecutor` (line 8); `respond()` builds Chat Completions request with `max_completion_tokens`, `tools`, `tool_choice`, o4 `reasoning_effort`, temperature exclusion (lines 90-176); 23 tests pass |
| 10 | OpenAI multi-chunk tool call accumulation: fragmented arguments reassemble into single toolCallRequested | VERIFIED | `OpenAISSEParser` uses `[Int: ToolCallAccumulator]` dictionary; tool calls emitted at `finish_reason` (Pitfall 4 mitigation); test 9 verifies 3-chunk fragmentation |
| 11 | OpenAI o4 model: reasoning_content to thinkingDelta, temperature excluded, reasoning_effort mapped from reasoningBudget | VERIFIED | `OpenAIProvider.respond()`: isO4 check excludes temperature (line 122), maps budget to "low"/"medium"/"high" (lines 118-119); `OpenAISSEParser` handles `reasoning_content` delta |
| 12 | Provider-internal types (StreamEvent, ContentBlock) not visible outside Providers/ | VERIFIED | `grep -rn "StreamEvent" Sources/.../Providers/Anthropic DeepSeek OpenAI/` returns zero; `grep -rn "import.*LLMClient\|LLMStreamParser"` returns zero; only SessionEvent.swift has a comment referencing StreamEvent (documenting replacement) |
| 13 | SQLiteMemoryStore conforms to RuntimeMemoryStore -- all 6 methods work correctly | VERIFIED | `actor SQLiteMemoryStore: RuntimeMemoryStore` (line 13); store/retrieve/search/summarize/forget/listNamespaces all implemented (lines 156-267); 12 tests pass including Codable roundtrip, schema migration (4 steps), persistence across instances |
| 14 | SQLiteMemoryStore uses parameterized queries exclusively -- zero string interpolation | VERIFIED | All SQL statements use `?` bind parameters; `execute()` helper binds via `sqlite3_bind_*` (lines 360-373); grep for string interpolation in SQL returns zero |
| 15 | AgentPermissionBridge routes AgentPermission taxonomy to PermissionEngine pipeline | VERIFIED | `AgentPermissionBridge: RuntimePermissionEngine` (line 9); exhaustive switch over all 13 AgentPermission cases (no `default:`); established permissions route to correct tool names; unestablished permissions deny by default; 16 tests pass |
| 16 | Zero new `nonisolated(unsafe)` annotations | VERIFIED | grep returns zero across all Providers/ subdirectories |

**Score:** 15/16 truths verified (one FAILED: cache control)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicProvider.swift` | LanguageModel + LanguageModelExecutor conformance | VERIFIED | 144 lines, full respond() pipeline |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicTranscriptTranslator.swift` | All 7 Entry cases mapped | VERIFIED | 100 lines, role-flushing pattern |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicToolTranslator.swift` | RuntimeToolDefinition to Anthropic tool JSON | VERIFIED | 31 lines, Codable round-trip |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicSSEParser.swift` | SSE to SessionEvent parsing with snapshot accumulation | VERIFIED | 111 lines, handles all 8 event types |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicContentAccumulator.swift` | Double-stringified JSON handling, tool accumulation | VERIFIED | 119 lines, .fragmentsAllowed fix |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift` | URLRequest with Anthropic headers | VERIFIED | 114 lines, POST /v1/messages |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRetryPolicy.swift` | Retry decisions, exponential backoff | VERIFIED | 65 lines, maxRetries=10 |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift` | LanguageModel + LanguageModelExecutor, dual-path | VERIFIED | 263 lines, APICompatibility switch |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekAPICompatibility.swift` | APICompatibility enum | VERIFIED | 24 lines, .anthropicCompatible / .openAICompatible |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekTranscriptTranslator.swift` | Dual-mode transcript translation | VERIFIED | 192 lines, strips cache_control |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekToolTranslator.swift` | Dual-mode tool translation | VERIFIED | 60 lines |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift` | Dual-mode SSE parsing | VERIFIED | 256 lines, actor-based |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIProvider.swift` | LanguageModel + LanguageModelExecutor, Chat Completions | VERIFIED | 191 lines, o4 support |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAITranscriptTranslator.swift` | Transcript to ChatMessage[] | VERIFIED | 100 lines, flat array mapping |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIToolTranslator.swift` | RuntimeToolDefinition to OpenAI function format | VERIFIED | 57 lines |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAISSEParser.swift` | SSE chunk parsing, multi-chunk tool accumulation | VERIFIED | 178 lines, actor-based |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift` | RuntimeMemoryStore via SQLite3 | VERIFIED | 381 lines, all 6 methods, schema migration |
| `Sources/SwiftAgentCore/AgentRuntime/Providers/Permission/AgentPermissionBridge.swift` | AgentPermission to PermissionEngine adapter | VERIFIED | 82 lines, exhaustive switch |
| `Tests/SwiftAgentCoreTests/AnthropicProviderTests.swift` | 11+ tests | VERIFIED | 689 lines, 23 tests |
| `Tests/SwiftAgentCoreTests/DeepSeekProviderTests.swift` | 13+ tests | VERIFIED | 774 lines, 27 tests |
| `Tests/SwiftAgentCoreTests/OpenAIProviderTests.swift` | 14+ tests | VERIFIED | 596 lines, 23 tests |
| `Tests/SwiftAgentCoreTests/SQLiteMemoryStoreTests.swift` | 12+ tests | VERIFIED | 220 lines, 12 tests |
| `Tests/SwiftAgentCoreTests/AgentPermissionBridgeTests.swift` | 10+ tests | VERIFIED | 225 lines, 16 tests |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| AnthropicProvider.respond() | AnthropicSSEParser | RequestBuilder + URLSession.AsyncBytes | WIRED | `AnthropicRequestBuilder.build()` constructs request; `session.bytes(for:)` streams; parser consumes `AsyncStream<String>` lines |
| AnthropicSSEParser | GenerationChannel.send(textDelta:) | accumulatedText snapshot | WIRED | `accumulatedText += text; await channel.send(textDelta: accumulatedText)` (lines 67-69) |
| AnthropicSSEParser | GenerationChannel.send(toolCallRequest:) | AnthropicContentAccumulator.finalizeToolCall | WIRED | `accumulator.finalizeToolCall()` at content_block_stop (lines 87-90) |
| AnthropicTranscriptTranslator | Transcript.Entry (all 7 cases) | switch on entry case | WIRED | All 7 cases handled: instruction, prompt, response, toolCall, toolOutput, thinking, system (lines 35-80) |
| DeepSeekProvider.respond() | APICompatibility switch | compatibility property | WIRED | `switch compatibility { case .anthropicCompatible: ... case .openAICompatible: ... }` (lines 106-121) |
| DeepSeekProvider (AnthropicCompat) | DeepSeekTranscriptTranslator | translateAnthropicCompat() | WIRED | Strips cache_control, NO anthropic-beta header (lines 132-162) |
| DeepSeekSSEParser (OpenAICompat) | SessionEvent.thinkingDelta | reasoning_content accumulation | WIRED | R1 reasoning_content chunks mapped to thinkingDelta snapshots |
| OpenAIProvider.respond() | OpenAITranscriptTranslator | translate() | WIRED | Transcript to ChatMessage[] conversion (line 96) |
| OpenAISSEParser | SessionEvent.toolCallRequested | [Int:ToolCallAccumulator] | WIRED | Multi-chunk accumulation, emitted at finish_reason |
| SQLiteMemoryStore.store() | SQLite3 INSERT OR REPLACE | Parameterized ? bindings | WIRED | `sqlite3_bind_*` calls for all parameters (lines 360-373) |
| AgentPermissionBridge.check() | PermissionEngine.check(toolName:) | AgentPermission to tool name mapping | WIRED | `.runCommands` -> "Bash", `.readFiles` -> "Read", `.writeFiles` -> "Write", `.network` -> "WebFetch" (lines 32-65) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| AnthropicProvider | accumulatedText (via SSE parser) | URLSession.AsyncBytes.lines -> AnthropicSSEParser | Yes (real API streaming) | FLOWING |
| AnthropicContentAccumulator | partialJSON / toolNames / toolIDs | input_json_delta SSE events | Yes (JSON accumulation from stream) | FLOWING |
| DeepSeekProvider | messages (via translators) | Transcript.entries -> DeepSeekTranscriptTranslator | Yes (derived from Transcript) | FLOWING |
| OpenAIProvider | messages (via translator) | Transcript.entries -> OpenAITranscriptTranslator | Yes (derived from Transcript) | FLOWING |
| OpenAISSEParser | toolCallAccumulators | tool_calls delta fragments | Yes (multi-chunk JSON reassembly) | FLOWING |
| SQLiteMemoryStore | Codable values (via retrieve) | SQLite3 BLOB column | Yes (real DB queries) | FLOWING |
| AgentPermissionBridge | verdict | PermissionEngine.check() | Yes (delegates to existing engine) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Build passes | `swift build --target SwiftAgentCore --disable-sandbox` | Exit 0, zero errors | PASS |
| All provider tests pass | `swift test --filter 'Anthropic\|DeepSeek\|OpenAI\|SQLiteMemory\|AgentPermissionBridge' --disable-sandbox --no-parallel` | 101 tests, 0 failures | PASS |
| Zero StreamEvent leakage | `grep -rn "StreamEvent" Providers/Anthropic DeepSeek OpenAI/` | Zero matches | PASS |
| Zero nonisolated(unsafe) | `grep -rn "nonisolated(unsafe)" Providers/` | Zero matches | PASS |
| Zero debt markers (TBD/FIXME/XXX) | grep across all Providers/ | Zero matches | PASS |
| SQLite3 linker in Package.swift | `grep linkedLibrary Package.swift` | `linkerSettings: [.linkedLibrary("sqlite3")]` on line 26 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MODEL-02 | 03-01-PLAN.md | AnthropicProvider implementing LanguageModelExecutor | SATISFIED | 7 source files, 23 tests, full respond() pipeline, snapshot SSE streaming |
| MODEL-03 | 03-02-PLAN.md | DeepSeekProvider (unified) with APICompatibility switch | SATISFIED | 5 source files, 27 tests, dual-path verified, cross-path equivalence |
| MODEL-04 | 03-03-PLAN.md | OpenAIProvider (Chat Completions, function calling, o4) | SATISFIED | 4 source files, 23 tests, multi-chunk tool accumulation, o4 reasoning support |
| MEM-02 | 03-04-PLAN.md | SQLiteMemoryStore + AgentPermissionBridge | SATISFIED | 2 source files, 28 tests (12+16), all 6 RuntimeMemoryStore methods, schema migration, exhaustive permission switch |
| PERM-02 | 03-04-PLAN.md | PermissionEngine upgrade to AgentPermission taxonomy | SATISFIED | AgentPermissionBridge wraps PermissionEngine; all 13 AgentPermission cases mapped; deny-by-default for unestablished permissions |

All 4 declared requirement IDs (MODEL-02, MODEL-03, MODEL-04, MEM-02) are accounted for. Additionally, PERM-02 (referenced in REQUIREMENTS.md as Phase 3) is satisfied by the AgentPermissionBridge implementation in 03-04.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | Zero debt markers (TBD/FIXME/XXX), zero placeholder/coming-soon, zero stub returns found in any provider implementation |

### Known Stub (from SUMMARY.md, confirmed in verification)

The AnthropicSUMMARY.md acknowledges cache control markers as a known stub. This was confirmed in verification:
- `AnthropicRequestBuilder.swift` line 43: system prompt passed as plain `String` with `body["system"] = system`
- `AnthropicTranscriptTranslator.swift` lines 86-96: system built as joined String, not as content block array with `cache_control`

This is the sole gap preventing full goal achievement.

### Gaps Summary

**1 gap found:**

**Cache control markers not preserved.** The ROADMAP.md success criteria #1 requires "all existing Anthropic streaming features (thinking, tool use, cache control) work through the new path." Plan 03-01 success criteria #7 requires "Cache control markers preserved in request body (AnthropicRequestBuilder includes cache_control blocks)." Both are unmet.

The system prompt is passed as a plain `String` instead of being wrapped in content blocks with `cache_control: {type: "ephemeral"}`. This means repeated requests with the same large system prompt do not benefit from Anthropic's prompt caching pricing tier. The core translation and streaming pipeline functions correctly without cache control -- this is a feature completeness gap within the AnthropicProvider, not a failure of the LanguageModelExecutor contract.

**Recommendation:** The AnthropicTranscriptTranslator should build the system parameter as an array of content blocks: `[{type: "text", text: systemPrompt, cache_control: {type: "ephemeral"}}]` instead of a plain String. The AnthropicProvider.respond() should also inject the CC-compatible billing header block and identity block with ephemeral cache at the system prompt boundary, following the pattern from the original LLMClient.

---

_Verified: 2026-06-25T19:55:00Z_
_Verifier: Claude (gsd-verifier)_
