# Requirements: SwiftAgent Agent Runtime

## v1 Requirements

### AgentRuntime Core (RUNTIME-01 to RUNTIME-06)

- [ ] **RUNTIME-01**: `AgentRuntime` as central actor replacing `QueryEngine` + `LLMClient` as the primary consumer API surface. Owns all subsystems: `ModelProvider`, `MemoryStore`, `PermissionEngine`, `ToolEngine`, `ContextManager`, `ProfileManager`, `GraphEngine` (placeholder), `HookSystem`. CLI and App wire to `AgentRuntime.shared`.
- [x] **RUNTIME-02**: `LanguageModel` protocol as `ModelProvider` interface. Model has `capabilities: LanguageModelCapabilities` and creates model sessions. Models are plugins — one Provider type among several under AgentRuntime. `Sendable`, actor-safe.
- [x] **RUNTIME-03**: `LanguageModelCapabilities` struct replacing dual `ModelInfo` types. Fields: `supportsStreaming`, `supportsToolUse`, `supportsThinking`, `supportsVision`, `contextWindow`, `maxOutputTokens`, `providerDisplayName`. Single source of truth across Core and App.
- [x] **RUNTIME-04**: `AgentRuntimeError` enum — unified error type across ALL subsystems. Cases grouped by subsystem: model errors (`rateLimited`, `unauthorized`, `serverError`, `timeout`, `contextSizeExceeded`, `invalidResponse`), memory errors (`storageFull`, `keyNotFound`, `migrationFailed`), permission errors (`denied`, `sandboxViolation`), tool errors (`notFound`, `executionFailed`, `validationFailed`), graph errors (`cycleDetected`, `nodeFailed`).
- [x] **RUNTIME-05**: `Transcript` struct — canonical conversation history with typed entries: `.instruction(String)`, `.prompt(String)`, `.response(String)`, `.toolCall(id:name:input:)`, `.toolOutput(id:output:)`, `.thinking(String)`, `.system(String)`. Replaces raw `[Message]` / `[ContentBlock]` in public API. Consumed by `MemoryStore` for persistent memory.
- [ ] **RUNTIME-06**: `AgentProfile` struct — agent identity bundle: `name: String`, `instructions: String`, `tools: [any Tool]`, `model: any LanguageModel`, `permissionMode: AgentPermission`, `memoryScope: MemoryScope`. Forward-compatible with FoundationModels `DynamicProfile` runtime switching.

### Memory Subsystem (MEM-01 to MEM-03)

- [x] **MEM-01**: `MemoryStore` protocol — persistent agent memory interface. Methods: `store(key:namespace:value:) async throws`, `retrieve(key:namespace:) async throws -> MemoryEntry?`, `search(query:namespace:) async throws -> [MemoryEntry]`, `summarize(namespace:) async throws -> String`, `forget(key:namespace:) async throws`, `listNamespace(_:) async throws -> [String]`. Provider-pluggable: SQLite (local), Firestore (cloud), Vector (semantic) implementations.
- [ ] **MEM-02**: `SQLiteMemoryStore` implementing `MemoryStore` — local persistent storage. Replaces ad-hoc file-based persistence currently in `SwiftAgentStore`. Stores: user preferences, project context, session summaries, tool usage patterns. Schema versioned with migration support.
- [x] **MEM-03**: `AgentState` property-wrapper concept — **design only, not implemented**. Protocol surface: `@AgentState<T: Codable>(key:namespace:store:) var value: T` with automatic MemoryStore read/write. Type-slot reserved in MemoryStore protocol for future property-level persistence (mirrors predicted WWDC27 `@AgentState` similar to `@Observable` + SwiftData).

### Permission Subsystem (PERM-01 to PERM-02)

