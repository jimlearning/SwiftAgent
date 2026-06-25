# Feature Landscape: AI Agent Runtime API

**Domain:** AI coding agent runtimes (Claude Code / FoundationModels Agent Runtime pattern)
**Researched:** 2026-06-25
**Overall confidence:** HIGH

## Executive Summary

Production AI coding agent runtimes converge on a surprisingly minimal core. Claude Code's 510K-line codebase allocates only ~1.6% to decision logic -- the remaining ~98.4% is operational harness (permissions, compaction, tool execution, safety). Apple's FoundationModels takes the opposite design philosophy: a small, protocol-driven core where `LanguageModelSession` is the universal abstraction and models are swappable plugins. The convergence point is clear: **the agent loop is small; the harness is everything else.**

The key architectural insight from both Claude Code and FoundationModels is that the runtime is fundamentally a `while(true)` loop of (stream -> tool execute -> append result -> repeat). The difference is what each wraps around that loop: Claude Code wraps a monolithic operational harness; FoundationModels wraps a protocol boundary that enables model swapping. The reorganized SwiftAgent API should collapse both philosophies: a FoundationModels-shaped protocol surface backed by Claude Code-grade operational harness.

---

## 1. Table Stakes (Must Have or the Agent Is Useless)

These are features that every production coding agent runtime provides. Missing any one of them makes the product non-viable for real use.

### TS-1: LanguageModel protocol (model abstraction boundary)

| Attribute | Detail |
|-----------|--------|
| **Why expected** | Every major runtime (Claude Code, Codex, LangGraph) has a model abstraction. FoundationModels makes this the central architectural concept with `LanguageModel`. Without it, you cannot swap providers and are locked to a single inference backend. |
| **Complexity** | Medium |
| **FoundationModels shape** | `protocol LanguageModel: Sendable { var capabilities: LanguageModelCapabilities { get }; var executorConfiguration: Executor.Configuration { get } }` |
| **Notes** | This is both a table-stakes requirement AND the primary architectural goal of this reorganization. Models become plugins behind a protocol surface. Provider-specific wire types (ContentBlock, StreamEvent) become internal implementation details of each executor. |

### TS-2: LanguageModelSession (unified public API)

| Attribute | Detail |
|--------|--------|
| **Why expected** | FoundationModels centers on `LanguageModelSession` as the single public surface. Claude Code centers on `QueryEngine` + `LLMClient`. Every runtime has a single entry point for "talk to the model." Users should never need to know which model backs a session. |
| **Complexity** | Medium |
| **FoundationModels shape** | `LanguageModelSession` with `respond(to:)`, `streamResponse(to:)`, `transcript`, `isResponding`, profile management |
| **Notes** | This replaces the current dual surface of `QueryEngine` (agent loop) + `LLMClient` (API calls). The session owns the transcript, tools, instructions, and model reference. It is the "file descriptor" for an agent conversation. |

### TS-3: Tool protocol (model-callable functions)

| Attribute | Detail |
|--------|--------|
| **Why expected** | Without tools, the agent is just a chatbot. Every coding agent runtime supports model-driven function calling. Claude Code has 66+ tools. FoundationModels defines `Tool` as a protocol with ~4 members. |
| **Complexity** | Medium |
| **Target shape** | `protocol Tool { var name: String { get }; var description: String { get }; associatedtype Arguments: Generable; func call(arguments: Arguments) async throws -> ToolOutput }` |
| **Current state** | 30+ member `Tool` protocol (1156-line `Tool.swift`) -- radically oversized. Must be simplified to FoundationModels shape. |
| **Notes** | The per-tool operational harness (permission classification, concurrency safety, search hints, interrupt behavior) should live in tool metadata / tool registry, not on the protocol itself. The protocol is the contract with the model; the registry is the contract with the runtime. |

### TS-4: Streaming responses

