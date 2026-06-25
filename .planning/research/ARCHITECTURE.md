# Architecture Patterns: Agent Runtime API

**Domain:** AI coding agent runtimes on Apple platforms
**Researched:** 2026-06-25
**Confidence:** HIGH

## Recommended Architecture

The Agent Runtime reorganizes SwiftAgent from an Anthropic-specific architecture into a provider-agnostic Agent Runtime modeled on Apple's FoundationModels framework (WWDC25/26 `LanguageModelSession` API). The core principle: **models become plugins, not the architecture**.

```
                          ┌──────────────────────────────────────────┐
                          │          CLI / App Entry Points          │
                          │   (ChatCommand, ThreadViewModel, etc.)   │
                          └────────────────────┬─────────────────────┘
                                               │
                                               ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                    LanguageModelSession  (UNIFIED PUBLIC API)                 │
│                                                                              │
│  var model: any LanguageModel                                                │
│  var transcript: Transcript                                                  │
│  var tools: [any Tool]                                                       │
│  var instructions: String                                                    │
│                                                                              │
│  func respond(to: String) async throws -> ResponseContent                    │
│  func streamResponse(to: String) -> AsyncThrowingStream<Snapshot, Error>     │
│  func respond<Output: Generable>(to: String, generating: Output.Type) async  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │  Internal Agent Loop (private)                                        │    │
│  │                                                                       │    │
│  │  1. Append .prompt to transcript                                      │    │
│  │  2. Ask model executor to respond (with transcript + tools)           │    │
│  │  3. If tool calls: execute tools, append .toolOutput to transcript    │    │
│  │  4. Loop back to step 2 until model emits end_turn                    │    │
│  │  5. Append .response to transcript, return content                    │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                 LanguageModel protocol  (MODEL ABSTRACTION)                   │
│                                                                              │
│  protocol LanguageModel: Sendable {                                           │
│      var capabilities: LanguageModelCapabilities { get }                      │
│      func makeExecutor() -> any LanguageModelExecutor                        │
│  }                                                                           │
│                                                                              │
│  protocol LanguageModelExecutor: Sendable {        ← INTERNAL TO CORE        │
│      func respond(                                                            │
│          to transcript: Transcript,                                           │
│          tools: [any Tool],                                                   │
│          options: GenerationOptions,                                          │
│          streamingInto channel: GenerationChannel                            │
│      ) async throws                                                          │
│  }                                                                           │
└────────────────────────────────────┬─────────────────────────────────────────┘
                                     │
         ┌───────────────────────────┼───────────────────────────┐
         ▼                           ▼                           ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ AnthropicExecutor│     │ DeepSeekExecutor│     │ OpenAIExecutor  │
│ (Claude models) │     │ (DeepSeek API)  │     │ (GPT/O-series)  │
│                 │     │                 │     │                 │
│ Internal types: │     │ Internal types: │     │ Internal types: │
│ - SSE parsing   │     │ - Chat API reqs │     │ - Chat API reqs │
│ - Content blocks│     │ - Stream chunks │     │ - Response parse│
│ - Tool use JSON │     │ - Reasoner mode │     │ - Function call │
│ - Cache headers │     │ - Token mapping │     │ - Token mapping │
│ - Beta features │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Component Boundaries

### Layer 1: Core Public API (`Sources/SwiftAgentCore/AgentRuntime/`)

These types form the public surface that CLI and App targets depend on. They contain **zero** provider-specific knowledge.

| Component | Responsibility | Key Types |
|-----------|---------------|-----------|
| `LanguageModelSession` | Stateful agent loop: transcript management, tool execution orchestration, streaming dispatch. Replaces `QueryEngine` + `LLMClient` as the primary API surface. | `respond(to:)`, `streamResponse(to:)`, `transcript`, `tools`, `instructions`, `isResponding` |
| `LanguageModel` protocol | Declares model capabilities and provides executor factory. Matches Apple's `LanguageModel` protocol. | `capabilities`, `makeExecutor()` |
| `LanguageModelCapabilities` | Single struct describing what a model supports. Replaces dual `ModelInfo` types (App's `ModelInfo` + Core's `ModelRegistry`). | `supportsThinking`, `supportsVision`, `contextWindow`, `maxOutputTokens`, `supportsToolUse`, `supportsStreaming` |
| `Tool` protocol | Simplified tool contract (~4 members). Matches FoundationModels `Tool` protocol shape. | `name`, `description`, `Arguments` (Generable), `call(arguments:) -> ToolOutput` |
| `Transcript` | Linear conversation history. Provider-agnostic sequence of entries. Replaces `Conversation` + `Message` + `ContentBlock`. | `.instructions`, `.prompt`, `.toolCalls`, `.toolOutput`, `.response` |
| `GenerationOptions` | Request parameters. | `temperature`, `maxTokens`, `reasoningLevel`, `sampling` |
| `LanguageModelUsage` | Token usage stats. Provider-agnostic. Replaces Anthropic-specific `Usage` struct. | `inputTokens`, `outputTokens`, `cachedTokens` |
| `LanguageModelError` | Unified error taxonomy. Replaces fragmented error types across providers. | `contextSizeExceeded`, `rateLimited`, `refusal`, `guardrailViolation`, `unsupportedCapability`, `providerError` |
| `GenerationChannel` | Streaming channel protocol. Executor emits events; session relays to consumer. Replaces `StreamEvent` enum. | `appendText(_:)`, `updateUsage(_:)`, `toolCalls(_:)`, `updateMetadata(_:)` |

### Layer 2: Core Internal Bridge (`Sources/SwiftAgentCore/AgentRuntime/Executors/`)

The `LanguageModelExecutor` protocol is _internal to Core_ -- not exposed to CLI/App. It defines the bridge that each provider executor must implement. This is the layer where transcript-to-wire mapping happens.

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `LanguageModelExecutor` protocol | Translates `Transcript` to provider-native wire format, streams responses through `GenerationChannel`. Internal to Core. | `LanguageModelSession` (caller), Provider executors (implementations) |
| `ToolDefinitionGenerator` | Converts `[any Tool]` to provider-native tool definitions using `@Generable` reflection. Each executor calls this to build its API-specific tool schema. | `Tool` protocol, Provider executors |

### Layer 3: Per-Provider Executors (`Sources/SwiftAgentCore/AgentRuntime/Executors/Anthropic/`, etc.)

Each executor is a self-contained module that implements `LanguageModelExecutor`. All provider-specific types live here.

| Executor | Provider | Internal Types (examples) |
|----------|----------|--------------------------|
| `AnthropicExecutor` | Anthropic Messages API | `AnthropicSSEParser`, `AnthropicContentBlock`, `AnthropicToolUseBlock`, `AnthropicCacheHeader`, `AnthropicBetaFeature` |
| `DeepSeekExecutor` | DeepSeek Chat Completions API | `DeepSeekChatRequest`, `DeepSeekStreamChunk`, `DeepSeekReasonerDetector` |
| `OpenAIExecutor` | OpenAI Chat Completions API | `OpenAIChatRequest`, `OpenAIStreamChunk`, `OpenAIFunctionCall` |

**What each executor owns internally:**
- API client / URLSession management
- Authentication / API key handling
- Wire format request serialization (JSON body construction)
- Wire format response parsing (SSE, JSON, streaming chunk parsing)
- Tool definition mapping (Transcript tools -> provider-specific function calling format)
- Token counting and usage tracking
- Retry logic with exponential backoff
- Beta/experimental feature gating (e.g., Anthropic cache control, OpenAI structured outputs)
- Thinking/reasoning extraction from provider-specific fields

**What each executor does NOT own (provided by Core):**
- Transcript management (receives `Transcript`, does not store it)
- Tool execution (reports tool calls to session; session executes and feeds back)
- Agent loop control (session decides when to stop/re-prompt)
- Session lifecycle (prewarm, cancel are called by session)
- Permission checks (tool execution is session's responsibility)

### Layer 4: Entry Point Adapters (CLI/App)

Thin adapters that bridge `LanguageModelSession` into each entry point's existing architecture.

| Adapter | Purpose |
|---------|---------|
| CLI: `ChatCommand` adapter | Wires `LanguageModelSession` into ChatCommand's event loop, replacing `QueryEngine.run()` + inline streaming |
| App: `ThreadViewModel` adapter | Wires `LanguageModelSession` into ThreadViewModel, replacing `AgentSessionManager` + `AppAgentProvider` |

## Data Flow

### Primary Request Flow (after reorganization)

```
1. User submits prompt
   CLI: LineEditor → ChatCommand
   App: ComposerView → ThreadViewModel

