# Requirements: SwiftAgent FoundationModels API Reorganization

## v1 Requirements

### Core Protocols (API-01 to API-06)

- [ ] **API-01**: `LanguageModel` protocol defining model identity, capabilities, and session creation. Model has `capabilities: LanguageModelCapabilities` and creates `LanguageModelSession` instances. Model is `Sendable`, models are plugins.
- [ ] **API-02**: `LanguageModelCapabilities` struct replacing dual `ModelInfo` types. Fields: `supportsStreaming`, `supportsToolUse`, `supportsThinking`, `supportsVision`, `contextWindow`, `maxOutputTokens`, `providerDisplayName`. Unified across Core and App.
- [ ] **API-03**: `LanguageModelSession` as unified public API replacing `QueryEngine` + `LLMClient` as primary consumer surface. Owns transcript, tools, streaming state. Method: `respond(to:generating:tools:)` → `AsyncSequence<SessionEvent>`.
- [ ] **API-04**: `LanguageModelError` enum replacing fragmented `LLMError` + `DeepSeekError`. Cases: `contextSizeExceeded`, `rateLimited(retryAfter:)`, `unauthorized`, `serverError(status:body:)`, `unsupportedCapability`, `timeout`, `invalidResponse`.
- [ ] **API-05**: `SessionEvent` enum as provider-agnostic streaming events replacing token-level `StreamEvent`. Cases: `responseDelta(text:)`, `thinkingDelta(text:)`, `toolCallRequested(name:id:)`, `toolCallCompleted(id:output:)`, `turnCompleted(usage:)`, `error(SessionError)`.
- [ ] **API-06**: `Transcript` struct maintaining conversation history as typed entries (`.instruction`, `.prompt`, `.response`, `.toolCall`, `.toolOutput`). Replaces raw `[Message]` / `[ContentBlock]` in public API.

### Simplified Tool Protocol (API-07 to API-09)

- [ ] **API-07**: Simplified `Tool` protocol with ~6 core members: `name: String`, `description: String`, `associatedtype Input: Codable`, `inputSchema: JSONSchema`, `func call(_ input: Input) async throws -> ToolOutput`. All rendering/metadata members move to `ToolMetadata`.
- [ ] **API-08**: `ToolMetadata` struct holding per-tool operational data: `searchHint`, `isEnabled`, `isReadOnly`, `isConcurrencySafe`, `isDestructive`, `interruptBehavior`, `activityDescription`. Populated via `ToolRegistry` at registration time.
- [ ] **API-09**: `ToolOutput` enum replacing `ToolResult` in public API. Cases: `string(String)`, `blocks([ContentBlock])`. Content blocks become internal detail of each executor.

### Executor Layer (API-10 to API-13)

- [ ] **API-10**: `LanguageModelExecutor` protocol (Core internal) as backend contract. Methods: `func respond(to request: GenerationRequest, streamingInto channel: GenerationChannel) async throws`. Each executor owns its wire format translation.
- [ ] **API-11**: `AnthropicExecutor` implementing `LanguageModelExecutor`, wrapping current `LLMClient` internals. `StreamEvent`, `ContentBlock`, `ContentBlockAccumulator`, `safeParseJSON` become internal to this executor.
- [ ] **API-12**: `DeepSeekExecutor` implementing `LanguageModelExecutor`, unifying dual DeepSeek paths (Anthropic-compat + standalone OpenAI-compat). Single executor, single code path.
- [ ] **API-13**: `OpenAIExecutor` implementing `LanguageModelExecutor`, replacing current stub. Supports GPT/O-series models via OpenAI-compatible API.

### Streaming Model (API-14 to API-15)

- [ ] **API-14**: `GenerationChannel` protocol for executor-to-session streaming. Session receives typed events, never raw SSE tokens. Channel abstracts over `AsyncThrowingStream` or callback-based delivery.
- [ ] **API-15**: Snapshot streaming via `PartiallyGenerated<T>` struct. For structured output requests, session emits typed progress snapshots as properties fill in, not raw JSON deltas. Runtime implementation using `Mirror` until `@Generable` macro is available (requires macOS 26+).

### Structured Output (API-16)

- [ ] **API-16**: Type-driven structured output via `GenerationSchema` protocol. `Codable` types conform to produce JSON schema at runtime. Replaces manual `JSONSchema` construction. Forward-compatible with `@Generable` macro when deployment target allows.

### Migration & Cleanup (API-17 to API-20)