| Attribute | Detail |
|--------|--------|
| **Why expected** | Users expect real-time output. Every LLM API supports SSE streaming. Every runtime exposes streaming either as token deltas (Claude Code, OpenAI) or snapshot snapshots (FoundationModels `AsyncSequence<PartiallyGenerated<T>>`). |
| **Complexity** | Medium |
| **Target shape** | FoundationModels snapshot streaming: `for await partial in session.streamResponse(to: prompt) { ... }` where `partial` is `T.PartiallyGenerated` (all fields Optional) |
| **Current state** | Token-delta streaming via `StreamEvent` enum with `textDelta`, `thinkingDelta`, `inputJSONDelta`. Anthropic-specific format. |
| **Notes** | Target architecture uses snapshot streaming over token deltas. FoundationModels emits `PartiallyGenerated<T>` snapshots where all fields are `Optional` -- the consumer sees the latest complete state, not individual token differences. This is higher-level and provider-agnostic. |

### TS-5: Conversation transcript / history management

| Attribute | Detail |
|--------|--------|
| **Why expected** | Multi-turn conversations are the entire point of an agent. The runtime must maintain history, inject it into requests, and expose it for inspection. FoundationModels provides `transcript` on the session. Claude Code maintains `conversationHistory: [Message]`. |
| **Complexity** | Low |
| **FoundationModels shape** | `session.transcript` -- a structured `Transcript` with typed entries: `.instructions`, `.prompt`, `.toolCalls`, `.toolOutput`, `.response` |
| **Notes** | The transcript is the session's source of truth. Compaction and context management operate on it. Wire-format messages (Anthropic `ContentBlock`, OpenAI `ChatCompletionMessage`) are internal translation artifacts -- the transcript is the canonical representation. |

### TS-6: Permission / safety engine

| Attribute | Detail |
|--------|--------|
| **Why expected** | Coding agents execute arbitrary shell commands and file operations. Without a permission engine, they are dangerous. Claude Code has a 7-mode permission system with AST-level bash analysis. FoundationModels WWDC26 dedicated an entire session (347) to agent security. |
| **Complexity** | High |
| **Current state** | `PermissionEngine` with 10-step pipeline, `PermissionStore` for persistent rules, `SafetyChecker` for AST-aware bash analysis. Already exists and must be preserved. |
| **Notes** | This is NOT part of the reorganized API surface -- it is operational harness that wraps tool execution, not a protocol the consumer sees. Keep it behind the `ToolExecutor` boundary. |

### TS-7: Context compaction

| Attribute | Detail |
|--------|--------|
| **Why expected** | Without compaction, conversations hit the context window limit and the agent stops working. Claude Code has a 4-layer cascading compaction pipeline. Every major runtime has some form of history summarization or truncation. |
| **Complexity** | High |
| **Current state** | `Compactor.swift` with LLM-based summarization, circuit breaker (max 3 consecutive failures). Must be preserved. |
| **Notes** | Compaction operates on the transcript, not on wire-format messages. It should be a session-level capability, not model-specific. |

### TS-8: Structured output / type-driven generation

| Attribute | Detail |
|--------|--------|
| **Why expected** | Both FoundationModels (`@Generable`) and Anthropic/OpenAI (structured outputs / JSON mode) support constrained generation. FoundationModels derives the schema from Swift types at compile time via `@Generable` macro. |
| **Complexity** | Medium |
| **FoundationModels shape** | `@Generable struct Foo { ... }` then `session.respond(generating: Foo.self)` returns `Response<Foo>` |
| **Notes** | Target is type-driven structured output that compiles the schema from Swift types. Manual `JSONSchema` construction (current approach) is error-prone and verbose. Initial implementation may use runtime schema derivation until `@Generable` macro is built. |

### TS-9: Error taxonomy

| Attribute | Detail |
|--------|--------|
| **Why expected** | Without a unified error type, callers must handle per-provider error shapes. FoundationModels defines `LanguageModelError` with cases: `contextSizeExceeded`, `rateLimited`, `refusal`, `guardrailViolation`, `unsupportedCapability`, `timeout`. |
| **Complexity** | Low |
| **FoundationModels shape** | `enum LanguageModelError` with standard cases covering all model failure modes |
| **Notes** | Replaces current fragmented error handling (per-provider error enums, `ToolResult.isError:true`, raw `Error` propagation). All model-level errors funnel through `LanguageModelError`. Tool execution errors remain separate (`ToolOutput` with error flag). |

### TS-10: Retry / fallback