2. LanguageModelSession.respond(to: prompt)
   - Session appends .prompt(prompt) to internal transcript
   - Session calls model.makeExecutor() to get executor
   - Session calls executor.respond(transcript, tools, options, channel)

3. Executor translates Transcript → native wire format
   AnthropicExecutor: Transcript → [anthropic ContentBlock[]] → POST /v1/messages
   DeepSeekExecutor: Transcript → [openai-compat messages[]] → POST /v1/chat/completions
   OpenAIExecutor:   Transcript → [openai messages[]] → POST /v1/chat/completions

4. Executor streams responses through GenerationChannel:
   → channel.updateUsage(input:, output:)     // token counts
   → channel.updateMetadata(modelID:, id:)    // model info
   → channel.appendText("token text")         // text deltas
   → channel.toolCalls([ToolCall(...)])       // completed tool calls
   → channel.appendThinking("reasoning")      // thinking/reasoning text

5. LanguageModelSession receives channel events:
   IF tool calls:
     - Session executes tools via ToolExecutor (existing, but with simplified Tool protocol)
     - Session appends .toolOutput to transcript
     - Session re-calls executor.respond() with updated transcript
     - LOOP to step 3
   IF text response:
     - Session appends .response to transcript
     - Session returns ResponseContent to caller

6. Caller consumes result
   CLI: StreamRenderer formats for terminal
   App: ChatBridge updates NSTableView