- [x] **PERM-01**: `AgentPermission` enum — runtime-level permission taxonomy (not tool-level): `.readFiles(paths:)`, `.writeFiles(paths:)`, `.network(domains:)`, `.contacts`, `.calendar`, `.location`, `.camera`, `.microphone`, `.runCommands`, `.delete`, `.all`. Forward-compatible with predicted WWDC27 `AgentSandbox` and macOS permission model.
- [x] **PERM-02**: `PermissionEngine` upgraded — from tool-level gate to Runtime-level subsystem. All capability invocations (tool calls, memory reads/writes, network requests) route through unified permission check. Existing allow/deny/ask rules preserved. `AgentPermission` taxonomy maps to existing `PermissionRule` system.

### Simplified Tool Protocol (TOOL-01 to TOOL-03)

- [ ] **TOOL-01**: Simplified `Tool` protocol (~6 core members): `var name: String { get }`, `var description: String { get }`, `associatedtype Input: Codable`, `var inputSchema: JSONSchema { get }`, `func call(_ input: Input) async throws -> ToolOutput`. Forward-compatible with predicted WWDC27 `AgentIntent` auto-discovery pattern. All cross-cutting members (30+ → removed) migrate to `ToolMetadata`.
- [x] **TOOL-02**: `ToolMetadata` struct — per-tool operational data separated from protocol: `searchHint`, `isEnabled`, `isReadOnly`, `isConcurrencySafe`, `isDestructive`, `interruptBehavior`, `activityDescription`, `requiresApproval`, `permissionCategory`. Populated via `ToolEngine.register(tool:metadata:)` at registration time.
- [x] **TOOL-03**: `ToolOutput` enum replacing `ToolResult` in public API. Cases: `string(String)`, `blocks([ContentBlock])`. `ContentBlock` becomes internal to each ModelProvider — consumers never see wire-format types.

### ModelProvider Layer (MODEL-01 to MODEL-05)

- [x] **MODEL-01**: `LanguageModelExecutor` protocol (Core internal) — ModelProvider backend contract. Methods: `func respond(to request: ModelRequest, streamingInto channel: GenerationChannel) async throws`. Each executor owns its wire format translation, SSE parsing, and model-specific quirks entirely.
- [ ] **MODEL-02**: `AnthropicProvider` implementing `LanguageModelExecutor` — wraps current `LLMClient` internals. `StreamEvent`, `ContentBlock`, `ContentBlockAccumulator`, `safeParseJSON` become `private` / `internal` to this provider. All Anthropic-specific features (thinking, cache control, tool use, prompt caching) preserved.
- [ ] **MODEL-03**: `DeepSeekProvider` implementing `LanguageModelExecutor` — single unified code path with internal `APICompatibility` switch (Anthropic-compat `/anthropic/v1/messages` vs OpenAI-compat `/v1/chat/completions`). Replaces dual `DeepSeekProvider` + `DeepSeekClient` paths.
- [ ] **MODEL-04**: `OpenAIProvider` implementing `LanguageModelExecutor` — full Chat Completions API support. GPT-5.2, GPT-5.2-mini, o4 models. Function calling mapped to tool system. Replaces current stub.
- [x] **MODEL-05**: `GenerationChannel` protocol — provider-to-runtime streaming abstraction. Runtime receives typed `SessionEvent` values via `AsyncThrowingStream`, never raw SSE token strings. Abstracts over URLSession async bytes, WebSocket, or callback-based delivery.

### Streaming & Structured Output (STREAM-01 to STREAM-02)

- [ ] **STREAM-01**: `SessionEvent` enum — provider-agnostic streaming events replacing Anthropic-specific `StreamEvent`. Cases: `responseDelta(text:)`, `thinkingDelta(text:)`, `toolCallRequested(id:name:input:)`, `toolCallCompleted(id:output:isError:)`, `turnCompleted(usage:stopReason:)`, `error(AgentRuntimeError)`. No consumer outside `AgentRuntime/Providers/` sees raw model output.
- [ ] **STREAM-02**: Snapshot streaming via `PartiallyGenerated<T: Codable>` struct. For structured output requests, Runtime emits typed progress snapshots (properties fill in progressively), not raw JSON deltas. Runtime implementation using `Mirror` + `CodingKeys` until macOS 27+ deployment target enables `@Generable` macro. Shadow-mode validation: old delta path and new snapshot path run simultaneously; output equivalence verified before consumer cutover.

