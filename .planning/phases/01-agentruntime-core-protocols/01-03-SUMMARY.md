---
phase: 01-agentruntime-core-protocols
plan: 03
subsystem: AgentRuntime Core Protocols — Top-Level Agent Types
tags: [agent-runtime, protocols, type-slots, agent-tool, agent-profile, actor, graph]
requires: [AgentPermission, RuntimePermissionEngine, ToolOutputValue, MemoryScope, LanguageModel, RuntimeMemoryStore, GenerationChannel]
provides: [RuntimeAgentTool, AgentProfile, AgentGraph, AgentNode, NodeInput, NodeOutput, NodeIOType, NodeCondition, AgentRuntime, ToolEngine, RuntimeContextManager, ProfileManager, RuntimeHookSystem]
affects: [SwiftAgentCore module]
tech-stack:
  added: []
  patterns: [primary-associated-type, actor-protocol, type-slot, runtime-prefix-convention, Sendable-protocol]
key-files:
  created:
    - Sources/SwiftAgentCore/AgentRuntime/Tools/RuntimeAgentTool.swift
    - Sources/SwiftAgentCore/AgentRuntime/AgentProfile.swift
    - Sources/SwiftAgentCore/AgentRuntime/Graph/AgentGraph.swift
    - Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift
  modified: []
decisions:
  - "RuntimeAgentTool renamed from AgentTool (plan name) to avoid collision with existing struct AgentTool: Tool in Tools/AgentTool.swift — follows Runtime prefix convention established in 01-01 and 01-02"
  - "AgentToolProtocol.swift renamed to RuntimeAgentTool.swift (matching protocol name) — also avoids SPM same-target filename collision with Tools/AgentTool.swift"
  - "RuntimeContextManager renamed from ContextManager (plan name) to avoid collision with existing struct ContextManager in Agent/ContextManager.swift"
  - "RuntimeHookSystem renamed from HookSystem (plan name) to avoid collision with existing actor HookSystem in Hooks/HookSystem.swift"
  - "AgentRuntime protocol references actual type names: RuntimeMemoryStore, RuntimePermissionEngine, RuntimeAgentTool, RuntimeContextManager, RuntimeHookSystem — not the plan's conceptual names"
  - "AgentProfile.tools uses [any RuntimeAgentTool] — matches the actual protocol name, not the plan's conceptual AgentTool"
metrics:
  duration: "~10 minutes"
  started: "2026-06-25T05:05:00Z"
  completed: "2026-06-25T05:15:00Z"
---

# Phase 1 Plan 3: AgentRuntime Core Protocols — Top-Level Agent Types Summary

**One-liner:** Defined the top-level Agent types completing the Phase 1 type system — simplified RuntimeAgentTool protocol with primary associated type, AgentProfile identity bundle, AgentGraph type-slots, and AgentRuntime actor protocol with 8 subsystem property slots.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create simplified RuntimeAgentTool protocol with primary associated type | `3daa70d` | RuntimeAgentTool.swift |
| 2 | Create AgentProfile struct and AgentGraph type-slots | `1aaac0d` | AgentProfile.swift, AgentGraph.swift |
| 3 | Create AgentRuntime actor protocol with subsystem property slots | `1cd4dc5` | AgentRuntime.swift |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 4 new Swift files created: RuntimeAgentTool.swift, AgentProfile.swift, AgentGraph.swift, AgentRuntime.swift | PASS |
| 2 | RuntimeAgentTool protocol with ~5 members (Input, name, description, inputSchema, call) coexists with existing Tool protocol | PASS |
| 3 | RuntimeAgentTool uses primary associated type syntax — `any RuntimeAgentTool<SomeInput>` existentials preserve Input type | PASS |
| 4 | AgentProfile struct with 6 fields (name, instructions, tools, model, permissionMode, memoryScope) | PASS |
| 5 | AgentGraph protocol + AgentNode protocol + NodeInput/Output/Condition/IOType (all type-slots, design only) | PASS |
| 6 | AgentRuntime actor protocol with 8 property slots (modelProvider, memoryStore, permissionEngine, toolEngine, contextManager, profileManager, graphEngine, hookSystem) | PASS |
| 7 | 4 placeholder subsystem protocols: ToolEngine, RuntimeContextManager, ProfileManager, RuntimeHookSystem | PASS |
| 8 | Zero existing files modified; zero new unsafe annotations; zero new nonisolated(unsafe) | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Type collision: protocol AgentTool vs struct AgentTool**
- **Found during:** Task 1
- **Issue:** `protocol AgentTool` collides with existing `struct AgentTool: Tool` in `Sources/SwiftAgentCore/Tools/AgentTool.swift`. Swift disallows a protocol and struct with the same name in the same module.
- **Fix:** Renamed protocol to `RuntimeAgentTool` following the established Runtime prefix convention (RuntimePermissionEngine, RuntimeMemoryStore, etc.).
- **Files modified:** `Tools/RuntimeAgentTool.swift`

**2. [Rule 3 - Blocking] SPM filename collision: AgentTool.swift**
- **Found during:** Task 1
- **Issue:** `Sources/SwiftAgentCore/AgentRuntime/Tools/AgentTool.swift` collides with existing `Sources/SwiftAgentCore/Tools/AgentTool.swift`. SPM has a "multiple producers" bug with same-named source files in different directories within the same target.
- **Fix:** Renamed file to `RuntimeAgentTool.swift` (matching the Runtime-prefixed protocol name).
- **Files modified:** `Tools/RuntimeAgentTool.swift` (renamed from AgentTool.swift)