```

### Streaming Snapshot Model

Instead of raw token deltas (`StreamEvent.textDelta`), the session emits snapshots:

```swift
// OLD: Consumer receives raw Anthropic events
onEvent: (@Sendable (StreamEvent) -> Void)?

// NEW: Consumer receives typed snapshots
for try await snapshot in session.streamResponse(to: prompt) {
    switch snapshot {
    case .text(let partialText):      // accumulated text so far
    case .thinking(let partial):      // accumulated thinking so far
    case .toolCall(let call):         // completed tool call
    case .usage(let usage):           // updated token counts
    case .metadata(let info):         // model/request metadata
    }
}
```

This hides provider wire format details entirely. The executor accumulates deltas internally and emits completed/partial results.

### Tool Execution Flow (after reorganization)

```
1. Executor reports tool calls via channel.toolCalls([Transcript.ToolCall])

2. Session receives tool calls:
   FOR EACH tool call:
     a. Match tool name to registered Tool instance
     b. Validate arguments using @Generable schema (compile-time derived)
     c. Check permissions via existing PermissionEngine
     d. Execute tool.call(arguments:) -> ToolOutput
     e. Append .toolOutput(result) to transcript

3. Session re-prompts executor with updated transcript
   → Model processes tool output
   → Model may issue more tool calls (loop) or respond with text (stop)