- [ ] **API-17**: Migrate all 60+ tools to simplified `Tool` protocol. Each tool's 30+ member overrides mapped to `ToolMetadata` entries via `ToolRegistry`. `searchHint` (55 overrides), `isEnabled` (39), `shouldDefer` (33) handled first.
- [ ] **API-18**: Wire CLI (`ChatCommand`) and App (`AppViewModel`) to `LanguageModelSession`. Feature-flag gated. Old `QueryEngine` + `LLMClient` path remains until new path stable.
- [ ] **API-19**: Remove deprecated types after new path validated in production: `LLMClient` (becomes `AnthropicExecutor` internal), `StreamEvent` (becomes executor-internal), `LLMStreamParser` (moves to executor), `ProviderRegistry` (replaced by model registry), dual `ModelInfo` types.
- [ ] **API-20**: All 258+ existing tests pass after reorganization. Add new test suites for `LanguageModelSession`, each executor, simplified `Tool` protocol, and streaming model before removing old code paths.

### Agent Profile (API-21)

- [ ] **API-21**: `AgentProfile` struct bundling agent identity: `name`, `instructions`, `tools`, `model`, `permissionMode`. Maps to FoundationModels `DynamicProfile` concept. Session accepts profile at init, can swap at runtime.

## v2 Requirements (Deferred)

- `@Generable` / `@Guide` Swift macros for compile-time structured output (requires macOS 26+ deployment target)
- Apple `SystemLanguageModel` executor (requires macOS 26+)
- `PrivateCloudComputeLanguageModel` executor (requires macOS 26+)
- Multi-Agent orchestration / AgentGraph
- Vision/multimodal support via executor capability
- `DynamicProfile` runtime identity switching
- RAG / Spotlight integration

## Out of Scope

- Multi-Agent orchestration in the API layer — executor concern, not session primitive (per Cognition/Google guidance)
- Building `@Generable` Swift macros — use runtime equivalent until deployment target allows
- On-device Apple model integration — requires macOS 26+
- Modifying CLI or App UI layer beyond wiring to new API
- Changing `ToolUseContext` (70+ fields) — separate refactoring phase
- Modifying MCP, Hooks, or Permissions subsystems

## Traceability

| REQ-ID | Requirement | Phase | Research Source |
|--------|-------------|-------|-----------------|
| API-01 | LanguageModel protocol | 1 | STACK.md §2, ARCHITECTURE.md §Boundary Design |
| API-02 | LanguageModelCapabilities | 1 | FEATURES.md Table Stakes #1 |
| API-03 | LanguageModelSession | 2 | STACK.md §3, ARCHITECTURE.md §Core Protocols |
| API-04 | LanguageModelError | 1 | FEATURES.md Table Stakes #4 |
| API-05 | SessionEvent | 2 | STACK.md §4, FEATURES.md Table Stakes #3 |
| API-06 | Transcript | 1 | ARCHITECTURE.md §Core Public API |
| API-07 | Simplified Tool protocol | 3 | FEATURES.md Table Stakes #2, PITFALLS.md §1 |
| API-08 | ToolMetadata | 3 | PITFALLS.md §1 (searchHint/isEnabled migration) |
| API-09 | ToolOutput | 3 | ARCHITECTURE.md §Tool protocol |
| API-10 | LanguageModelExecutor | 4 | ARCHITECTURE.md §Core Internal Bridge |
| API-11 | AnthropicExecutor | 4 | ARCHITECTURE.md §Per-Provider Executors |
| API-12 | DeepSeekExecutor | 5 | FEATURES.md Table Stakes #5, PITFALLS.md §8 |
| API-13 | OpenAIExecutor | 5 | FEATURES.md Table Stakes #6 |
| API-14 | GenerationChannel | 2 | STACK.md §4, ARCHITECTURE.md §Streaming |
| API-15 | Snapshot streaming | 6 | FEATURES.md Differentiator #1, PITFALLS.md §2 |
| API-16 | Type-driven structured output | 6 | FEATURES.md Differentiator #2, STACK.md §6 |
| API-17 | Tool migration | 7 | PITFALLS.md §1 (55 searchHint, 39 isEnabled, 33 shouldDefer) |
| API-18 | Consumer wiring | 7 | ARCHITECTURE.md §Migration Strategy |
| API-19 | Remove deprecated types | 8 | PITFALLS.md §12 (legacy adapter deadline) |
| API-20 | All tests pass | All | PITFALLS.md §11 (test-first approach) |
| API-21 | AgentProfile | 1 | FEATURES.md Differentiator #4, AboutAppleFoundationModels.md |

---
*Last updated: 2026-06-25*
