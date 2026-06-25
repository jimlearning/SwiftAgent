---
phase: 02-session-streaming-structured-output
plan: 02
type: execute
subsystem: AgentRuntime Subsystem Stubs + Mock Providers
tags: [subsystem-stubs, mock-providers, tool-engine, testing]
depends_on: [01-01, 01-02, 01-03]
provides: [DefaultToolEngine, NoOpContextManager, NoOpProfileManager, NoOpHookSystem, MockLanguageModel, MockLanguageModelExecutor, MockMemoryStore, MockPermissionEngine]
affects: [AgentRuntimeImpl (02-03)]
tech-stack:
  added: []
  patterns: [actor-based-tool-registry, dictionary-backed-storage, mock-streaming-executor]
key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/SubsystemStubs.swift
    - Tests/SwiftAgentCoreTests/MockProviders.swift
  modified:
    - Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/AgentMemoryStore.swift
decisions:
  - "ToolEngine protocol methods all made async to support actor-based implementations (DefaultToolEngine)"
  - "DefaultToolEngine.execute returns stubbed string output; type-safe execution path deferred to Phase 3"
  - "RuntimeMemoryEntry given public init (missing from Phase 1, needed by test target)"
metrics:
  duration: ~4 min
  completed_date: "2026-06-25T10:03:11Z"
---

# Phase 2 Plan 2: Subsystem Stubs + Mock Providers Summary

Created concrete implementations for Phase 1 placeholder protocols and mock providers for testing the agent loop.

## What Was Built

### Subsystem Stubs (SubsystemStubs.swift)

- **DefaultToolEngine**: Actor-based tool registry storing tools by name in a dictionary. Supports registration, definition lookup, and stubbed execution. Full type-safe execution arrives in Phase 3.
- **NoOpContextManager**: Empty struct conforming to RuntimeContextManager.
- **NoOpProfileManager**: Empty struct conforming to ProfileManager.
- **NoOpHookSystem**: Empty struct conforming to RuntimeHookSystem.

### Mock Providers (MockProviders.swift)

- **MockLanguageModel**: Configurable mock with `cannedResponses` and `cannedToolCalls` arrays for multi-turn test sequences.
- **MockLanguageModelExecutor**: Streams canned text deltas and tool calls through `GenerationChannel`, with default fallback response.
- **MockMemoryStore**: In-memory `RuntimeMemoryStore` with full Codable roundtrip (store/retrieve), search, summarize, forget, and namespace listing.
- **MockPermissionEngine**: Configurable `RuntimePermissionEngine` returning a canned `shouldAllow` Bool.

## Tasks Completed

| # | Task | Commit | Status |
|---|------|--------|--------|
| 1 | Update ToolEngine protocol + create subsystem stubs | 6d0abf6 | Done |
| 2 | Create mock provider implementations | aad11d9 | Done |
| 3 | Verify both targets compile together | N/A (verification) | Done |

## Verification Results

- `swift build --target SwiftAgentCore`: PASSED
- `swift build --target SwiftAgentCoreTests`: PASSED
- `nonisolated(unsafe)` in AgentRuntime/: 0 (no additions)
- `func register` in AgentRuntime.swift: 1
- `DefaultToolEngine.*ToolEngine` conformance: 1
- `MockProviders.swift` line count: 157 (> 50 threshold)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made all ToolEngine methods async**
- **Found during:** Task 1
- **Issue:** ToolEngine protocol had `getDefinition` and `getAllDefinitions` as synchronous methods. Actor conformance (DefaultToolEngine) cannot satisfy non-async protocol requirements without crossing actor isolation boundaries.
- **Fix:** Added `async` to `getDefinition(name:)` and `getAllDefinitions()` in the ToolEngine protocol, matching the existing `async` on `register` and `execute`. Updated DefaultToolEngine accordingly.
- **Files modified:** `Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift`, `Sources/SwiftAgentCore/AgentRuntime/SubsystemStubs.swift`
- **Commit:** 6d0abf6

**2. [Rule 3 - Blocking] Added public init to RuntimeMemoryEntry**
- **Found during:** Task 2
- **Issue:** `RuntimeMemoryEntry` (Phase 1, plan 01-02) had no public memberwise initializer. The Swift-synthesized memberwise init is `internal`, making it inaccessible from the test target when constructing search result entries.
- **Fix:** Added explicit `public init(key:namespace:value:createdAt:updatedAt:metadata:)` to RuntimeMemoryEntry. Does not change any protocol surface or existing behavior.
- **Files modified:** `Sources/SwiftAgentCore/AgentRuntime/Providers/AgentMemoryStore.swift`
- **Commit:** aad11d9

## Decisions Made

1. **All ToolEngine methods are async.** The protocol is `Sendable` (not `Actor`-constrained) so concrete types can choose actor or non-actor storage, but all methods are `async` so actor-based implementations like DefaultToolEngine can conform naturally.

2. **DefaultToolEngine.execute is a stub in Phase 2.** Returns `.string("[Phase 2 stub] tool \(name) executed with \(input.count) bytes of input")` for registered tools. The full type-erased execution path with permission gating arrives in Phase 3.

3. **RuntimeMemoryEntry now has a public init.** The Phase 1 definition relied on the internal synthesized memberwise init, which was inaccessible from the test target. The public init is a minimal addition that doesn't change the protocol contract.

## Known Stubs

| File | Line | Description |
|------|------|-------------|
| SubsystemStubs.swift | ~55 | `DefaultToolEngine.execute` returns canned string — real type-safe execution in Phase 3 |
| SubsystemStubs.swift | ~64 | `NoOpContextManager` — empty struct, real compaction in Phase 3 |
| SubsystemStubs.swift | ~72 | `NoOpProfileManager` — empty struct, real profile management in future phase |
| SubsystemStubs.swift | ~80 | `NoOpHookSystem` — empty struct, real hook dispatch in future phase |
| MockProviders.swift | ~35 | `MockLanguageModelExecutor` guard-casts parent model — real executors will access their own provider config directly |

All stubs are intentional per the plan design. No stubs prevent the plan's goal (AgentRuntimeImpl in 02-03 will instantiate and use these concrete types).

## Self-Check: PASSED

- [x] SubsystemStubs.swift exists and compiles
- [x] MockProviders.swift exists and compiles
- [x] Commit 6d0abf6 exists (ToolEngine + stubs)
- [x] Commit aad11d9 exists (mock providers + RuntimeMemoryEntry fix)
- [x] Both build targets compile with zero errors
- [x] Zero nonisolated(unsafe) additions in AgentRuntime/
- [x] Requirements STREAM-01 fulfilled
