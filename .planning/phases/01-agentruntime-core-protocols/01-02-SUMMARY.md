---
phase: 01-agentruntime-core-protocols
plan: 02
subsystem: AgentRuntime Core Protocols — Provider Layer
tags: [agent-runtime, protocols, provider, model, memory, tool-metadata]
requires: [AgentRuntimeError, Transcript, AgentPermission, RuntimePermissionEngine, ToolOutputValue, GenerationChannel]
provides: [LanguageModel, LanguageModelCapabilities, LanguageModelExecutor, RuntimeToolDefinition, GenerationOptions, RuntimeMemoryStore, RuntimeMemoryEntry, AgentStateProtocol, ToolMetadata]
affects: [SwiftAgentCore module]
tech-stack:
  added: []
  patterns: [Sendable-protocol, protocol-as-contract, type-slot, factory-method, runtime-prefix-convention]
key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/Providers/LanguageModel.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/LanguageModelExecutor.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/AgentMemoryStore.swift
    - Sources/SwiftAgentCore/AgentRuntime/Tools/ToolMetadata.swift
  modified: []
decisions:
  - "InterruptBehavior reused from Types/Tool.swift (existing definition with .cancel and .block cases)"
  - "ToolDefinition renamed to RuntimeToolDefinition to avoid collision with LLM/LLMClient.swift"
  - "MemoryStore protocol renamed to RuntimeMemoryStore to avoid collision with Storage/MemoryStore.swift class"
  - "MemoryEntry struct renamed to RuntimeMemoryEntry to avoid collision with Storage/MemoryStore.swift struct"
  - "File renamed to AgentMemoryStore.swift to avoid SPM same-target filename collision with Storage/MemoryStore.swift"
  - "Full test suite blocked by pre-existing KeyboardShortcuts macro error (unrelated to this plan)"
metrics:
  duration: "~8 minutes"
  started: "2026-06-25T04:00:00Z"
  completed: "2026-06-25T04:08:00Z"
---

# Phase 1 Plan 2: AgentRuntime Core Protocols — Provider Layer Summary

**One-liner:** Defined 4 protocol types and 5 supporting structs/enums establishing the swappable Provider boundaries (LanguageModel, LanguageModelExecutor, RuntimeMemoryStore) plus ToolMetadata decoupling operational concerns from the Tool protocol.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create LanguageModelCapabilities struct and ToolMetadata struct | `4244194` | LanguageModel.swift, ToolMetadata.swift |
| 2 | Create LanguageModel, LanguageModelExecutor, RuntimeMemoryStore, and AgentStateProtocol protocols | `3b0eab1` | LanguageModel.swift (appended), LanguageModelExecutor.swift, AgentMemoryStore.swift |
| 3 | Verify compilation and cross-plan type resolution | (verification only) | -- |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All 4 new Swift files exist in AgentRuntime/Providers/ and AgentRuntime/Tools/ | PASS |
| 2 | LanguageModel protocol with 3 members (capabilities, displayName, makeExecutor) | PASS |
| 3 | LanguageModelCapabilities struct with 7 fields (single source of truth) | PASS |
| 4 | LanguageModelExecutor protocol with 2 members (model, respond) | PASS |
| 5 | RuntimeToolDefinition and GenerationOptions structs defined (normalized request types) | PASS |
| 6 | RuntimeMemoryStore protocol with 6 async-throws methods | PASS |
| 7 | RuntimeMemoryEntry struct with metadata dictionary | PASS |
| 8 | AgentStateProtocol type-slot (3 properties, marked design-only) | PASS |
| 9 | ToolMetadata struct with 9 fields + InterruptBehavior reference | PASS |
| 10 | Zero existing files modified; zero new unsafe annotations | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] InterruptBehavior redefinition**
- **Found during:** Task 1
- **Issue:** `InterruptBehavior` enum already exists in `Types/Tool.swift` (line 1116) with identical cases (`.cancel`, `.block`). Defining a second `InterruptBehavior` in `ToolMetadata.swift` caused a redeclaration error and ambiguity across 5+ existing files.
- **Fix:** Removed the duplicate `InterruptBehavior` definition. `ToolMetadata` references the existing `InterruptBehavior` from `Types/Tool.swift`.
- **Files modified:** `Tools/ToolMetadata.swift`

