# Project: SwiftAgent Agent Runtime

## What This Is

Reorganize SwiftAgent's AI Agent API from an Anthropic-specific LLM client into a **model-agnostic Agent Runtime** — an operating system for AI agents where inference models are just one category of swappable Provider plugins. The architecture targets Apple's FoundationModels WWDC25→26→27 trajectory, specifically the predicted WWDC27 "AgentKit / Agent OS" direction where the framework splits into FoundationModels (inference only) and AgentKit (agent orchestration, memory, permissions, evaluation).

**This is not an API wrapper reorganization. This is building the kernel of an Agent Operating System.**

## Core Value

**Models are peripherals, not the CPU.** The Agent Runtime — not any specific LLM — is the architecture's center. Memory, permissions, tool execution, context management, and agent orchestration are first-class subsystems with their own Provider interfaces. FoundationModels, Claude, OpenAI, and DeepSeek are interchangeable `ModelProvider` implementations. SQLite, Firestore, and VectorDB are interchangeable `MemoryProvider` implementations. This matches the WWDC27 predicted direction: `AgentKit` (agent orchestration) sits above `FoundationModels` (inference only).

## Context

- **Brownfield refactoring** of `/Users/jim/SwiftAgent` (Swift 6, SPM, 3 targets)
- **Current state:** `SwiftAgentCore/LLM/` (LLMClient, LLMStreamParser, ModelRegistry, RetryPolicy), `SwiftAgentCore/Agent/` (QueryEngine, ToolExecutor, StreamRenderer), `SwiftAgentCore/Types/` (Tool, Conversation, StreamEvent), `SwiftAgentApp/LLM/` (LLMProvider, ProviderRegistry, AnthropicProvider, DeepSeekProvider, OpenAIProvider), `SwiftAgentApp/DeepSeek/` (DeepSeekClient, standalone)
- **Codebase mapped:** `.planning/codebase/` (7 docs)
- **258+ tests, 60+ suites** — must keep passing
- **References:** Apple FoundationModels docs (WWDC25-286, WWDC25-301, WWDC26-339), `AboutAppleFoundationModels.md` (WWDC25→26→27 full trajectory)

## Target Architecture

```
CLI / App
  │
  ▼
AgentRuntime                       ← THE central abstraction (≈ OS kernel)
  │
  ├── SessionManager               ← conversation lifecycle, transcript, multi-turn state
  ├── ModelProvider                ← inference backends (Anthropic, DeepSeek, OpenAI, future Apple)
  ├── ToolEngine                   ← capability registry + execution pipeline
  ├── PermissionEngine             ← runtime-level permission system (not tool-level)
  ├── MemoryStore                  ← persistent memory (SQLite, Firestore, Vector, Semantic)
  ├── ContextManager               ← token budget, compaction, context window
  ├── GraphEngine                  ← AgentGraph placeholder (Planner → Research → Code → Review)
  ├── EvaluationEngine             ← quality assessment, guardrails, output validation
  ├── ProfileManager               ← agent identity, instructions, tool sets (DynamicProfile)
  └── HookSystem                   ← event hooks (pre/post tool, pre/post turn)
```

### Provider Subsystem (each category swappable)

```
AgentRuntime
  │
  ├── ModelProvider
  │   ├── AnthropicProvider        ← wraps Anthropic Messages API
  │   ├── DeepSeekProvider         ← unified single code path
  │   ├── OpenAIProvider           ← Chat Completions API
  │   └── (future: AppleProvider, MLXProvider, GeminiProvider)
  │
  ├── MemoryProvider
  │   ├── SQLiteMemoryStore        ← local persistent memory
  │   ├── FirestoreMemoryStore     ← cloud-synced memory
  │   └── VectorMemoryStore        ← semantic search
  │
  └── PermissionProvider
      ├── LocalPermissionEngine    ← file system, network, sandbox
      └── (future: AgentSandbox)   ← macOS App-level sandboxing
```

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| `AgentRuntime` as central abstraction, not `LanguageModelSession` | WWDC27 predicted split: FoundationModels (inference) → AgentKit (orchestration). Models are peripherals, not the CPU | Architecture centers on `AgentRuntime`; `LanguageModel` is one Provider among many |
| Models → ModelProvider; Memory → MemoryProvider; Permissions → PermissionEngine | Claude Code's operational harness (~98% of code) is everything beyond LLM calls. The runtime must treat all subsystems as first-class pluggable providers | Three Provider protocols (Model, Memory, Permission) each with swappable implementations |
| `AgentGraph` type-slots reserved in Phase 1, not implemented | WWDC27 prediction: AgentGraph = Planner → Research → Code → Review orchestration. Must design protocol surface now to avoid dead-end integration later | `AgentGraph` protocol + `AgentNode` concept defined as placeholder types; implemented in future phase |
| `AgentState` property-wrapper concept for persistent agent memory | WWDC27 prediction: `@AgentState` similar to `@Observable` + SwiftData. Session history is insufficient; agents need cross-session persistent state | `MemoryStore` protocol with `@AgentState`-compatible design (property-level read/write with automatic persistence) |
| Tool → AgentIntent direction | WWDC27 prediction: tools auto-discovered like AppIntents, not manually registered. Protocol design must not block this evolution | Simplified `Tool` protocol (~6 members) designed to be forward-compatible with `AgentIntent` auto-discovery |
| All other decisions from v1 carry forward | FoundationModels v2 direction unchanged | LanguageModel protocol, snapshot streaming, wire-format isolation, DeepSeek unification, type-driven output all retained |

