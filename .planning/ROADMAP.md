# Roadmap: SwiftAgent Agent Runtime

## Overview

Reorganize SwiftAgent's AI agent API from an Anthropic-specific LLM client into a **model-agnostic Agent Runtime** — an operating system kernel for AI agents where inference models, memory stores, and permission engines are swappable Provider plugins. The architecture targets Apple's FoundationModels WWDC25→26 trajectory and the predicted WWDC27 "Agent OS" direction where the framework splits into FoundationModels (inference only) and AgentKit (agent orchestration, memory, permissions, evaluation).

The journey proceeds through four phases: defining the AgentRuntime blueprint (all protocols, structs, enums, type-slots for future subsystems), building the runtime core (session loop, snapshot streaming, structured output), implementing all Provider backends (Model + Memory + Permission), and finally migrating 60+ tools, wiring CLI/App consumers, and removing deprecated types.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: AgentRuntime Core Protocols** — All new type-level definitions: AgentRuntime, Providers (Model/Memory/Permission), simplified Tool, AgentProfile, AgentGraph placeholder. Existing code unchanged.
- [x] **Phase 2: Session, Streaming & Structured Output** — AgentRuntime loop works end-to-end with mock ModelProvider. Snapshot streaming accumulates correctly. Type-driven output from Codable types.
- [x] **Phase 3: Provider Implementations** — Three ModelProviders (Anthropic, DeepSeek unified, OpenAI) + SQLiteMemoryStore + PermissionEngine upgrade. Wire-format isolation enforced. (completed 2026-06-25)
- [ ] **Phase 4: Migration, Wiring & Cleanup** — 60+ tools to simplified protocol. CLI + App wired to AgentRuntime. Deprecated types removed. All tests pass.

## Phase Details

### Phase 1: AgentRuntime Core Protocols

**Goal**: All new type-level definitions exist in the codebase — AgentRuntime, three Provider protocols (Model, Memory, Permission), simplified Tool, AgentGraph placeholder, unified error taxonomy. Compiling alongside existing code with zero behavioral change. This is the blueprint phase: new types are defined but nothing consumes them yet.

**Depends on**: Nothing (first phase)

**Requirements**: RUNTIME-01, RUNTIME-02, RUNTIME-03, RUNTIME-04, RUNTIME-05, RUNTIME-06, MEM-01, MEM-03, PERM-01, PERM-02, TOOL-01, TOOL-02, TOOL-03, MODEL-01, MODEL-05, GRAPH-01

**Success Criteria** (what must be TRUE):

  1. `AgentRuntime` actor protocol defined with property slots for all subsystems: `modelProvider`, `memoryStore`, `permissionEngine`, `toolEngine`, `contextManager`, `profileManager`, `graphEngine` (placeholder), `hookSystem`. Central actor is the single consumer entry point replacing `QueryEngine` + `LLMClient`
  2. `LanguageModel` protocol (ModelProvider interface) defined with `capabilities` property and `respond(to:streamingInto:)` method; `LanguageModelCapabilities` struct unified across Core and App
  3. `AgentRuntimeError` enum exists with unified cases grouped by subsystem (model, memory, permission, tool, graph errors); replaces fragmented `LLMError` + `DeepSeekError`
  4. `Transcript` struct with typed entries (`.instruction`, `.prompt`, `.response`, `.toolCall`, `.toolOutput`, `.thinking`, `.system`) defined as canonical conversation history
  5. `AgentProfile` struct bundling agent identity: `name`, `instructions`, `tools`, `model`, `permissionMode`, `memoryScope`. Forward-compatible with `DynamicProfile`
  6. `MemoryStore` protocol defined with `store/retrieve/search/summarize/forget` interface; `AgentState` property-wrapper protocol surface reserved (not implemented)
  7. `AgentPermission` enum (runtime-level: `.readFiles`, `.writeFiles`, `.network`, `.runCommands`, etc.) and upgraded `PermissionEngine` protocol (subsystem-level, not tool-level)
  8. Simplified `Tool` protocol (~6 members) coexists with existing 30+ member protocol; `ToolMetadata` struct defined; no tool files modified
  9. `LanguageModelExecutor` protocol (Core internal) and `GenerationChannel` protocol defined as ModelProvider backend contract and streaming abstraction
  10. `AgentGraph` protocol + `AgentNode` concept defined as type-slots (not implemented) — ordered DAG of AgentNodes, forward-compatible with WWDC27 AgentGraph
  11. All 258+ existing tests pass without modification — new types are additive, not substitutive