### AgentGraph Placeholder (GRAPH-01)

- [ ] **GRAPH-01**: `AgentGraph` protocol + `AgentNode` concept — **type-slots only, not implemented**. `AgentGraph` = ordered DAG of `AgentNode`s. Each `AgentNode` has: `agent: AgentProfile`, `inputs: [NodeInput]`, `outputs: [NodeOutput]`, `condition: NodeCondition?`. Placeholder for predicted WWDC27 AgentGraph / WorkflowGraph orchestration. Protocol surface designed so AgentRuntime can accept a Graph in a future phase without breaking changes.

### Migration & Cleanup (MIG-01 to MIG-05)

- [ ] **MIG-01**: Migrate all 60+ tools to simplified `Tool` protocol. Per-tool metadata extracted to `ToolMetadata` via `ToolEngine`. `searchHint` (55 overrides), `isEnabled` (39 overrides), `shouldDefer` (33 overrides) migrated first. `ToolUseContext` (70+ fields) decoupled from Tool protocol — remains as internal runtime context.
- [ ] **MIG-02**: Wire CLI `ChatCommand` and App `ThreadViewModel` to `AgentRuntime.shared`. Feature flag `AGENT_RUNTIME_ENABLED` gates new path. Old `QueryEngine` + `LLMClient` path remains operational until new path validated in shadow mode (both paths run, output compared).
- [ ] **MIG-03**: Remove deprecated types after shadow-mode validation: `LLMClient` (absorbed into AnthropicProvider), `StreamEvent` enum (becomes executor-internal), `LLMStreamParser` (moves to AnthropicProvider), `QueryEngine` (replaced by AgentRuntime), `ProviderRegistry` (replaced by AgentRuntime provider registry), dual `ModelInfo` types (replaced by `LanguageModelCapabilities`), `DeepSeekClient` standalone path (replaced by `DeepSeekProvider`).
- [ ] **MIG-04**: All 258+ existing tests pass. New test suites added for new types before old code removal: `AgentRuntimeTests`, `MemoryStoreTests`, `PermissionEngineTests`, `ToolMetadataTests`, `AnthropicProviderTests`, `DeepSeekProviderTests`, `OpenAIProviderTests`, `SessionEventTests`, `PartiallyGeneratedTests`, `AgentProfileTests`, `TranscriptTests`.
- [ ] **MIG-05**: `MessageNormalizer` (17-pass pipeline) adapted from `[ContentBlock]` input → `[Transcript.Entry]` input. Same normalization logic, new type. Validated against recorded API responses to ensure no behavioral change.

## v2 Requirements (Deferred)

- `@Generable` / `@Guide` Swift macros for compile-time structured output (requires macOS 27+)
- Apple `SystemLanguageModel` provider (requires macOS 27+)
- `PrivateCloudComputeLanguageModel` provider (requires macOS 27+)
- `AgentGraph` full implementation with `WorkflowGraph` execution engine
- `@AgentState` property-wrapper full implementation with automatic MemoryStore persistence
- `AgentIntent` auto-discovery (Tool → Intent automatic registration)
- Multi-Agent concurrent orchestration via AgentGraph
- Vision/multimodal support via ModelProvider capability
- `DynamicProfile` runtime identity switching
- RAG / Spotlight integration
- `AgentSandbox` macOS-level sandboxing
- `AgentProcess` background agent runtime
- `AgentKit` framework extraction (separate from FoundationModels inference layer)

## Out of Scope

