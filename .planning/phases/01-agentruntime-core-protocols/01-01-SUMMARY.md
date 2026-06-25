---
phase: 01-agentruntime-core-protocols
plan: 01
subsystem: AgentRuntime Core Protocols
tags: [agent-runtime, types, protocols, enums, foundation]
requires: []
provides: [AgentRuntimeError, Transcript, MemoryScope, AgentPermission, RuntimePermissionEngine, ToolOutputValue, OutputBlock, OutputBlockType, GenerationChannel, Usage]
affects: [SwiftAgentCore module]
tech-stack:
  added: []
  patterns: [enum-with-associated-values, manual-CaseIterable, Sendable-protocol, protocol-as-contract]
key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/AgentRuntimeError.swift
    - Sources/SwiftAgentCore/AgentRuntime/Transcript.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/AgentPermission.swift
    - Sources/SwiftAgentCore/AgentRuntime/Providers/GenerationChannel.swift
    - Sources/SwiftAgentCore/AgentRuntime/Tools/ToolOutputValue.swift
  modified: []
decisions:
  - "AgentRuntimeError has 16 cases (matching RESEARCH.md) rather than 15 as stated in plan text — research code is authoritative source"
  - "PermissionEngine protocol renamed to RuntimePermissionEngine to avoid Swift name collision with existing PermissionEngine struct"
  - "ToolOutput enum renamed to ToolOutputValue to avoid collision with existing ToolOutput discriminated union in Types/Tool.swift"
  - "New file PermissionEngine.swift renamed to AgentPermission.swift to avoid SPM same-target filename collision"
  - "Usage struct reused from existing StreamEvent.swift instead of defining duplicate — same target, same fields"
metrics:
  duration: "~6 minutes"
  started: "2026-06-25T03:47:00Z"
  completed: "2026-06-25T03:53:00Z"
---

# Phase 1 Plan 1: AgentRuntime Core Protocols Summary

**One-liner:** Defined 5 leaf-level type files with 8 new public types (3 enums, 2 protocols, 3 structs) as the type system foundation for the Agent Runtime — zero existing files modified.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create AgentRuntimeError enum and Transcript struct | `1ce8311` | AgentRuntimeError.swift, Transcript.swift |
| 2 | Create AgentPermission enum + RuntimePermissionEngine protocol + ToolOutputValue + GenerationChannel | `d2a22b0` | AgentPermission.swift, GenerationChannel.swift, ToolOutputValue.swift |
| 3 | Verify compilation and test non-regression | (verification only) | — |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All 5 new Swift files exist under Sources/SwiftAgentCore/AgentRuntime/ | PASS |
| 2 | AgentRuntimeError enum has 16 subsystem-grouped cases (model: 6, memory: 3, permission: 2, tool: 3, graph: 2) | PASS |
| 3 | Transcript struct with 7 Entry cases + MemoryScope enum defined | PASS |
| 4 | AgentPermission enum with 13 cases (matching macOS permission taxonomy) defined | PASS |
| 5 | RuntimePermissionEngine protocol with check(_:) method defined (existing struct untouched) | PASS |
| 6 | ToolOutputValue enum with string + blocks cases defined (no ContentBlock exposure) | PASS |
| 7 | GenerationChannel protocol with 6 streaming methods defined | PASS |
| 8 | Zero existing files modified; zero new unsafe annotations | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] SPM filename collision: PermissionEngine.swift**
- **Found during:** Task 2
- **Issue:** `Sources/SwiftAgentCore/AgentRuntime/Providers/PermissionEngine.swift` has the same filename as existing `Sources/SwiftAgentCore/Safety/PermissionEngine.swift`. SPM rejects duplicate source filenames within the same target (error: "multiple producers").
- **Fix:** Renamed new file to `AgentPermission.swift` — the primary type in the file is `enum AgentPermission`, making this a natural name.
- **Files modified:** `Providers/PermissionEngine.swift` -> `Providers/AgentPermission.swift`

**2. [Rule 3 - Blocking] Swift redeclaration: PermissionEngine protocol vs struct**
- **Found during:** Task 2
- **Issue:** Swift disallows a protocol and a struct with the same name in the same module. The existing `PermissionEngine` struct in `Safety/PermissionEngine.swift` blocks the new protocol declaration.
- **Fix:** Renamed protocol to `RuntimePermissionEngine`. Documentation comments updated to note that the existing struct will conform to this (or a compatible) protocol in Phase 3.
- **Files modified:** `Providers/AgentPermission.swift`