```

## Patterns to Follow

### Pattern 1: Transcript as Universal Wire Format

**What:** Every provider executor accepts a `Transcript` and translates it to its native format internally. The `Transcript` is the single source of truth for conversation state.

**Why:** This isolates all wire-format concerns inside each executor. Adding a new provider means only implementing `Transcript → NativeRequest` translation -- no changes to the session or public API.

**When:** Every provider integration.

**Example -- Anthropic translation:**
```swift
// Inside AnthropicExecutor (INTERNAL)
func translateTranscriptToMessages(_ transcript: Transcript) -> [[String: Any]] {
    var messages: [[String: Any]] = []
    var currentRole: String? = nil
    var currentBlocks: [[String: Any]] = []

    for entry in transcript {
        switch entry {
        case .instructions(let text):
            // System prompt -- handled separately, not in messages array
            break
        case .prompt(let text, let attachments):
            flushCurrentBlocks(&currentBlocks, role: &currentRole, into: &messages)
            currentRole = "user"
            currentBlocks.append(["type": "text", "text": text])
        case .response(let text, let thinking):
            flushCurrentBlocks(&currentBlocks, role: &currentRole, into: &messages)
            currentRole = "assistant"
            if let thinking { currentBlocks.append(["type": "thinking", "thinking": thinking]) }
            currentBlocks.append(["type": "text", "text": text])
        case .toolCalls(let calls):
            flushCurrentBlocks(&currentBlocks, role: &currentRole, into: &messages)
            currentRole = "assistant"
            for call in calls {
                currentBlocks.append([
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": call.arguments  // JSON-encoded
                ])
            }
        case .toolOutput(let callID, let output):
            flushCurrentBlocks(&currentBlocks, role: &currentRole, into: &messages)
            currentRole = "user"
            currentBlocks.append([
                "type": "tool_result",
                "tool_use_id": callID,
                "content": output
            ])
        }
    }
    flushCurrentBlocks(&currentBlocks, role: &currentRole, into: &messages)
    return messages
}
```

### Pattern 2: Tool Protocol Simplified to FoundationModels Shape

**What:** Reduce the current 30-member `Tool` protocol to ~4 required members, matching FoundationModels.

```swift
public protocol Tool: Sendable {
    /// PascalCase tool name as seen by the LLM (e.g., "Bash", "Read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    var description: String { get }

    /// The tool's input schema, derived from the Arguments type at compile time.
    associatedtype Arguments: Generable

    /// Execute the tool with validated arguments.
    func call(arguments: Arguments) async throws -> ToolOutput
}
```

**What's removed from Tool protocol and where it goes:**
| Old Member | Where It Moves |
|-----------|----------------|
| `isReadOnly`, `isDestructive()` | `LanguageModelCapabilities.toolCategories` or executor-specific annotation |
| `isConcurrencySafe`, `interruptBehavior()` | `ToolExecutionPolicy` (separate registry, keyed by tool name) |
| `isMcp`, `isLsp`, `mcpInfo` | Tool metadata registry (keyed by name) |
| `searchHint`, `shouldDefer`, `alwaysLoad` | Tool metadata registry |
| `checkPermissions()` | `PermissionEngine` (existing, unchanged) |
| `validateInput()` | Handled by `@Generable` schema validation (compile-time) |
| `prompt()` (system prompt text) | `Tool.systemPromptDescription` (simple String, no complex closure) |
| `maxResultSizeChars` | `ToolExecutionPolicy` |
| `userFacingName()`, `toAutoClassifierInput()` | Tool metadata registry |
| `backfillObservableInput()`, `preparePermissionMatcher()`, `inputsEquivalent()` | Permission layer (separate concern) |
| `mapToolResultToToolResultBlockParam()` | Executor's transcript translation (provider-specific) |

**Why this matters:** The 30-member protocol couples tools to every subsystem. By reducing to 4 members, tools become simple closures with types. Cross-cutting concerns (permissions, metadata, execution policy) move to dedicated registries.

### Pattern 3: Executor Isolation via Internal Protocol

**What:** `LanguageModelExecutor` is defined in Core but marked internal, not public. Only `LanguageModel.makeExecutor()` creates them. CLI/App code never references executor types directly.

**Why:** This enforces the boundary. The public API is `LanguageModelSession`. Executors are implementation details that sessions create and manage.

**How migration works:**
```
OLD: CLI/App → LLMClient (public) → Anthropic API
NEW: CLI/App → LanguageModelSession → LanguageModel.makeExecutor() → AnthropicExecutor (internal) → Anthropic API
```

The `LLMClient` class is dissolved: its auth, retry, and HTTP logic move into `AnthropicExecutor` (internal). Its streaming parser (`LLMStreamParser`) becomes `AnthropicSSEParser` (internal).

### Pattern 4: Profile Concept for Agent Identity

**What:** A `Profile` bundles instructions, tools, and model selection into a reusable configuration. Enables the session to support multiple modes (craft, analysis, brainstorm) by swapping profiles.

```swift
public struct Profile: Sendable {
    public var instructions: String
    public var tools: [any Tool]
    public var model: (any LanguageModel)?
    public var reasoningLevel: ReasoningLevel