## Requirements

### Validated

- ✓ Tool system with 43+ tools, one per file — existing
- ✓ Permission engine with allow/deny/ask rules — existing (upgraded to Runtime-level in this milestone)
- ✓ File-based CC-compatible persistence — existing
- ✓ Streaming with thinking/redacted thinking support — existing
- ✓ MCP server integration — existing
- ✓ Hook system — existing
- ✓ Model registry with aliases — existing
- ✓ Retry with exponential backoff — existing
- ✓ Context compaction — existing
- ✓ 258+ tests, 60+ suites — existing

### Active

#### AgentRuntime Core (RUNTIME-01 to RUNTIME-06)

- [ ] **RUNTIME-01**: `AgentRuntime` as central actor replacing `QueryEngine` + `LLMClient` as the primary consumer API surface. Owns all subsystems (Model, Memory, Permission, Tools, Context, Profile). Entry points: CLI `ChatCommand`, App `ThreadViewModel`.
- [ ] **RUNTIME-02**: `LanguageModel` protocol (ModelProvider interface). Model has `capabilities: LanguageModelCapabilities`, creates sessions. Models are plugins — one of several Provider types under AgentRuntime.
- [ ] **RUNTIME-03**: `LanguageModelCapabilities` struct replacing dual `ModelInfo` types. Unified across Core and App.
- [ ] **RUNTIME-04**: `AgentRuntimeError` enum replacing fragmented `LLMError` + `DeepSeekError`. Unified across ALL subsystems: model errors, memory errors, permission errors, tool errors, graph errors.
- [ ] **RUNTIME-05**: `Transcript` struct with typed entries (`.instruction`, `.prompt`, `.response`, `.toolCall`, `.toolOutput`). Canonical conversation history consumed by MemoryStore.
- [ ] **RUNTIME-06**: `AgentProfile` struct bundling agent identity: `name`, `instructions`, `tools`, `model`, `permissionMode`, `memoryScope`. Forward-compatible with `DynamicProfile` runtime switching.

#### Memory Subsystem (MEM-01 to MEM-03)

- [ ] **MEM-01**: `MemoryStore` protocol defining persistent agent memory interface: `store(key:value:)`, `retrieve(key:)`, `search(query:)`, `summarize()`, `forget(key:)`. Provider-pluggable (SQLite, Firestore, Vector).
- [ ] **MEM-02**: `SQLiteMemoryStore` implementing `MemoryStore`. Replaces ad-hoc file-based persistence in `SwiftAgentStore`. User preferences, project context, and session summaries persisted.
- [ ] **MEM-03**: `AgentState` property-wrapper concept (design only — implementation deferred). `@AgentState var preferences: Preferences` with automatic MemoryStore read/write. Type-slot reserved in MemoryStore protocol for future property-level persistence.

#### Permission Subsystem (PERM-01 to PERM-02)

- [ ] **PERM-01**: `AgentPermission` enum at Runtime level (not Tool level): `.readFiles`, `.writeFiles`, `.network`, `.contacts`, `.calendar`, `.runCommands`, `.delete`. Maps to macOS permission model for future `AgentSandbox`.
- [ ] **PERM-02**: `PermissionEngine` upgraded from tool-level gate to Runtime-level subsystem. All tool calls, memory reads/writes, and network requests pass through unified permission check.

#### Simplified Tool Protocol (TOOL-01 to TOOL-03)