| Attribute | Detail |
|--------|--------|
| **Why expected** | LLM APIs fail. Network errors, rate limits, 5xx responses. Every runtime has retry with backoff and model fallback chains. Claude Code June 2026 added `fallbackModel` chains with per-model `maxTokens`, `costCeiling`, `timeoutSeconds`. |
| **Complexity** | Medium |
| **Current state** | `RetryPolicy.swift` with exponential backoff and jitter. Fallback model support exists but is basic. |
| **Notes** | Retry policy should be part of `LanguageModelCapabilities` / executor configuration, not a separate system. FoundationModels executors handle retry internally; the session sees only success or `LanguageModelError`. |

### TS-11: MCP (Model Context Protocol) support

| Attribute | Detail |
|--------|--------|
| **Why expected** | MCP is the universal extensibility layer for agent tools ("USB-C for AI agents"). Claude Code has deepest MCP integration. FoundationModels doesn't mandate MCP but fully interoperates with it. Every serious coding agent runtime supports MCP. |
| **Complexity** | High |
| **Current state** | `MCPClient` (actor), `MCPTransport` (7 variants), `MCPToolBridge`, OAuth flow. Must be preserved. |
| **Notes** | MCP tools appear as regular `Tool` implementations. The MCP transport layer is internal to tool registration -- the session and model never need to know a tool came from MCP. |

---

## 2. Differentiators (Competitive Advantage)

These features set a runtime apart from basic SDK wrappers. They are not universally provided, and doing them well creates meaningful differentiation.

### DIFF-1: Dynamic Profiles (agent identity switching)

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels `DynamicProfile` enables mid-session model/tool/instruction switching without losing transcript context. One session, multiple agent personalities. Claude Code achieves similar behavior through sub-agents with isolated conversations. |
| **Complexity** | Medium |
| **FoundationModels shape** | `protocol DynamicProfile { associatedtype Body: DynamicInstructions; var body: Self.Body { get } }` with `Profile` builder that takes model, instructions, tools, and modifiers |
| **Notes** | This is a FoundationModels-native differentiator. Claude Code does not have an equivalent first-class concept -- profiles emerge from sub-agent configuration. Building this into the API layer is forward-looking. |
| **When to build** | After core `LanguageModelSession` is stable. Profiles compose on top of sessions. |

### DIFF-2: Snapshot streaming over token deltas

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels uses `AsyncSequence<PartiallyGenerated<T>>` -- each element is a complete snapshot of the current state. Claude Code uses `text_delta` / `input_json_delta` token deltas. Snapshot streaming is provider-agnostic (no per-provider token format leaking) and easier for UI binding. |
| **Complexity** | Medium |
| **Notes** | This is the single highest-impact differentiator in the API surface. It isolates all provider-specific wire formats behind the executor boundary. Consumers see only structured progress snapshots. |

### DIFF-3: Type-driven structured output (compile-time schema)

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels `@Generable` macro derives JSON schema from Swift types at compile time. Current approach requires manual `JSONSchema` construction. Type-driven output eliminates an entire class of bugs (schema/type mismatch) and tedious boilerplate. |
| **Complexity** | High (requires Swift macro) |
| **Notes** | Initial implementation can use runtime schema derivation (mirror-based or `Codable`-based) as a stepping stone to the `@Generable` macro. The protocol shape (`Generable`, `GenerationSchema`, `PartiallyGenerated`) should be designed now even if the macro comes later. |

### DIFF-4: Model capabilities as a struct (not dual ModelInfo types)

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels `LanguageModelCapabilities` is a single struct describing what a model supports: tool calling, guided generation, reasoning levels, context window size, vision, etc. Current codebase has fragmented capability information across `ModelInfo` types. |
| **Complexity** | Low |
| **FoundationModels shape** | `struct LanguageModelCapabilities { /* supportsToolCalling, supportsVision, contextWindowSize, etc. */ }` |
| **Notes** | This is a clean-up that reduces the current dual `ModelInfo` types to a single capabilities struct. Low complexity, high clarity payoff. |

### DIFF-5: Wire-format isolation (executor-internal details)