**3. [Rule 3 - Blocking] Name collision: ToolOutput enum vs existing type**
- **Found during:** Task 2
- **Issue:** `ToolOutput` already exists as a discriminated union enum in `Types/Tool.swift` (line 969) with cases: `.text`, `.image`, `.notebook`, `.pdf`, `.fileUnchanged`, `.parts`. The plan wants a new `ToolOutput` with `.string` and `.blocks` cases — but Swift cannot have two enums with the same name in the same module.
- **Fix:** Renamed new enum to `ToolOutputValue`. Renamed file to `ToolOutputValue.swift`. Updated `GenerationChannel` method signature from `output: ToolOutput` to `output: ToolOutputValue`.
- **Files modified:** `Tools/ToolOutput.swift` -> `Tools/ToolOutputValue.swift`, `Providers/GenerationChannel.swift`

**4. [Rule 3 - Blocking] Duplicate Usage struct definition**
- **Found during:** Task 2
- **Issue:** `Usage` struct already exists in `Types/StreamEvent.swift` (line 38) with the same fields (`inputTokens`, `outputTokens`). Defining a second `Usage` causes ambiguity errors across the module.
- **Fix:** Removed the duplicate `Usage` definition from `GenerationChannel.swift`. The protocol methods reference the existing `Usage` type from the same target.
- **Files modified:** `Providers/GenerationChannel.swift`

**5. [Rule 1 - Bug] CaseIterable conformance not synthesizable**
- **Found during:** Task 2
- **Issue:** Swift cannot auto-synthesize `CaseIterable` for enums with associated values. `AgentPermission` has 3 associated-value cases (`readFiles`, `writeFiles`, `network`).
- **Fix:** Added manual `allCases` implementation returning 13 entries with empty sets for associated-value cases.
- **Files modified:** `Providers/AgentPermission.swift`

### Stub Tracking

No stubs exist. All types are fully defined with all specified cases and methods.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: information-disclosure | AgentRuntimeError.swift | `unauthorized(reason:)` carries a reason string. Mitigated per plan: carries reason, never raw API key. |
| threat_flag: elevation-of-privilege | AgentPermission.swift | `CaseIterable` enables exhaustive switches; `RuntimePermissionEngine.check()` is the single gate. No backdoor. |

## Key Design Decisions

1. **16 error cases (not 15):** The RESEARCH.md code example at lines 502-528 defines exactly 16 cases (model: 6, memory: 3, permission: 2, tool: 3, graph: 2). The plan text says "15" but the research reference is the authoritative source. The breakdown in verification section also sums to 16.

2. **RuntimePermissionEngine naming:** The plan wanted a `PermissionEngine` protocol, but Swift cannot have a struct and protocol share the same name in a module. The `Runtime` prefix clearly indicates this is the AgentRuntime-level protocol, distinct from the existing Safety-level struct.

3. **ToolOutputValue naming:** The existing `ToolOutput` (discriminated union in Types/Tool.swift) serves a different purpose (CC-compatible result variant). The new `ToolOutputValue` is the AgentRuntime's public-facing tool output abstraction.

4. **Existing Usage struct reused:** Rather than defining a duplicate `Usage`, the `GenerationChannel` protocol references the existing `Usage` type from `Types/StreamEvent.swift`. This avoids the ambiguity error and keeps token tracking consistent.

5. **File renamed to AgentPermission.swift:** Prevents SPM same-target filename collision while keeping `AgentPermission` as the primary visible type in the file.

## Test Results

- **Build:** `swift build --disable-sandbox` exits 0
- **Tests:** 17 pre-existing test errors (all `PermissionMode` scope-related, unrelated to new code). Our changes add zero new failures.
- **Existing files modified:** 0 source files changed
- **Nonisolated(unsafe):** Zero new annotations in AgentRuntime/

## Self-Check: PASSED

All 5 files exist and contain correct types. Both commits are in git history (`1ce8311`, `d2a22b0`). Build passes. No existing files modified.