- [ ] **TOOL-01**: Simplified `Tool` protocol (~6 members): `name`, `description`, `associatedtype Input: Codable`, `inputSchema`, `func call(_:) async throws -> ToolOutput`. Forward-compatible with `AgentIntent` auto-discovery. All rendering/metadata members → `ToolMetadata`.
- [ ] **TOOL-02**: `ToolMetadata` struct: `searchHint`, `isEnabled`, `isReadOnly`, `isConcurrencySafe`, `isDestructive`, `interruptBehavior`, `activityDescription`. Populated via `ToolEngine` at registration.
- [ ] **TOOL-03**: `ToolOutput` enum replacing `ToolResult` in public API. Cases: `string(String)`, `blocks([ContentBlock])`. Wire-format types become internal to each ModelProvider.

#### ModelProvider Layer (MODEL-01 to MODEL-05)

- [ ] **MODEL-01**: `LanguageModelExecutor` protocol (Core internal) as ModelProvider backend contract. Each executor owns its wire format translation entirely.
- [ ] **MODEL-02**: `AnthropicProvider` implementing `LanguageModelExecutor`. `StreamEvent`, `ContentBlock`, `ContentBlockAccumulator`, `safeParseJSON` become internal. All current Anthropic features preserved.
- [ ] **MODEL-03**: `DeepSeekProvider` implementing `LanguageModelExecutor`. Single code path with internal `APICompatibility` switch (Anthropic-compat vs OpenAI-compat). Replaces dual paths.
- [ ] **MODEL-04**: `OpenAIProvider` implementing `LanguageModelExecutor`. Full GPT/O-series support. Replaces current stub.
- [ ] **MODEL-05**: `GenerationChannel` protocol for provider-to-runtime streaming. Runtime receives typed events — never raw SSE tokens.

#### Streaming & Structured Output (STREAM-01 to STREAM-02)

- [ ] **STREAM-01**: `SessionEvent` enum as provider-agnostic streaming events. Cases: `responseDelta`, `thinkingDelta`, `toolCallRequested`, `toolCallCompleted`, `turnCompleted`, `error`. Replaces token-level `StreamEvent`.
- [ ] **STREAM-02**: Snapshot streaming via `PartiallyGenerated<T>`. Runtime emits typed progress snapshots. Mirror-based generation until macOS 27+ enables `@Generable`.

#### AgentGraph Placeholder (GRAPH-01)

- [ ] **GRAPH-01**: `AgentGraph` protocol + `AgentNode` concept defined as type-slots. Not implemented — design surface only. Graph = ordered DAG of AgentNodes (Planner → Researcher → Coder → Reviewer). Forward-compatible with WWDC27 `AgentGraph` / `WorkflowGraph`.

#### Migration & Cleanup (MIG-01 to MIG-05)

- [ ] **MIG-01**: Migrate all 60+ tools to simplified `Tool` protocol. `searchHint` (55), `isEnabled` (39), `shouldDefer` (33) → `ToolMetadata` via `ToolEngine`. `ToolUseContext` (70+ fields) decoupled from Tool protocol.
- [ ] **MIG-02**: Wire CLI `ChatCommand` and App `ThreadViewModel` to `AgentRuntime`. Feature-flag gated (`AGENT_RUNTIME_ENABLED`). Shadow mode: old path runs alongside new until validated.
- [ ] **MIG-03**: Remove deprecated types: `LLMClient`, `StreamEvent` (public), `LLMStreamParser` (public), `QueryEngine`, `ProviderRegistry`, dual `ModelInfo`, `DeepSeekClient` (standalone path).
- [ ] **MIG-04**: All 258+ existing tests pass. New test suites: `AgentRuntime`, each Provider, simplified `Tool`, `MemoryStore`, `PermissionEngine`, snapshot streaming.
- [ ] **MIG-05**: `MessageNormalizer` (17-pass pipeline) adapted from `ContentBlock[]` → `Transcript` entries. Preserved functionality, new type input.

### Out of Scope

- `@Generable` / `@Guide` Swift macros — use runtime Mirror approach (requires macOS 27+ for macros)
- Apple `SystemLanguageModel` / `PCCLanguageModel` providers — requires macOS 27+
- `AgentGraph` full implementation — type-slots only in this milestone
- `@AgentState` property-wrapper full implementation — protocol design only
- `AgentIntent` auto-discovery — protocol forward-compatibility only
- Multi-Agent concurrent orchestration — AgentGraph placeholder only
- Vision/multimodal support — ModelProvider capability flag only
- RAG / Spotlight integration — future phase
- Background Agent (`AgentProcess`) — future phase
- Modifying CLI or App UI layer beyond wiring to `AgentRuntime`

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

---
*Last updated: 2026-06-25 after WWDC27 Agent OS direction update*
