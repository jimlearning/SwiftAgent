---
phase: 02-session-streaming-structured-output
plan: 01
subsystem: Core Streaming Types
tags: [agent-runtime, streaming, types, enums, structs, actors, Mirror]
requires: [AgentRuntimeError, ToolOutputValue, Usage, JSONSchema, GenerationChannel]
provides: [SessionEvent, PartiallyGenerated, GenerationSchema, RuntimeGenerationChannel]
affects: [SwiftAgentCore module]
tech-stack:
  added: []
  patterns: [Sendable-enum, Sendable-generic-struct, Mirror-reflection, actor-protocol-conformance, AsyncThrowingStream-continuation, finish-gating]
key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/SessionEvent.swift
    - Sources/SwiftAgentCore/AgentRuntime/PartiallyGenerated.swift
    - Sources/SwiftAgentCore/AgentRuntime/GenerationSchema.swift
    - Sources/SwiftAgentCore/AgentRuntime/RuntimeGenerationChannel.swift
    - Tests/SwiftAgentCoreTests/Phase2StreamingTests.swift
  modified: []
decisions:
  - "SessionEvent uses snapshot semantics for textDelta/thinkingDelta — the value is the COMPLETE accumulated text so far, not an incremental delta. Prevents double-render bug (PITFALLS.md Pitfall 2)."
  - "generationSchemaFromMirror parameter renamed from 'type' to 'metatype' to avoid shadowing the type(of:) global function."
  - "PartiallyGenerated uses public var (not public let) for mutable snapshot state updates in AgentRuntimeImpl (Plan 02-03)."
  - "Tests structured as post-send collection (for try await after all sends) to avoid Swift 6 Sendable closure capture issues with local var [SessionEvent]."
  - "Test execution blocked by pre-existing KeyboardShortcuts macro error in SwiftAgentApp target; test target compiles cleanly via swift build --target SwiftAgentCoreTests."
metrics:
  duration: "~10 minutes"
  started: "2026-06-25T09:46:43Z"
  completed: "2026-06-25T09:56:25Z"
---

# Phase 2 Plan 1: Core Streaming Types Summary

**One-liner:** Defined the four foundational AgentRuntime streaming types — provider-agnostic SessionEvent enum, snapshot-diffing PartiallyGenerated<T>, Mirror-based GenerationSchema protocol, and finish-gated RuntimeGenerationChannel actor — forming the data plane of the AgentRuntime loop.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create SessionEvent enum (STREAM-01) | `0d028d4` | SessionEvent.swift |
| 2 | Create PartiallyGenerated struct and GenerationSchema protocol (STREAM-02) | `b7a68a6` | PartiallyGenerated.swift, GenerationSchema.swift |
| 3 | Create RuntimeGenerationChannel actor and unit tests | `2f72b1b` | RuntimeGenerationChannel.swift, Phase2StreamingTests.swift |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | SessionEvent.swift defines a 6-case public enum with all specified associated value types | PASS |
| 2 | PartiallyGenerated.swift defines a generic struct with snapshot/diff/complete fields | PASS |
| 3 | GenerationSchema.swift defines a protocol with Mirror-based default JSON schema generation | PASS |
| 4 | RuntimeGenerationChannel.swift defines an actor implementing GenerationChannel with finish gating | PASS |
| 5 | Phase2StreamingTests.swift has 6 test methods covering all four types | PASS |
| 6 | SwiftAgentCore target builds with zero errors | PASS |
| 7 | Zero existing files modified; zero new nonisolated(unsafe) annotations | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Parameter name 'type' shadowed type(of:) global function**
- **Found during:** Task 2
- **Issue:** The function signature `generationSchemaFromMirror(_ type: Any.Type)` used `type` as the parameter name. This shadowed Swift's `type(of:)` global function, causing `type(of: child.value)` on line 72 to produce the cryptic error "type 'Any' has no member 'init'".
- **Fix:** Renamed parameter from `type` to `metatype` throughout the function signature and doc comment.
- **Files modified:** `Sources/SwiftAgentCore/AgentRuntime/GenerationSchema.swift`
- **Commit:** `b7a68a6`

**2. [Rule 1 - Bug] Task.value call missing try in async tests**
- **Found during:** Task 3
- **Issue:** `_ = await collectTask.value` failed to compile because `Task.value` can throw when iterating an `AsyncThrowingStream<SessionEvent, Error>`.
- **Fix:** Changed to `_ = try await collectTask.value`.
- **Files modified:** `Tests/SwiftAgentCoreTests/Phase2StreamingTests.swift`
- **Commit:** `2f72b1b`

**3. [Rule 1 - Bug] Swift 6 Sendable closure capture of local mutable var**
- **Found during:** Task 3
- **Issue:** `Task { for try await event in stream { events.append(event) } }` captured a local `var events: [SessionEvent]` in a `@Sendable` closure, violating Swift 6 strict concurrency.
- **Fix:** Restructured tests to use post-send collection: send all events first, then `for try await event in stream { events.append(event) }` in the calling scope instead of a Task closure. Used `.bufferingNewest(10)` on the AsyncThrowingStream to ensure events are buffered during the send phase.
- **Files modified:** `Tests/SwiftAgentCoreTests/Phase2StreamingTests.swift`
- **Commit:** `2f72b1b`