| Attribute | Detail |
|--------|--------|
| **Value proposition** | In the current codebase, Anthropic-specific types (`ContentBlock`, `StreamEvent`, `ThinkingBlock`) leak through the public API. FoundationModels isolates all wire-format concerns behind `LanguageModelExecutor`. Consumers never see Anthropic SSE events or OpenAI chat completion chunks. |
| **Complexity** | Medium |
| **Notes** | This is the architectural principle behind the reorganization. Every executor translates its provider's wire format into the session's canonical transcript representation. The `StreamEvent` enum and `ContentBlock` struct become internal to the Anthropic executor. |

### DIFF-6: Transcript as canonical history (not API messages)

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels `Transcript` is a structured, typed history with entries like `.instructions`, `.prompt`, `.toolCalls`, `.toolOutput`, `.response`. Claude Code stores `Message[]` in Anthropic API format. The transcript is a higher-level representation that survives model swapping. |
| **Complexity** | Medium |
| **Notes** | The transcript is the session's internal history format. Each executor translates transcript entries into its provider's API message format and translates API responses back into transcript entries. This translation layer is where the operational work happens. |

### DIFF-7: Tool execution harness separation

| Attribute | Detail |
|--------|--------|
| **Value proposition** | FoundationModels `Tool` protocol is ~4 members. The current 30+ member `Tool` protocol conflates the tool-model contract with the tool-runtime contract. Separating these: the protocol defines what the model sees; the registry/metadata defines how the runtime executes (concurrency safety, permission classification, interrupt behavior, etc.). |
| **Complexity** | Medium |
| **Notes** | This is the key refactoring of the tool system. The protocol becomes the FoundationModels shape. Per-tool operational metadata moves to a `ToolMetadata` struct or `ToolRegistry` configuration. Existing tools keep their behavior; only the declaration site changes. |

---

## 3. Anti-Features (Things to Deliberately NOT Build Into the API Layer)

These are features that seem natural but create long-term problems. They are explicitly excluded from the API surface.

### ANTI-1: Multi-agent orchestration in the API layer

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| Agent graphs, supervisor/worker patterns, agent-to-agent handoffs baked into `LanguageModelSession` | Cognition (Devin creators) explicitly warns: "Don't build multi-agents." Context fragmentation, coordination failures, conflicting decisions. LangGraph's graph orchestration is a different architectural problem. FoundationModels `DynamicProfile` handles agent identity switching without multi-agent complexity. | Sub-agents (Claude Code's `AgentTool` / `SubAgentManager`) are a separate concern. Keep them as a tool, not a session primitive. A `DynamicProfile` can change what a session *is* but shouldn't orchestrate multiple concurrent sessions. |

### ANTI-2: Provider-specific types in the public API

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| `ContentBlock`, `StreamEvent`, `ThinkingBlock`, `ToolUseBlock` as public types | These are Anthropic wire-format types. Exposing them forces every consumer to understand Anthropic's API. Adding OpenAI means adding OpenAI types. The public API becomes a union of all provider formats. | Transcript entries are the public history format. Each executor translates provider-specific types into transcript entries internally. The `StreamEvent` enum becomes internal to the Anthropic executor. |

### ANTI-3: State machines for the agent loop

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| Formal state machine (nodes, edges, transitions) for the agent execution loop | Claude Code's architecture study explicitly notes: the agentic loop is fundamentally sequential (model speaks -> tools execute -> model speaks again). A state machine adds "formality without adding clarity." The model decides transitions at runtime. | The `while(true)` loop pattern: stream response, check for tool calls, execute tools, append results, repeat. This is the ReAct pattern and it's proven across Claude Code, Codex, and FoundationModels. |

### ANTI-4: Hard iteration limits on the agent loop

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| `MAX_TOOL_ITERATIONS` or any hard cap on tool-execution rounds | Claude Code explicitly removed this. The model decides when to stop via `end_turn`. Hard limits create arbitrary failure modes where the model would have succeeded on the next iteration. | Circuit breakers at the platform level (cost ceiling, time budget, user ESC). Not iteration counting. The `LanguageModelSession` should have a `ContextOptions` budget, not a loop counter. |