**Plans**: 3 plans
Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Foundation leaf types: AgentRuntimeError, Transcript, AgentPermission, PermissionEngine protocol, ToolOutput, GenerationChannel (6 requirements)
- [x] 01-02-PLAN.md — Provider protocols: LanguageModel, LanguageModelCapabilities, LanguageModelExecutor, MemoryStore, AgentStateProtocol, ToolMetadata (6 requirements)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-03-PLAN.md — Top-level agent types: AgentTool protocol, AgentProfile, AgentGraph type-slots, AgentRuntime actor protocol (4 requirements)

### Phase 2: Session, Streaming & Structured Output

**Goal**: `AgentRuntime` can run an agent loop end-to-end (with mock ModelProvider), emitting provider-agnostic `SessionEvent` snapshots via `AsyncThrowingStream`. Snapshot streaming accumulates correctly (no double-render). `GenerationSchema` produces JSON schema from Codable types at runtime. The Runtime core works — models and memory providers are mocks, but the orchestration is real.

**Depends on**: Phase 1

**Requirements**: STREAM-01, STREAM-02

**Success Criteria** (what must be TRUE):

  1. `AgentRuntime.respond(to:)` completes a turn with mock ModelProvider: prompt appended to Transcript, mock response received, Transcript updated, MemoryStore notified
  2. `AgentRuntime.streamResponse(to:)` yields `SessionEvent` snapshots via `AsyncThrowingStream`, with correct progressive accumulation (text builds, no duplication)
  3. `PartiallyGenerated<T>` snapshots diff correctly against previous state — a renderer consuming only snapshots produces identical output to a consumer of raw deltas (shadow-mode validation)
  4. `GenerationSchema` protocol produces valid JSON schema from a Codable Swift type at runtime (e.g., `BashParams` struct → `{"type":"object","properties":{"command":{"type":"string"}}}`)
  5. Runtime correctly routes: model calls → ModelProvider, permission checks → PermissionEngine, memory writes → MemoryStore, tool calls → ToolEngine
  6. All existing tests pass; new test suites cover Runtime agent loop, snapshot accumulation, runtime schema generation, and subsystem routing

**Plans**: 3 plans

**Wave 1**

- [x] 02-01-PLAN.md — Core streaming types: SessionEvent, PartiallyGenerated, GenerationSchema, RuntimeGenerationChannel
- [x] 02-02-PLAN.md — Subsystem stubs (DefaultToolEngine, NoOp stubs) + Mock providers (MockLanguageModel, MockMemoryStore, MockPermissionEngine)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-03-PLAN.md — AgentRuntimeImpl actor: agent loop, subsystem routing, reentrancy guard, integration tests

### Phase 3: Provider Implementations

**Goal**: All three ModelProviders (Anthropic, DeepSeek unified, OpenAI) respond through `LanguageModelExecutor`. AnthropicProvider absorbs LLMClient internals. DeepSeekProvider unifies dual code paths. SQLiteMemoryStore implements MemoryStore protocol. PermissionEngine upgraded to AgentPermission taxonomy. Provider-specific wire types (`ContentBlock`, `StreamEvent`, SSE parsing) are internal to each provider — consumers see only `SessionEvent` values.

**Depends on**: Phase 2

**Requirements**: MEM-02, MODEL-02, MODEL-03, MODEL-04

**Success Criteria** (what must be TRUE):

  1. `AnthropicProvider` translates `Transcript` to Anthropic Messages API format, streams responses through `GenerationChannel` as `SessionEvent` snapshots; all existing Anthropic streaming features (thinking, tool use, cache control) work through the new path
  2. `DeepSeekProvider` handles both Anthropic-compat and OpenAI-compat endpoints from a single code path (internal `APICompatibility` switch); both paths produce identical `SessionEvent` output for equivalent inputs
  3. `OpenAIProvider` maps Chat Completions API responses to `SessionEvent` snapshots with function calling support; replaces current stub
  4. Provider-specific types (`ContentBlock`, `StreamEvent` enum, SSE event parsing logic) confined to `Sources/SwiftAgentCore/AgentRuntime/Providers/` — grep for `StreamEvent` outside the Providers directory returns zero results
  5. `SQLiteMemoryStore` passes MemoryStore protocol conformance tests: store, retrieve, search (LIKE-based), summarize (heuristic), forget, namespace listing, schema migration
  6. `PermissionEngine` accepts `AgentPermission` taxonomy and correctly gates tool calls, memory operations, and (simulated) network requests
  7. All existing tests pass; new Provider test suites verify cross-provider output equivalence (identical Transcript + Tools → semantically identical SessionEvent sequences across all three ModelProviders)