    public init(
        instructions: String,
        tools: [any Tool] = [],
        model: (any LanguageModel)? = nil,
        reasoningLevel: ReasoningLevel = .medium
    )
}
```

**This replaces:** The current ad-hoc system prompt construction scattered across `ChatCommand`, `SystemPromptBuilder`, and `QueryEngine`.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Provider-Specific Types in Public API

**What:** Exposing `StreamEvent`, `ContentBlock`, or `Usage` in any public API.

**Why bad:** Every consumer must understand Anthropic wire format. Adding OpenAI or DeepSeek means adding parallel code paths everywhere (exactly the current problem with dual DeepSeek paths).

**Instead:** Use `Transcript`, `Snapshot`, `LanguageModelUsage`, and `GenerationChannel` -- all provider-agnostic.

**Detection:** Grep for `StreamEvent`, `ContentBlock`, `Usage` in anything outside `Sources/SwiftAgentCore/AgentRuntime/Executors/`. If found, it's a leak.

### Anti-Pattern 2: Model-Specific Executor Selection in CLI/App

**What:** `if model == "claude-sonnet-4-6" { use AnthropicClient } else { use DeepSeekClient }` in entry points.

**Why bad:** Adding a new provider requires changes in every entry point.

**Instead:** `LanguageModelSession(model: chosenModel)` -- the session delegates to the model's executor. Entry points never know which executor is running.

### Anti-Pattern 3: Dual Code Paths for Same Provider

**What:** Two separate `DeepSeekClient` instances (one in App/DeepSeek/, one via LLMProvider).

**Why bad:** Fixes in one path may not apply to the other. Configuration drifts. The current situation.

**Instead:** Single `DeepSeekExecutor` implementing `LanguageModelExecutor`. Used by both CLI and App through `LanguageModelSession`.

### Anti-Pattern 4: Inline Transcript Manipulation in Entry Points

**What:** CLI or App code directly modifying `Transcript.entries`, adding/removing entries, or converting to provider format.

**Why bad:** Breaks the executor isolation boundary. Makes transcript correctness the entry point's problem.

**Instead:** All transcript manipulation happens inside `LanguageModelSession`. Entry points only call `session.respond(to:)` or `session.streamResponse(to:)`.

## Scalability Considerations

| Concern | Current State | After Reorganization |
|---------|--------------|---------------------|
| Adding a new model provider | Requires new `LLMProvider` + new `DeepSeek-style` standalone client + wiring in two entry points | Implement `LanguageModelExecutor` in new file, register model in capabilities registry. Zero changes to entry points. |
| Changing tool behavior | Modify 30-member protocol, update all 60+ tools | Modify 4-member protocol. Most concerns moved to registries -- update registry, not every tool. |
| Streaming to new UI target | Parse `StreamEvent` enum (Anthropic-specific), translate to UI events | Consume `Snapshot` enum (provider-agnostic). Same snapshots for terminal, SwiftUI, web. |
| Context compaction | Hard-coded Anthropic content block manipulation | Compaction operates on `Transcript` entries. Provider-agnostic. Executor handles native format mapping. |
| Adding structured output | Manual `JSONSchema` with Anthropic-specific tool-use block handling | `@Generable` types with schema derived at compile time. Executor maps to provider-specific structured output API. |

## Build Order (Dependency Graph)

Suggested build sequence based on component dependencies:

```
Phase 1: Foundation Types (no dependencies)
  ├── Transcript + Transcript.Entry
  ├── LanguageModelCapabilities
  ├── LanguageModelUsage
  ├── LanguageModelError
  └── GenerationOptions

Phase 2: Core Protocols (depends on Phase 1)
  ├── Tool protocol (simplified, ~4 members)
  ├── LanguageModel protocol
  ├── LanguageModelExecutor protocol (internal)
  └── GenerationChannel protocol