### ANTI-5: One tool with an `action` parameter

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| A single "FileOperation" tool with `action: "read" | "write" | "delete"` | The model must correctly set the action field AND provide action-specific parameters. Schema validation gets complex. Error messages become ambiguous ("invalid input" -- which action?). Claude Code learned this: each tool has exactly one responsibility. | One tool per operation: `FileReadTool`, `FileWriteTool`, `FileEditTool`. Each has a focused schema where invalid states are impossible by construction. |

### ANTI-6: Raw API key strings in public types

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| `String`-typed API keys in model configuration, session configuration, or error messages | API keys in plain strings leak into logs, error messages, debug output, and stack traces. The current codebase already has masking only in `DebugLogger` -- not universally. | A `RedactableString` or `Secret` wrapper type where `description`/`debugDescription` always masks. The `LanguageModel` protocol should accept a redacted credential type, not `String`. |

### ANTI-7: Framework lock-in through session type

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| Making `LanguageModelSession` tied to a specific framework (FoundationModels, SwiftAgent, or any one runtime) | The whole point of the `LanguageModel` protocol is that sessions are model-agnostic. If the session type itself carries framework-specific assumptions, swapping models doesn't help. | `LanguageModelSession` should be a protocol or a generic over `LanguageModel`. The concrete implementation lives in SwiftAgent but the contract should match FoundationModels' shape, enabling future migration to Apple's native session if desired. |

### ANTI-8: Overly broad agent scope

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| A single "UniversalAgent" profile that handles everything | Agents with broad responsibilities without specific operating parameters perform poorly. Claude Code is a coding agent -- it doesn't try to be a travel agent or a customer service bot. | `DynamicProfile` with explicit boundaries. Each profile has specific instructions, tools, and model configurations. The `CodingProfile` handles code. Future profiles handle their domains. |

### ANTI-9: Prompt templates in the API layer

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| System prompt templating, variable substitution, or prompt engineering as API surface | Prompt construction is an operational concern, not an API contract. Claude Code builds system prompts from 190+ modular `.md` files. FoundationModels uses `Instructions` builders. Neither exposes templating as API. | `SystemPromptBuilder` remains operational harness. The session's `instructions` are the result of prompt construction, not the mechanism. The API accepts "these are the instructions," not "build instructions from these templates." |

### ANTI-10: Built-in tool implementations in the API layer

| Anti-Feature | Why Avoid | What to Do Instead |
|-------------|-----------|-------------------|
| Shipping `BashTool`, `FileReadTool`, `FileWriteTool` (etc.) as part of the `LanguageModelSession` or `LanguageModel` protocol | The protocol defines the tool contract. Concrete tools are implementations. Shipping tools in the API layer conflates "what a tool looks like" with "here are the tools you get." FoundationModels ships `OCRTool` and `BarcodeReaderTool` as system tools but they implement `Tool`, not extend it. | Tools are registered into the session, not baked into it. The API layer defines `Tool` protocol + `ToolRegistry`. Actual implementations (Bash, Read, Write, etc.) live in the tools directory and conform to the protocol. |

---

## Feature Dependencies

```
LanguageModel protocol ─────────────────────────────────────────────┐
    │                                                                 │
    ├── LanguageModelCapabilities ──────────────────────────────────  │
    ├── LanguageModelError ─────────────────────────────────────────  │
    │                                                                 │
    ▼                                                                 │
LanguageModelSession ◄── LanguageModel (model backend)               │
    │                                                                 │
    ├── Transcript (history) ◄── LanguageModelExecutor (translates)   │
    ├── Tool protocol (~4 members)                                    │
    ├── DynamicProfile (future phase)                                 │
    ├── ContextOptions (reasoning level, budget)                      │
    └── Streaming (AsyncSequence<PartiallyGenerated<T>>)              │
    │                                                                 │
    ▼                                                                 │
ToolExecutor (operational harness)                                    │
    │                                                                 │
    ├── PermissionEngine (10-step pipeline)                           │
    ├── Compactor (context window management)                         │
    ├── RetryPolicy (backoff + fallback)                              │
    ├── ToolRegistry (metadata, search, concurrency safety)           │
    └── MCP bridge (external tools -> Tool protocol)                  │
```