**Plans**: 4 plans

Plans:
**Wave 1** *(all plans independent — zero file overlap)*

- [x] 03-01-PLAN.md — AnthropicProvider: absorbs LLMClient internals, Transcript→Anthropic Messages API, SSE→SessionEvent parsing (MODEL-02)
- [x] 03-02-PLAN.md — DeepSeekProvider: unified dual-path with APICompatibility switch, Anthropic+OpenAI compat endpoints (MODEL-03)
- [x] 03-03-PLAN.md — OpenAIProvider: Chat Completions API with function calling, multi-chunk tool accumulation, o4 reasoning (MODEL-04)
- [x] 03-04-PLAN.md — SQLiteMemoryStore + AgentPermissionBridge: persistent SQLite3 storage, AgentPermission→PermissionEngine adapter (MEM-02)

### Phase 4: Migration, Wiring & Cleanup

**Goal**: All 60+ tools adopt the simplified `Tool` protocol. CLI `ChatCommand` and App `ThreadViewModel` consume `LanguageModelSessionImpl` as their primary API surface with direct replacement (per D-08, no feature flags). Deprecated types (`LLMClient`, `StreamEvent`, `QueryEngine`, `ProviderRegistry`, `DeepSeekClient`, `AgentSessionManager`, `App/LLM/`, `Storage/`, `MessageNormalizer`, old `Tool` protocol + `ToolUseContext`) are removed. Per-provider normalization replaces shared `MessageNormalizer` (per D-17). Every existing test passes.

**Depends on**: Phase 3

**Requirements**: MIG-01, MIG-02, MIG-03, MIG-04, MIG-05

**Success Criteria** (what must be TRUE):

  1. All 60+ tools conform to simplified `Tool` protocol; per-tool metadata migrated to `ToolMetadata` registered via `ToolEngine`
  2. CLI `ChatCommand` and App `ThreadViewModel` use `LanguageModelSessionImpl.streamResponse(to:)` for agent interactions; old `QueryEngine` + `LLMClient` + `AgentSessionManager` paths removed
  3. Deprecated types fully removed: `LLMClient`, `StreamEvent`, `LLMStreamParser`, `QueryEngine`, `ToolExecutor`, `SubAgentManager`, `Compactor`, `RetryPolicy`, `SortedJSON`, `ChatToolInputAccumulator`, `ChatToolExecutionScheduler`, `StatusLine`, old `Tool` protocol + `ToolUseContext`, `AgentSessionManager`, `AppAgentProvider`, `App/LLM/` (5 files), `App/DeepSeek/` (4 files), `ProviderRegistry`, `Storage/` (8 files), `MessageNormalizer`, `EvalCommand`
  4. `MessageNormalizer` (848 lines, 17-pass pipeline) deleted; normalization handled per-provider (D-17) — each provider translates `Transcript` → API wire format internally
  5. Zero new `nonisolated(unsafe)` annotations; the count decreases from 4 to 2 (LLMClient removed, SwiftAgentPaths removed; only TerminalView closures remain)
  6. All 258+ existing tests pass after cleanup; no test files reference removed types

**Plans**: 6 plans

Plans:
**Wave 1** *(foundation — all downstream plans depend on this)*

- [ ] 04-01-PLAN.md — Foundation plumbing: rename RuntimeAgentTool.Input→Arguments + call(_:)→call(arguments:) per D-07; extract JSONSchema/InterruptBehavior from Types/Tool.swift; implement real type-erased tool execution in DefaultToolEngine.execute() (MIG-01)

**Wave 2** *(tool migration batches — depends on Wave 1)*

- [ ] 04-02-PLAN.md — Batch 1: 15 read-only tools (FileRead, Grep, Glob, WebSearch, WebFetch, ListSkills, ToolSearch, etc.) + Batch1ToolRegistry (MIG-01)

**Wave 3** *(protocol deletion + remaining tool batches — depends on Wave 2)*