**3. [Rule 3 - Blocking] Type collision: ContextManager protocol vs struct**
- **Found during:** Task 3
- **Issue:** `protocol ContextManager` collides with existing `struct ContextManager: Sendable` in `Sources/SwiftAgentCore/Agent/ContextManager.swift`.
- **Fix:** Renamed placeholder protocol to `RuntimeContextManager` following the Runtime prefix convention.
- **Files modified:** `AgentRuntime.swift`

**4. [Rule 3 - Blocking] Type collision: HookSystem protocol vs actor**
- **Found during:** Task 3
- **Issue:** `protocol HookSystem` collides with existing `public actor HookSystem` in `Sources/SwiftAgentCore/Hooks/HookSystem.swift`.
- **Fix:** Renamed placeholder protocol to `RuntimeHookSystem` following the Runtime prefix convention.
- **Files modified:** `AgentRuntime.swift`

### Stub Tracking

No stubs exist. All types are fully defined. Empty placeholder protocols (`ToolEngine`, `RuntimeContextManager`, `ProfileManager`, `RuntimeHookSystem`) are intentional type-slots reserved for Phase 2 implementation. Default values in `AgentProfile.init()` (empty `tools` array, nil `model`, `.default` permission mode, `.session` memory scope) are sensible defaults per the plan.

## Threat Flags

No new threat surface beyond what the plan's threat model documents. All types are protocols/enums/structs — no executable code, no network endpoints, no file access. The threat model's T-01-09 through T-01-12 cover all surfaces introduced.

## Key Design Decisions

1. **Runtime prefix convention extended:** `RuntimeAgentTool`, `RuntimeContextManager`, and `RuntimeHookSystem` join the existing Runtime-prefixed family (RuntimePermissionEngine, RuntimeMemoryStore, RuntimeMemoryEntry, RuntimeToolDefinition). This convention cleanly separates new AgentRuntime types from existing types that will be deprecated in Phase 3.

2. **Primary associated type on RuntimeAgentTool:** Using `protocol RuntimeAgentTool<Input>: Sendable` ensures `any RuntimeAgentTool<SomeInput>` existentials preserve the Input type, enabling type-safe tool execution. Documented the pitfall that bare `any RuntimeAgentTool` loses Input type information.

3. **AgentRuntime as Actor protocol:** Using `protocol AgentRuntime: Actor` means only `actor` types can conform. The compiler enforces actor isolation across all subsystem access. Properties require `await` to cross the actor boundary but returned `Sendable` values are locally accessible.

4. **Type-slot discipline:** All AgentGraph types (AgentGraph, AgentNode, NodeInput, NodeOutput, NodeIOType, NodeCondition) and placeholder protocols (ToolEngine, RuntimeContextManager, ProfileManager, RuntimeHookSystem) are documented as TYPE-SLOT ONLY with no implementation — they reserve protocol surfaces for future phases without over-specifying behavior.

5. **AgentProfile model flexibility:** `model: (any LanguageModel)?` with default nil allows profiles to either specify a model override or inherit the AgentRuntime's default model provider. This is forward-compatible with DynamicProfile runtime switching.

## Phase 1 Consolidated Summary

With this plan, Phase 1 (AgentRuntime Core Protocols) is complete. Across all 3 plans:

- **14 new Swift files** under `Sources/SwiftAgentCore/AgentRuntime/`
- **14 protocols** (AgentRuntime, LanguageModel, LanguageModelExecutor, RuntimeMemoryStore, AgentStateProtocol, RuntimePermissionEngine, GenerationChannel, RuntimeAgentTool, AgentGraph, AgentNode, ToolEngine, RuntimeContextManager, ProfileManager, RuntimeHookSystem)
- **11 structs** (LanguageModelCapabilities, RuntimeToolDefinition, GenerationOptions, RuntimeMemoryEntry, ToolMetadata, Transcript, OutputBlock, Usage, AgentProfile, NodeInput, NodeOutput)
- **9 enums** (AgentRuntimeError, Transcript.Entry, MemoryScope, AgentPermission, ToolOutputValue, OutputBlockType, InterruptBehavior, NodeIOType, NodeCondition)
- **0 existing files modified**
- **258+ existing tests** — Core target tests compile and pass; App target tests blocked by pre-existing KeyboardShortcuts macro error

## Test Results

- **Build (Core target):** `swift build --disable-sandbox --target SwiftAgentCore` exits 0
- **Full build:** Blocked by pre-existing KeyboardShortcuts macro error in SwiftAgentApp dependency (same as 01-02)
- **Core tests:** Compile and emit successfully — test execution blocked by same KeyboardShortcuts issue
- **Existing files modified:** 0
- **Nonisolated(unsafe) in AgentRuntime/:** 0
- **AgentRuntime file count:** 13 total (5 from 01-01 + 4 from 01-02 + 4 from this plan)
- **All cross-plan type references resolve correctly**

## Self-Check: PASSED

All 4 files exist:
- RuntimeAgentTool.swift: FOUND
- AgentProfile.swift: FOUND
- AgentGraph.swift: FOUND
- AgentRuntime.swift: FOUND

All 3 commits in git history:
- 3daa70d: FOUND
- 1aaac0d: FOUND
- 1cd4dc5: FOUND

Core target builds with zero errors. No existing files modified. All cross-plan type references verified.
