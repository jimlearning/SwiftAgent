---
phase: 03-provider-implementations
fixed_at: 2026-06-25T00:00:00Z
review_path: .planning/phases/03-provider-implementations/03-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report — Provider Implementations

**Source review:** .planning/phases/03-provider-implementations/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (1 Critical, 6 Warning)
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: Request body JSON encoding failures silently swallowed in four provider locations

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift`, `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicProvider.swift`, `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift`, `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIProvider.swift`
**Commit:** 69d53ba
**Applied fix:** Replaced `try?` with proper guard/throw pattern in all four locations. `AnthropicRequestBuilder.build()` now throws `AgentRuntimeError.invalidResponse` on encoding failure, caught by `AnthropicProvider.respond()` which fails the channel. DeepSeekProvider (both paths) and OpenAIProvider now guard-let the encoding and fail the channel with `invalidResponse` on failure instead of silently sending nil `httpBody`.

### WR-01: `SQLiteMemoryStore` silently ignores directory creation failure

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift`
**Commit:** 511cdbc
**Applied fix:** Replaced `try?` with `do/catch` block that throws `AgentRuntimeError.storageFull(availableBytes: 0)` on directory creation failure, masking the root cause less than before.

### WR-02: `SQLiteMemoryStore.init` throws misleading `storageFull` for any open failure

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift`
**Commit:** 511cdbc
**Applied fix:** Added `sqlite3_errmsg()` extraction for open failures so the thrown error includes the actual SQLite error message. When the handle is nil (unlikely edge case), includes the raw SQLite return code in the message. This allows callers to distinguish permission errors from disk-full conditions.

### WR-03: `OpenAIToolTranslator` sets `strict: true` unconditionally

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIToolTranslator.swift`
**Commit:** aadc916
**Applied fix:** Added `enableStrictMode: Bool = false` parameter to `translate()`. Strict mode is now opt-in; callers must explicitly enable it when they know their tool schemas meet OpenAI's strict-mode requirements (all properties in `required`, `additionalProperties: false`, no `default` values). Existing callers default to safe behavior.

### WR-04: `AgentPermissionBridge` deny-by-default cases have no override mechanism

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Permission/AgentPermissionBridge.swift`, `Sources/SwiftAgentCore/AgentRuntime/Providers/AgentPermission.swift`
**Commit:** 0367d4d
**Applied fix:** Added `toolName` computed property to `AgentPermission` enum mapping each case to a PermissionEngine-compatible tool name. The six deny-by-default permissions (contacts, calendar, location, camera, microphone, delete) now route through `PermissionEngine.check()` using their tool names, so operators can configure per-tool rules to selectively grant them. Without matching rules, PermissionEngine denies by default (preserving existing behavior).

### WR-05: Duplicate Anthropic-compat SSE parsing logic between two parsers

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift`
**Commit:** bb7e9fc
**Applied fix:** Replaced the ~80-line `parseAnthropicCompat()` implementation in `DeepSeekSSEParser` with a single delegation call to `AnthropicSSEParser.parse()`. Since `AnthropicSSEParser` is a `Sendable` struct with all state local to the parse method, it can be safely instantiated and used from within the `DeepSeekSSEParser` actor. Bug fixes and improvements in the Anthropic parser now apply to both providers.

### WR-06: Two independent tool call accumulator implementations for OpenAI format

**Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAISSEParser.swift`
**Commit:** a56a0a4
**Applied fix:** Replaced the manual `JSONSerialization.jsonObject` + re-encode pattern in `OpenAISSEParser.finalizeAllToolCalls()` with `AnthropicContentAccumulator.safeParseJSON()`, matching the approach used by `OpenAIToolCallAccumulator` in `DeepSeekSSEParser`. This ensures both accumulators handle double-stringified argument payloads identically and provides resilience against API edge cases.

---

_Fixed: 2026-06-25T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