### Known Issues

**Pre-existing:** KeyboardShortcuts `PreviewsMacros.SwiftUIView` macro error blocks full `swift test` execution. The `SwiftAgentApp` target (which depends on KeyboardShortcuts) cannot build, and `swift test` builds all package targets. The `SwiftAgentCoreTests` target compiles successfully in isolation via `swift build --target SwiftAgentCoreTests`. This is the same pre-existing blocker documented in Phase 1 summaries (01-02, 01-03). Test execution will be available once the KeyboardShortcuts dependency issue is resolved.

## Test Results

- **Build (Core target):** `swift build --disable-sandbox --target SwiftAgentCore` exits 0
- **Build (Core test target):** `swift build --disable-sandbox --target SwiftAgentCoreTests` exits 0
- **Test execution:** Blocked by pre-existing KeyboardShortcuts macro error in SwiftAgentApp dependency
- **Test compilation:** All 6 test methods compile cleanly; no warnings
- **Existing files modified:** 0
- **Nonisolated(unsafe) in AgentRuntime/:** 0
- **AgentRuntime file count:** 17 total (13 from Phase 1 + 4 new)

## Stub Tracking

No stubs exist. All types are fully defined:
- SessionEvent: 6 cases with complete associated value types
- PartiallyGenerated<T>: 5 properties, memberwise init, diffSnapshots helper
- GenerationSchema: protocol with Mirror-based default implementation; fallback returns descriptive JSONSchema when type lacks DefaultInitializable conformance (design intent, not a stub)
- RuntimeGenerationChannel: 7 methods, all fully implemented with finish gating
- Phase2StreamingTests: 6 test methods, all with assertion logic

## Threat Flags

No new threat surface beyond what the plan's threat model documents:
- T-02-01 (Spoofing / finish gating): MITIGATED — isFinished flag gates all 6 protocol methods; after complete() or fail(), all subsequent sends silently dropped
- T-02-02 (Information disclosure / token counts): ACCEPT — Usage carries non-sensitive operational metrics only
- T-02-03 (Tampering / rawAccumulatedText): ACCEPT — internal debugging data within AgentRuntime actor boundary

## Key Design Decisions

1. **Snapshot semantics for textDelta/thinkingDelta:** Despite the "Delta" name, each event carries the COMPLETE accumulated text (snapshot), not the incremental addition. This prevents the double-render bug (PITFALLS.md Pitfall 2) where consumers concatenating deltas would double-render. The executor is responsible for tracking the accumulation and sending snapshots.

2. **DefaultInitializable protocol for Mirror schema generation:** Since Swift cannot call `type.init()` without a protocol constraint, `generationSchemaFromMirror` uses an internal `DefaultInitializable` protocol. Types that want automatic JSON schema derivation conform to this protocol. Types that don't get a best-effort schema with a descriptive note. The protocol is `internal` (accessible via `@testable import` for test structs).

3. **Post-send collection pattern for AsyncThrowingStream tests:** To avoid Swift 6 `@Sendable` closure capture issues, tests use a buffered stream (`.bufferingNewest(10)`) and collect events after all sends complete (`for try await event in stream` in the calling scope). This avoids the need for `Task {}` closure captures of mutable local state.

4. **No new type collisions:** Unlike Phase 1 where 10+ naming collisions required Runtime-prefix conventions, Phase 2 Plan 01 introduces entirely new types with zero conflicts with existing codebase symbols. SessionEvent deduplicates from `StreamEvent` (which is an Anthropic-specific enum in Types/) by having a semantically distinct name.

## Artifacts This Plan Produces

| Symbol | Kind | File | Purpose |
|--------|------|------|---------|
| SessionEvent | enum (6 cases) | SessionEvent.swift | Provider-agnostic streaming events |
| PartiallyGenerated\<T\> | generic struct | PartiallyGenerated.swift | Snapshot accumulation with diffing |
| diffSnapshots | function | PartiallyGenerated.swift | Mirror-based diff between two snapshots |
| GenerationSchema | protocol | GenerationSchema.swift | Runtime JSON schema generation from Codable types |
| generationSchemaFromMirror | function | GenerationSchema.swift | Mirror-based JSON schema auto-derivation |
| mapSwiftToJSONType | function | GenerationSchema.swift | Swift type to JSON type mapping |
| RuntimeGenerationChannel | actor | RuntimeGenerationChannel.swift | Concrete GenerationChannel with finish gating |
| Phase2StreamingTests | XCTestCase | Phase2StreamingTests.swift | Unit tests for all four types |

## Self-Check: PASSED

All 5 files exist:
- SessionEvent.swift: FOUND
- PartiallyGenerated.swift: FOUND
- GenerationSchema.swift: FOUND
- RuntimeGenerationChannel.swift: FOUND
- Phase2StreamingTests.swift: FOUND

All 3 commits in git history:
- 0d028d4: FOUND
- b7a68a6: FOUND
- 2f72b1b: FOUND

Core target builds with zero errors. Core test target builds with zero errors. No existing files modified.