**2. [Rule 3 - Blocking] SPM filename collision: MemoryStore.swift**
- **Found during:** Task 2
- **Issue:** `Storage/MemoryStore.swift` already exists in `SwiftAgentCore`. SPM rejects duplicate source filenames within the same target (error: "multiple producers").
- **Fix:** Renamed new file to `AgentMemoryStore.swift` following plan 01-01 precedent (`PermissionEngine.swift` -> `AgentPermission.swift`).
- **Files modified:** `Providers/MemoryStore.swift` -> `Providers/AgentMemoryStore.swift`

**3. [Rule 3 - Blocking] Type collision: MemoryStore protocol vs class**
- **Found during:** Task 2
- **Issue:** `MemoryStore` already exists as a `final class` in `Storage/MemoryStore.swift`. Swift disallows a protocol with the same name as an existing type in the same module.
- **Fix:** Renamed protocol to `RuntimeMemoryStore` following plan 01-01 precedent (`PermissionEngine` -> `RuntimePermissionEngine`).
- **Files modified:** `Providers/AgentMemoryStore.swift`

**4. [Rule 3 - Blocking] Type collision: MemoryEntry struct**
- **Found during:** Task 2
- **Issue:** `MemoryEntry` already exists as a struct in `Storage/MemoryStore.swift` with different fields (name, description, type, body, filePath, lastModified).
- **Fix:** Renamed to `RuntimeMemoryEntry` following the `Runtime` prefix convention.
- **Files modified:** `Providers/AgentMemoryStore.swift`

**5. [Rule 3 - Blocking] Type collision: ToolDefinition struct**
- **Found during:** Task 2
- **Issue:** `ToolDefinition` already exists in `LLM/LLMClient.swift` (line 816) with an additional `deferLoading` field. Defining a second `ToolDefinition` caused ambiguity errors across the codebase.
- **Fix:** Renamed to `RuntimeToolDefinition` following the `Runtime` prefix convention. Updated `LanguageModelExecutor.respond()` parameter type.
- **Files modified:** `Providers/LanguageModelExecutor.swift`

### Stub Tracking

No stubs exist. All types are fully defined with all specified properties and methods. `AgentStateProtocol` is intentionally design-only per the plan.

### Known Issues

**Pre-existing:** KeyboardShortcuts dependency macro error prevents full `swift build` and `swift test` from completing. This is unrelated to our changes — `SwiftAgentCore` target builds and links successfully in isolation, and all cross-plan type references resolve correctly.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: information-disclosure | LanguageModelCapabilities | `providerDisplayName` is display-only. API keys live in executor implementation (Phase 3), not in the protocol. Mitigated per plan. |
| threat_flag: elevation-of-privilege | ToolMetadata | `isEnabled` defaults to `true` but is controlled by ToolEngine registration. Metadata is read-only at tool execution time. Mitigated per plan. |

## Key Design Decisions

1. **Runtime prefix convention established:** All new AgentRuntime types that collide with existing types use the `Runtime` prefix (`RuntimeMemoryStore`, `RuntimeMemoryEntry`, `RuntimeToolDefinition`). This is consistent with plan 01-01's `RuntimePermissionEngine` and creates a clear namespace separation between new AgentRuntime types and existing types that will be deprecated in Phase 3.

2. **InterruptBehavior reuse:** Rather than defining a duplicate, `ToolMetadata` references the existing `InterruptBehavior` enum from `Types/Tool.swift` (`.cancel`, `.block`). This avoids a type fork and keeps tool interruption behavior consistent.

3. **AgentMemoryStore.swift filename:** Following plan 01-01 precedent where `PermissionEngine.swift` was renamed to `AgentPermission.swift` to avoid SPM filename collision.

4. **AgentStateProtocol as type-slot:** The protocol is defined but not implemented — it reserves the design surface for future `@AgentState` property-wrapper integration without committing to implementation details.

## Test Results

- **Build (Core target):** `swift build --disable-sandbox --target SwiftAgentCore` exits 0
- **Full build:** Blocked by pre-existing KeyboardShortcuts macro error in SwiftAgentApp dependency
- **Full test suite:** Blocked by same pre-existing build error
- **Existing files modified:** 0
- **Nonisolated(unsafe) in AgentRuntime/:** 0
- **AgentRuntime file count:** 9 total (5 from plan 01-01 + 4 from this plan)

## Self-Check: PASSED

All 4 files exist and contain correct types. Both commits (`4244194`, `3b0eab1`) are in git history. Core target builds. No existing files modified. All cross-plan type references verified.