- `@Generable` Swift macros implementation — use runtime Mirror approach
- On-device Apple model integration — requires macOS 27+
- `AgentGraph` execution engine — type-slots only
- `@AgentState` implementation — protocol design only
- Multi-Agent concurrent orchestration — AgentGraph placeholder only
- Vision/multimodal — ModelProvider capability flag only
- Background Agent (`AgentProcess`) — future phase
- Modifying CLI or App UI beyond wiring to `AgentRuntime`
- Changing `ToolUseContext` (70+ fields) internals — decouple from Tool protocol only

## Traceability

| REQ-ID | Requirement | Phase | Research Source |
|--------|-------------|-------|-----------------|
| RUNTIME-01 | AgentRuntime central actor | 1 | AboutAppleFoundationModels.md AgentRuntime §14, ARCHITECTURE.md |
| RUNTIME-02 | LanguageModel protocol | 1 | STACK.md §2, AboutAppleFoundationModels.md Model Abstraction §13 |
| RUNTIME-03 | LanguageModelCapabilities | 1 | FEATURES.md Table Stakes #1 |
| RUNTIME-04 | AgentRuntimeError | 1 | FEATURES.md Table Stakes #4, PITFALLS.md §9 |
| RUNTIME-05 | Transcript | 1 | ARCHITECTURE.md Core Public API |
| RUNTIME-06 | AgentProfile | 1 | AboutAppleFoundationModels.md Dynamic Profile §10 |
| MEM-01 | MemoryStore protocol | 1 | AboutAppleFoundationModels.md Memory System §8, WWDC27 Prediction §4 |
| MEM-02 | SQLiteMemoryStore | 3 | STACK.md, AboutAppleFoundationModels.md Memory §8 |
| MEM-03 | AgentState concept (design) | 1 | AboutAppleFoundationModels.md WWDC27 Prediction §2 |
| PERM-01 | AgentPermission enum | 1 | AboutAppleFoundationModels.md WWDC27 Prediction §5 |
| PERM-02 | PermissionEngine upgrade | 1 | PITFALLS.md, AboutAppleFoundationModels.md Permissions |
| TOOL-01 | Simplified Tool protocol | 1 | FEATURES.md Table Stakes #2, PITFALLS.md §1 |
| TOOL-02 | ToolMetadata | 1 | PITFALLS.md §1 (searchHint/isEnabled migration) |
| TOOL-03 | ToolOutput | 1 | ARCHITECTURE.md Tool protocol |
| MODEL-01 | LanguageModelExecutor protocol | 1 | ARCHITECTURE.md Core Internal Bridge |
| MODEL-02 | AnthropicProvider | 3 | ARCHITECTURE.md Per-Provider Executors |
| MODEL-03 | DeepSeekProvider (unified) | 3 | FEATURES.md Table Stakes #5, PITFALLS.md §8 |
| MODEL-04 | OpenAIProvider | 3 | FEATURES.md Table Stakes #6 |
| MODEL-05 | GenerationChannel | 1 | STACK.md §4, ARCHITECTURE.md Streaming |
| STREAM-01 | SessionEvent | 2 | STACK.md §4, FEATURES.md Table Stakes #3 |
| STREAM-02 | PartiallyGenerated<T> snapshot | 2 | FEATURES.md Differentiator #1, PITFALLS.md §2 |
| GRAPH-01 | AgentGraph type-slots | 1 | AboutAppleFoundationModels.md WWDC27 Prediction §1 |
| MIG-01 | Tool migration (60+ tools) | 4 | PITFALLS.md §1 (55 searchHint, 39 isEnabled, 33 shouldDefer) |
| MIG-02 | Consumer wiring (CLI + App) | 4 | ARCHITECTURE.md Migration Strategy |
| MIG-03 | Remove deprecated types | 4 | PITFALLS.md §12 (legacy adapter deadline) |
| MIG-04 | All tests pass + new suites | 4 | PITFALLS.md §11 (test-first approach) |
| MIG-05 | MessageNormalizer adaptation | 4 | PITFALLS.md §7 |

**Coverage: 29/29 requirements mapped (100%)**

---
*Last updated: 2026-06-25*