- [ ] 04-03-PLAN.md — Delete old Tool protocol + ToolUseContext per D-06; Batch 2 (4 file mutation tools) + Batch 3 (5 command execution tools) + old Tools/ directory cleanup (MIG-01, MIG-03)
- [ ] 04-04-PLAN.md — Batches 4+5: 20 task/agent/workflow tools + 16 MCP/config/cron/misc tools; relocate shared types from old Tools/; rename RuntimeAgentTool→Tool (MIG-01)

**Wave 4** *(CLI consumer wiring — depends on Wave 3)*

- [ ] 04-05-PLAN.md — Rewire ChatCommand to LanguageModelSessionImpl per D-08/D-09; build fresh SessionEventRenderer per D-10; delete 13 deprecated Core types (LLMClient, QueryEngine, StreamEvent, ToolExecutor, SubAgentManager, Compactor, LLMStreamParser, RetryPolicy, SortedJSON, ChatToolInputAccumulator, ChatToolExecutionScheduler, StatusLine) per D-12 (MIG-02, MIG-03)

**Wave 5** *(App consumer wiring + final cleanup — depends on Wave 4)*

- [ ] 04-06-PLAN.md — Rewire ThreadViewModel to LanguageModelSessionImpl per D-11; delete App/Agent/ (3), App/LLM/ (5), App/DeepSeek/ (4), Storage/ (8), MessageNormalizer, EvalCommand per D-12/D-13/D-14/D-15/D-16/D-17; fix 15 test files; verify full test suite passes (MIG-02, MIG-03, MIG-04, MIG-05)

**UI hint**: yes

## Progress

**Execution Order:**
Phases execute sequentially: 1 → 2 → 3 → 4 (dependency chain: types → runtime → providers → migration)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. AgentRuntime Core Protocols | 3/3 | Complete    | 2026-06-25 |
| 2. Session, Streaming & Structured Output | 3/3 | Complete    | 2026-06-25 |
| 3. Provider Implementations | 4/4 | Complete   | 2026-06-25 |
| 4. Migration, Wiring & Cleanup | 0/6 | Planned | - |

## Design Rationale (4-phase vs 8-phase)

The original 8-phase plan split types, tools, executors, streaming, and migration into separate waves with parallel execution. The revised 4-phase structure recognizes the linear dependency chain while combining groups that are architecturally cohesive:

- **Phase 1 combines all type-level work** (protocols, structs, enums, type-slots). All new types are additive with zero behavioral change — defining them together avoids the risk of defining half a protocol without its dependencies. The AgentRuntime protocol surface reveals the full architecture shape from day one.
- **Phase 2 builds the Runtime loop + streaming + structured output together.** The Runtime is meaningless without streaming, and `PartiallyGenerated<T>` is the streaming payload. Building them separately creates integration risk. A mock ModelProvider validates the orchestration without waiting for real backends.
- **Phase 3 implements all Providers together** (Model × 3 + Memory × 1 + Permission upgrade). All share the Provider contracts defined in Phase 1; building Anthropic first proves the contract, then DeepSeek/OpenAI/Memory are simpler additions. Wire-format isolation enforced by directory structure.
- **Phase 4 is one continuous "land the plane" effort** — tool migration, consumer wiring, deprecated type removal, and MessageNormalizer adaptation. Wiring consumers before tools are migrated creates dead-end integration paths.

## WWDC27 Forward Compatibility

Every Phase 1 type-slot is designed to accept predicted WWDC27 capabilities without breaking changes:

| Phase 1 Type-Slot | WWDC27 Prediction | Migration Path |
|-------------------|-------------------|----------------|
| `AgentGraph` protocol | AgentKit WorkflowGraph | Add `GraphEngine` implementation behind existing protocol |
| `AgentNode` concept | Agent orchestration DAG | Add node types (Planner, Researcher, Coder, Reviewer) |
| `AgentState` protocol surface | `@AgentState` property-wrapper | Swap Mirror-based runtime for macro when macOS 27+ available |
| `AgentPermission` enum | macOS AgentSandbox | Map enum cases to system permission dialogs |
| `MemoryStore` protocol | SemanticMemoryStore / VectorMemoryStore | Add provider implementations behind existing protocol |
| `Tool` protocol (~6 members) | AgentIntent auto-discovery | `AgentIntent` protocol refines `Tool` with auto-registration |

---
*Last updated: 2026-06-25 — Phase 1 complete, Phase 2 complete, Phase 3 complete (10 plans, 22 requirements fulfilled)*
*Phase 4 planned — 6 plans covering 5 requirements (MIG-01, MIG-02, MIG-03, MIG-04, MIG-05)*