Phase 3: LanguageModelSession (depends on Phase 1+2)
  ├── Session state management
  ├── Transcript manipulation
  ├── Agent loop (prompt → executor → tools → loop)
  ├── Tool execution orchestration
  └── Snapshot emission

Phase 4: AnthropicExecutor (depends on Phase 2)
  ├── Transcript → Anthropic Messages API translation
  ├── SSE stream parsing
  ├── Tool use block handling
  ├── Thinking/cache control
  └── Migrate LLMClient + LLMStreamParser internals

Phase 5: DeepSeekExecutor (depends on Phase 2)
  ├── Transcript → Chat Completions API translation
  ├── Stream chunk parsing
  ├── Reasoning content extraction
  └── Unify dual DeepSeek paths into single executor

Phase 6: OpenAIExecutor (depends on Phase 2)
  ├── Transcript → Chat Completions API translation
  ├── Function calling format mapping
  └── Structured output support

Phase 7: Tool Migration (depends on Phase 2)
  ├── Convert existing 60+ tools to new Tool protocol
  ├── Extract metadata to ToolMetadataRegistry
  ├── Extract execution policies to ToolExecutionPolicyRegistry

Phase 8: Entry Point Adapters (depends on Phase 3+4+5+7)
  ├── CLI: ChatCommand adapter (replace QueryEngine + LLMClient)
  ├── App: ThreadViewModel adapter (replace AgentSessionManager)
  └── Remove old LLMProvider, ProviderRegistry, dual ModelInfo types
```

**Phases 1-3 must be sequential** (each builds on previous). **Phases 4-7 can be parallelized** (independent executors + tool migration). **Phase 8 depends on all preceding phases.**

## Migration Strategy: Brownfield, Not Greenfield

This is a refactoring of existing code, not a rewrite. Key migration tactics:

1. **Keep existing types working during migration.** The old `Tool` protocol, `QueryEngine`, `LLMClient`, and `StreamEvent` remain operational until Phase 8. Tests continue to pass at each phase.

2. **Ship AnthropicExecutor first (Phase 4).** It's the primary provider and the most complex. Once it works, the session/loop (Phase 3) is validated. Other executors are simpler additions.

3. **Tool migration uses protocol extensions (Phase 7).** Add the new `Tool` protocol conformance via extension on existing tools. Both old and new protocols coexist during migration. Remove old protocol members in Phase 8 after all consumers switch.

4. **DeepSeek unification is a cleanup, not a feature.** Phase 5 replaces two implementations with one. No new behavior -- just deduplication.

5. **258+ tests must stay green.** Each phase includes test updates. Phase 8 includes removal of tests for deprecated types.

## Sources

- [Apple WWDC26 Session 339: Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/) -- HIGH confidence. Official Apple documentation on `LanguageModel`, `LanguageModelExecutor`, `LanguageModelSession`, `Transcript`, streaming channels, and provider architecture.
- [Apple WWDC25 Session 286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/) -- HIGH confidence. Official introduction to `LanguageModelSession`, `Tool` protocol, `@Generable`, snapshot streaming.
- [Apple WWDC25 Session 301: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/) -- HIGH confidence. Detailed `@Generable` internals, dynamic schemas, tool calling architecture.
- [Apple Developer Documentation: FoundationModels updates](https://developer.apple.com/documentation/updates/foundationmodels) -- HIGH confidence. Official API reference for `LanguageModelSession`, `Transcript`, `Tool`, `LanguageModelCapabilities`.
- [OpenFoundationModels (GitHub)](https://github.com/1amageek/OpenFoundationModels) -- MEDIUM confidence. Open-source implementation confirming the protocol shapes are implementable without Apple's internals.
- [AnyLanguageModel (GitHub)](https://github.com/mattt/AnyLanguageModel) -- MEDIUM confidence. Multi-provider implementation showing executor isolation pattern.
- [Dev.to: What's New in Apple's Foundation Models Framework at WWDC 2026](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227) -- MEDIUM confidence. Community summary confirming Dynamic Profiles and provider architecture.
- SwiftAgent codebase analysis: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`, `.planning/PROJECT.md` -- HIGH confidence. Direct codebase analysis of current 295-file, 3-target architecture.