Key dependency chain:
1. `LanguageModel` protocol and `LanguageModelSession` are co-required (session needs model)
2. `Tool` protocol simplification must happen before `DynamicProfile` (profiles compose tools)
3. Snapshot streaming requires `PartiallyGenerated<T>` which requires `@Generable`-compatible type system
4. `LanguageModelCapabilities` and `LanguageModelError` are leaf types (no internal deps)
5. Permission engine, compactor, retry are operational harness -- they wrap tool execution, don't change the API surface

---

## MVP Recommendation (Phase 1 of API Reorganization)

Prioritize in this order:

1. **`LanguageModel` protocol + `LanguageModelCapabilities`** -- The model boundary. Everything else depends on this.
2. **`LanguageModelSession`** -- The unified public API. Replaces `QueryEngine` + `LLMClient` as primary surface.
3. **`LanguageModelExecutor` protocol** -- Backend implementation contract. Anthropic executor is the first concrete implementation.
4. **Simplified `Tool` protocol (~4 members)** -- The model-tool contract. Existing tools adapt to new shape.
5. **`LanguageModelError` enum** -- Unified error type. Replaces fragmented per-provider errors.

**Defer to later phases:**
- `DynamicProfile` -- Composes on top of stable `LanguageModelSession`. Phase 2+.
- `@Generable` macro -- Requires Swift macro infrastructure. Use runtime schema derivation initially.
- Vision/multimodal support -- Explicitly out of scope for this reorganization.
- Multi-agent orchestration -- Explicitly out of scope (anti-feature in API layer).

---

## Sources

**FoundationModels API (HIGH confidence -- Apple WWDC sessions):**
- [WWDC 2026 Session 339: Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/) -- `LanguageModel` protocol, `LanguageModelExecutor`, provider implementation guide
- [WWDC 2026 Session 241: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/) -- `DynamicProfile`, built-in tools, streaming, RAG
- [WWDC 2025 Session 301: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/) -- Original `Tool` protocol, `@Generable`, structured output
- [Foundation Models Developer Documentation](https://developer.apple.com/documentation/FoundationModels) -- `LanguageModelError`, `LanguageModelCapabilities`, `Generable` protocol

**Claude Code architecture (MEDIUM-HIGH confidence -- source analysis + verified docs):**
- [Claude Code Agent Harness: Architecture Breakdown](https://wavespeed.ai/blog/posts/claude-code-agent-harness-architecture/) -- Tool system 3-layer architecture, execution lifecycle
- [I Read Claude Code's 510K Lines of Source Code](https://dev.to/neuzhou/i-read-claude-codes-510k-lines-of-source-code-heres-how-it-actually-works-3kco) -- Streaming executor, context compaction, single-loop architecture
- [Claude Code Docs: Stream responses in real-time](https://code.claude.com/docs/en/agent-sdk/streaming-output) -- Token delta streaming, content block events
- [Claude Code June 2026 Features](https://www.sitepoint.com/claude-code-june-2026-10-new-features-devs-need-to-know/) -- Fallback chains, nested sub-agents, agent checkpointing

**Anti-patterns & design wisdom (MEDIUM confidence -- practitioner blogs, verified by multiple independent sources):**
- [Cognition: Don't Build Multi-Agents](https://cognition.ai/blog/dont-build-multi-agents) -- Why single-threaded agents with full context sharing beat multi-agent architectures
- [Google: Production-Ready AI Agents -- 5 Lessons](https://developers.googleblog.com/en/production-ready-ai-agents-5-lessons-from-refactoring-a-monolith/) -- Observable, auditable, simple
- [Common Sub-Agent Anti-Patterns](https://stevekinney.com/courses/ai-development/subagent-anti-patterns) -- Context fragmentation, coordination failures
- [Context Window is RAM, Not Storage](https://mem0.ai/blog/context-window-is-ram-not-storage-why-most-agent-failures-happen-how-to-fix-them-in-2026) -- Working memory vs persistent memory separation

**Codebase analysis (HIGH confidence -- directly verified):**
- SwiftAgent `Tool.swift` (1156 lines, 30+ members) -- Current oversized protocol
- SwiftAgent `docs/ARCHITECTURE.md` -- Current module boundaries, data flow
- SwiftAgent `.planning/PROJECT.md` -- Target architecture, 12 active requirements
- SwiftAgent `AboutAppleFoundationModels.md` -- FoundationModels feature map and architecture guidance
