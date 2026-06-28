# AgentRuntime Architecture

The AgentRuntime is the central AI agent execution layer, designed after Apple's [FoundationModels](https://developer.apple.com/documentation/FoundationModels) framework. It replaces the legacy `LLMClient` + `QueryEngine` stack with a provider-agnostic, protocol-driven architecture where `LanguageModelSessionImpl` orchestrates the full agent loop.

---

## 1. Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Integration Layer                       │
│  ThreadViewModel (App)    │    ChatCommand (CLI)         │
├─────────────────────────────────────────────────────────┤
│                  Session Layer                           │
│  LanguageModelSessionImpl ─── actor, owns the loop       │
│  ├─ Transcript (conversation history)                    │
│  ├─ ResponseStream = AsyncThrowingStream<SessionEvent>   │
│  └─ 8 subsystem references                              │
├────────────────────┬──────────┬─────────────────────────┤
│    Provider Layer  │ Tools    │ Subsystems               │
│  AnthropicProvider │ 64 tools │ SQLiteMemoryStore (actor)│
│  DeepSeekProvider  │ 3 batches│ AgentPermissionBridge    │
│  OpenAIProvider    │          │ MCPBootstrapper (actor)  │
├────────────────────┴──────────┴─────────────────────────┤
│  Core Types: Transcript, SessionEvent, Usage, Response   │
│  AgentPermission (13 cases), AgentRuntimeError (19 cases)│
└─────────────────────────────────────────────────────────┘
```

**Design principles:**

- **Provider-agnostic** — App/CLI code never sees API-specific types. All communication flows through `SessionEvent` and `Transcript`.
- **Snapshot semantics** — `textDelta` and `thinkingDelta` carry accumulated totals, not incremental deltas. Consumers replace, not append.
- **Actor isolation** — `LanguageModelSessionImpl`, `StreamingGenerationChannel`, `SQLiteMemoryStore`, and `DefaultToolEngine` are all actors. Provider structs are `Sendable` value types.
- **FoundationModels alignment (2026-06-27)** — P0/P1/P2 alignment complete: `LanguageModelExecutorConfiguration`, `LanguageModelExecutorGenerationRequest`, `ContextOptions`, `GenerationOptions` (SamplingMode, ToolCallingMode), `LanguageModelCapabilities` (Capability enum, `contains(_:)`), `SessionToolDefinition.parameters`, richer `AgentRuntimeError` info structs, `Prompt`/`Instructions`/`PromptAttachment` types, `TranscriptErrorHandlingPolicy`, `Tool` protocol `Output` associated type. See §2 for details.

---

## 2. Core Protocols and Type System

### 2.1 LanguageModel + LanguageModelExecutor

```
LanguageModel (Sendable)              LanguageModelExecutor (Sendable)
├─ capabilities: LanguageModelCapabilities   ├─ model: any LanguageModel
├─ displayName: String                       ├─ prewarm(transcript:) → no-op default
├─ executorConfiguration: LanguageModel      └─ respond(to: LanguageModelExecutor
│    ExecutorConfiguration                       GenerationRequest,
└─ makeExecutor() -> any LanguageModelExecutor   streamingInto:) async throws
```

**`LanguageModel`** (`Providers/LanguageModel.swift`) is a factory protocol. It holds configuration (API key, base URL, model ID) but no runtime state. `makeExecutor()` creates per-model inference backends. `executorConfiguration` exposes the configuration (aligned with Apple's `LanguageModel.Executor.Configuration`). Uses `makeExecutor()` factory instead of `associatedtype Executor` due to existential type constraints (session stores `any LanguageModel`).

**`LanguageModelExecutor`** (`Providers/LanguageModelExecutor.swift`) is the internal protocol for performing inference. Takes a bundled `LanguageModelExecutorGenerationRequest` (aligned with Apple) instead of flat parameters:

```swift
public struct LanguageModelExecutorGenerationRequest: Sendable {
    var id: UUID
    var transcript: Transcript
    var enabledTools: [SessionToolDefinition]
    var schema: JSONSchema?
    var generationOptions: GenerationOptions
    var contextOptions: ContextOptions
    var metadata: [String: String]
}
```

`prewarm(transcript:)` allows preloading model assets (no-op default, aligned with Apple). Each provider struct conforms to **both** protocols — `makeExecutor()` returns `self`.

**`LanguageModelCapabilities`** (`Providers/LanguageModel.swift`) uses flattened bools + `Capability` enum with `contains(_:)` for Apple-aligned inspection: `supportsToolUse`, `supportsGuidedGeneration`, `supportsReasoning`, `supportsStreaming`, `supportsVision`, `contextWindow`, `maximumResponseTokens`, `providerDisplayName`.

**`GenerationOptions`** (`Providers/LanguageModelExecutor.swift`) Apple-aligned with `SamplingMode` (`.greedy`, `.temperature`), `ToolCallingMode` (`.auto`, `.required`, `.none`), `temperature`, `maximumResponseTokens`, `reasoningBudget`, `stream`.

**`ContextOptions`** (`Providers/LanguageModelExecutor.swift`) separate struct for prompting behavior: `includeSchemaInPrompt`, `reasoningLevel` (`ReasoningLevel.low/.medium/.high`). Aligned with Apple.

**`SessionToolDefinition`** (`Providers/LanguageModelExecutor.swift`) is the normalized tool shape: `name`, `description`, `parameters: JSONSchema` (aligned with Apple's `Transcript.ToolDefinition.parameters`), `deferLoading`.

### 2.2 GenerationChannel

`Providers/GenerationChannel.swift:8` — the streaming abstraction between executor and runtime. Six methods, all `async`:

| Method | Purpose |
|--------|---------|
| `send(textDelta:)` | Accumulated text snapshot |
| `send(thinkingDelta:)` | Accumulated thinking snapshot |
| `send(toolCallRequest:id:name:input:)` | Model requested tool execution |
| `send(toolCallCompleted:id:output:)` | Tool execution finished |
| `complete(stopReason:usage:)` | Turn finished normally |
| `fail(with:)` | Error during streaming |

Two concrete implementations:
- **`StreamingGenerationChannel`** (`StreamingGenerationChannel.swift:15`) — public actor, bridges to `AsyncThrowingStream` continuation. Used by the streaming `streamResponse(to:)` path.
- **`CollectingChannel`** (`LanguageModelSessionImpl.swift:8`) — private actor, records events locally. Used by the non-streaming `respond(to:)` path for post-hoc inspection.

### 2.3 LanguageModelSession

`LanguageModelSession.swift:68` — the central orchestrator protocol. Only actor types can conform:

```swift
public protocol LanguageModelSession: Actor {
    var modelProvider: any LanguageModel { get }
    var memoryStore: any SessionMemoryStore { get }
    var permissionEngine: any SessionPermissionEngine { get }
    var toolEngine: any ToolEngine { get }
    var contextManager: any SessionContextManager { get }
    var profileManager: any ProfileManager { get }
    var graphEngine: (any AgentGraph)? { get }
    var hookSystem: any SessionHookSystem { get }
    var isResponding: Bool { get }

    func respond(to prompt: String) async throws -> Response
    func streamResponse(to prompt: String) -> ResponseStream
}
```

Eight subsystem properties, two entry points. `isResponding` guards against concurrent turns (throws `.rateLimited`).

### 2.4 SessionEvent

`SessionEvent.swift:18` — the provider-agnostic streaming event enum. All communication between executor and session flows through these 6 cases:

```swift
public enum SessionEvent: Sendable {
    case textDelta(String)              // Accumulated text (not token delta)
    case thinkingDelta(String)          // Accumulated thinking (not token delta)
    case toolCallRequested(id: String, name: String, input: Data)
    case toolCallCompleted(id: String, output: ToolOutputValue, isError: Bool)
    case turnCompleted(usage: Usage?, stopReason: String?)
    case error(AgentRuntimeError)
}
```

Key design: `textDelta` and `thinkingDelta` carry **replacement** values (full snapshot), not incremental deltas. This prevents the double-render bug where consumers concatenate partial strings.

### 2.5 Transcript

`Transcript.swift:5` — Codable conversation history with 7 typed entry kinds:

```swift
public enum Entry: Sendable, Codable {
    case instruction(String)                          // System prompt
    case prompt(String)                               // User message
    case response(String)                             // Model text response
    case thinking(String)                             // Model reasoning
    case toolCall(id: String, name: String, input: Data)
    case toolOutput(id: String, output: String, isError: Bool)
    case system(String)                               // System notification
}
```

The transcript accumulates across turns and is persisted to memory via `memoryStore.store(key:"latest", namespace:"sessions", value: transcript)`.

### 2.6 Usage, Response, ResponseStream

- **`Usage`** (`Usage.swift:5`) — Rich token counts aligned with Claude Code's `NonNullUsage`: `inputTokens`, `outputTokens`, `cacheCreationInputTokens`, `cacheReadInputTokens`, `serverToolUse`, `cacheCreation`, `inferenceGeo`, `iterations`, `speed`, `costUSD`, `contextWindow`, `maxOutputTokens`.
- **`Response`** (`Response.swift:8`) — Result of non-streaming `respond(to:)`: `transcript`, `usage`, `stopReason`.
- **`ResponseStream`** (`Response.swift:29`) — `AsyncThrowingStream<SessionEvent, Error>`. Consumers iterate with `for try await event in stream`.

### 2.7 FoundationModels-Aligned Types (P1/P2)

New types added to match Apple's FoundationModels API surface (iOS 26+/27+):

**`Prompt`** (`Providers/Prompt.swift`) — Typed prompt abstraction replacing raw `String` in session APIs:

```swift
public protocol PromptRepresentable: Sendable {
    func resolvePrompt() -> Prompt
}
public struct Prompt: Sendable, PromptRepresentable {
    public let content: String
    public init(_ content: String)
    public init(@PromptBuilder _ builder: () -> Prompt)
}
```

`String` conforms to `PromptRepresentable` for seamless adoption. `@PromptBuilder` is a result builder for composable prompt construction. `PromptAttachment` wraps multimodal content (`.image`, `.file`, `.url`) and `ImageAttachmentContent` carries image metadata (format, detail level).

**`Instructions`** (`Providers/Instructions.swift`) — Typed system instructions:

```swift
public struct Instructions: Sendable {
    public let content: String
    public init(_ content: String)
    public init(@InstructionsBuilder _ builder: () -> Instructions)
}
```

`@InstructionsBuilder` enables composable instruction assembly from strings and `Instructions` values.

**`TranscriptErrorHandlingPolicy`** (`Providers/TranscriptErrorHandlingPolicy.swift`) — Policy for error handling during generation:

```swift
public struct TranscriptErrorHandlingPolicy: Sendable {
    public var toolErrorStrategy: ToolErrorStrategy     // .retry, .skip, .abort, .reportToModel
    public var contextOverflowStrategy: ContextOverflowStrategy  // .truncateOldest, .compress, .abort
    public var maxToolErrorRetries: Int
}
```

These types are defined and available but not yet wired into `LanguageModelSessionImpl` (session APIs still take raw `String` for backward compatibility during transition).

---

## 3. Agent Loop

### 3.1 LanguageModelSessionImpl

`LanguageModelSessionImpl.swift:55` — the concrete actor implementing `LanguageModelSession`. Created with 8 subsystem references:

```swift
public init(
    modelProvider: any LanguageModel,
    memoryStore: any SessionMemoryStore,
    permissionEngine: any SessionPermissionEngine,
    toolEngine: any ToolEngine,
    contextManager: any SessionContextManager = NoOpSessionContextManager(),
    profileManager: any ProfileManager = NoOpProfileManager(),
    graphEngine: (any AgentGraph)? = nil,
    hookSystem: any SessionHookSystem = NoOpSessionHookSystem(),
    systemPrompt: String? = nil
)
```

The system prompt (if provided) is appended as `.instruction(prompt)` to a fresh transcript.

### 3.2 Reentrancy Guard

`LanguageModelSessionImpl.swift:101` — `assertNotResponding()` checks `isResponding` before starting a turn. If a turn is in progress, throws `.rateLimited`. `isResponding` is set to `true` at turn start and `false` in a `defer` block.

### 3.3 Streaming Path

```
User sends "run ls"
    │
    ▼
streamResponse(to: "run ls")
    │
    ├─ transcript.entries.append(.prompt("run ls"))
    ├─ Create StreamingGenerationChannel + setContinuation
    ├─ executor.respond(to: transcript, tools, options, streamingInto: channel)
    │       │
    │       ├─ SSE bytes → SSE parser → channel.send(textDelta:)
    │       ├─                              channel.send(thinkingDelta:)
    │       ├─                              channel.send(toolCallRequest:)
    │       └─                              channel.complete(stopReason:usage:)
    │
    ├─ Read channel.accumulatedThinking → transcript.entries.append(.thinking)
    ├─ Read channel.accumulatedText → transcript.entries.append(.response)
    │
    ├─ recordedToolCalls?
    │   │ YES
    │   ├─ For each call:
    │   │   ├─ executeTool(name:input:) → permission check → toolEngine.execute
    │   │   ├─ transcript.entries.append(.toolCall)
    │   │   ├─ transcript.entries.append(.toolOutput)
    │   │   └─ continuation.yield(.toolCallCompleted)
    │   └─ Loop back: re-prompt executor with updated transcript
    │
    └─ NO → memoryStore.store(transcript) → continuation.finish()
```

Key ordering guarantee: **thinking → text → toolCall → toolOutput** is strictly maintained in the transcript. This is required by thinking-mode APIs (DeepSeek, Anthropic) which validate block ordering.

### 3.4 Non-Streaming Path

`LanguageModelSessionImpl.swift:160` — `respond(to:)` follows the same pattern but uses `CollectingChannel` instead. Events are collected locally and inspected after the executor finishes. Tool calls trigger re-prompt (max 50 iterations). Returns `Response(transcript, usage, stopReason)`.

### 3.5 Tool Execution

`LanguageModelSessionImpl.swift:113` — `executeTool(name:input:)`:
1. Communication tools (`SendUserMessage`, `TaskOutput`) bypass permission checks.
2. All other tools: map name to `AgentPermission` via `permissionForTool(_:)`, call `permissionEngine.check(permission)`, then `toolEngine.execute(name:input:)`.
3. On failure: append `.toolOutput(id:output:isError:true)` to transcript — the model can respond to the error.

### 3.6 Channel Comparison

| | CollectingChannel | StreamingGenerationChannel |
|---|---|---|
| Visibility | private actor | public actor |
| Storage | `events: [SessionEvent]` array | `AsyncThrowingStream` continuation |
| Tool tracking | events array includes toolCallRequested | `recordedToolCalls` array |
| Usage | `respond(to:)` non-streaming | `streamResponse(to:)` streaming |
| Post-complete guard | `isFinished` flag | `isFinished` flag |

---

## 4. Provider System

### 4.1 Shared Architecture

All three providers follow the same pattern:

```
┌──────────────────────────────────────────┐
│  Provider Struct (LanguageModel +        │
│  LanguageModelExecutor + Sendable)       │
│                                          │
│  respond(to:tools:options:streamingInto:)│
│    ├─ Transcript Translator → wire dict  │
│    ├─ Tool Translator → wire dict        │
│    ├─ URLRequest assembly                │
│    ├─ URLSession.bytes(for:) → SSE lines │
│    └─ SSE Parser → GenerationChannel     │
└──────────────────────────────────────────┘
```

### 4.2 AnthropicProvider

`Providers/Anthropic/AnthropicProvider.swift:8` — targets `/v1/messages`.

- **Transcript translation**: `AnthropicTranscriptTranslator` — maps Transcript entries to `{role, content: [{type, text/tool_use/tool_result/thinking}]}` arrays with role-flushing.
- **Tool translation**: `AnthropicToolTranslator` — maps `SessionToolDefinition` to `{name, description, input_schema}`.
- **SSE parsing**: `AnthropicSSEParser` — handles `content_block_start/delta/stop`, `message_delta`, `message_stop`, `error`.
- **Content accumulation**: `AnthropicContentAccumulator` — per-index `input_json_delta` concatenation with `safeParseJSON` (handles double-stringified JSON).
- **Model capabilities**: Sonnet 4.6, Opus 4.7, Haiku 4.5 with context windows 200K and max output 32K/32K/8K.

### 4.3 DeepSeekProvider

`Providers/DeepSeek/DeepSeekProvider.swift:15` — dual API compatibility via `APICompatibility` enum:

| Mode | Endpoint | Transcript Translator | SSE Parser |
|------|----------|----------------------|------------|
| `.anthropicCompatible` | `/anthropic/v1/messages` | `translateAnthropicCompat()` | `DeepSeekSSEParser` (→`AnthropicSSEParser`) |
| `.openAICompatible` | `/v1/chat/completions` | `translateChatCompletions()` | `ChatCompletionsSSEParser` |

Both translators delegate to canonical implementations with DeepSeek-specific post-processing:
- `translateAnthropicCompat` → `AnthropicTranscriptTranslator.translate` then strips `cache_control` keys and empty `signature` from thinking blocks.
- `translateChatCompletions` → `OpenAITranscriptTranslator.translateChatCompletions`.
- `DeepSeekToolTranslator` follows the same delegation pattern to `AnthropicToolTranslator` and `OpenAIToolTranslator`.

Key differences from Anthropic:
- Strips `anthropic-beta` header and `cache_control` markers (DeepSeek rejects them).
- Thinking blocks preserved as `{"type": "thinking", "thinking": text}` in Anthropic mode, `reasoning_content` in Chat Completions mode (required by DeepSeek for re-prompt validation).
- `translateResponses` kept for future use when DeepSeek adds Responses API support.
- Models: `deepseek-v4-pro` (128K ctx, 32K output), `deepseek-v4-flash` (128K ctx, 8K output), `deepseek-chat`, `deepseek-reasoner`.

### 4.4 OpenAIProvider

`Providers/OpenAI/OpenAIProvider.swift:8` — targets `/v1/responses` (OpenAI Responses API, 2025+).

- **Transcript translation**: `OpenAITranscriptTranslator.translateResponses` — Responses API typed items (message, reasoning, function_call, tool_call_output).
- **Tool translation**: `OpenAIToolTranslator.translateResponses` — `{"type": "function", "function": {name, description, parameters}}`.
- **SSE parsing**: `ResponsesSSEParser` — event-based SSE (`response.output_text.delta`, `response.function_call_arguments.delta`, `response.completed`).
- **o4 reasoning**: Maps `reasoningBudget` to `reasoning_effort` ("low"/"medium"/"high"), omits temperature for reasoning models.
- **Chat Completions support**: Both `OpenAITranscriptTranslator` and `OpenAIToolTranslator` also expose `translateChatCompletions` for providers using the legacy format (e.g. DeepSeek `openAICompatible`).

---

## 5. Streaming Infrastructure

### 5.1 StreamingGenerationChannel

`StreamingGenerationChannel.swift:15` — the public actor bridging executor output to consumer. Key design:

- **Snapshot semantics**: `send(textDelta:)` and `send(thinkingDelta:)` use REPLACEMENT — each call overwrites `accumulatedText`/`accumulatedThinking` and yields the full value. The executor provides accumulated totals, not incremental deltas.
- **Post-complete guard**: After `complete()` or `fail()`, `isFinished = true` — all subsequent sends silently drop. Prevents dangling events after turn completion.
- **Tool tracking**: `recordedToolCalls: [(id, name, input)]` — the agent loop inspects this after the executor finishes to decide whether to execute tools or finish.
- **Continuation lifecycle**: `setContinuation()` stores the stream continuation. `fail(with:)` calls `continuation.finish(throwing:)`; normal completion calls `continuation.finish()` from the agent loop.

Thread safety: `recordedToolCalls` and `accumulatedText`/`accumulatedThinking` are `public private(set)` — write-protected behind the actor, read-accessible with `await`.

### 5.2 SSE Parsers

Each provider has its own SSE parser, but all share the same output interface (they write to `GenerationChannel`):

- **`AnthropicSSEParser`** — Parses Anthropic SSE events: `content_block_start` (registers tool call), `content_block_delta` (text/thinking/input_json), `content_block_stop` (finalizes tool call), `message_delta` (usage/stop_reason), `error`.
- **`DeepSeekSSEParser`** — Anthropic-compat only; delegates entirely to `AnthropicSSEParser`. The Chat Completions path uses `ChatCompletionsSSEParser` directly.
- **`ResponsesSSEParser`** — Parses OpenAI Responses API event-based SSE: `response.output_text.delta`, `response.reasoning.delta`, `response.function_call_arguments.delta`, `response.output_item.done`, `response.completed`.
- **`ChatCompletionsSSEParser`** — Parses Chat Completions SSE: `choices[0].delta.content` → text, `choices[0].delta.reasoning_content` → thinking, `choices[0].delta.tool_calls` → tool call, `choices[0].finish_reason` → complete. Used by DeepSeek `openAICompatible` mode.

### 5.3 Transcript Translators

Pure functions converting `Transcript` → provider-specific wire format:

| Translator | Input | Output | Format |
|------------|-------|--------|--------|
| `AnthropicTranscriptTranslator.translate` | Transcript | `(messages, system)` | Anthropic Messages API |
| `DeepSeekTranscriptTranslator.translateAnthropicCompat` | Transcript | `(messages, system)` | Anthropic Messages (delegates + strips cache_control) |
| `DeepSeekTranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions (delegates to `OpenAITranscriptTranslator`) |
| `DeepSeekTranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API (delegates to `OpenAITranscriptTranslator`) |
| `OpenAITranscriptTranslator.translateChatCompletions` | Transcript | `[[String: Any]]` | Chat Completions messages[] with role-flushing |
| `OpenAITranscriptTranslator.translateResponses` | Transcript | `[[String: Any]]` | Responses API typed input items |

All translators include role-flushing logic: consecutive same-role entries are merged into one message; role changes (user↔assistant) or tool boundaries trigger a flush. DeepSeek translators delegate to canonical Anthropic/OpenAI translators with format-specific post-processing.

---

## 6. Tool System

### 6.1 Tool Protocol (Apple-aligned)

`Tools/RuntimeAgentTool.swift` — the `Tool` protocol with dual associated types aligned with Apple's FoundationModels:

```swift
public protocol Tool<Arguments, Output>: Sendable {
    associatedtype Arguments: Codable & Sendable
    associatedtype Output: PromptRepresentable
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    func call(arguments: Arguments) async throws -> Output
    func _callFromData(_ input: Data) async throws -> ToolOutputValue
}
```

Key changes from pre-alignment:
- **`Output` associated type** — tools can return typed outputs conforming to `PromptRepresentable`. Default is `ToolOutputValue`.
- **`call(arguments:)` returns `Output`** — aligned with Apple's `func call(arguments:) async throws -> Output`.
- **`_callFromData` returns `ToolOutputValue`** — the type-erased path stays stable for `ToolEngine.execute(name:input:)`.
- **60+ tools** declare `typealias Output = ToolOutputValue`.
- **`@concurrent`** annotation noted for future Swift 6 adoption.

`ToolOutputValue` conforms to `PromptRepresentable` for Apple alignment. The deprecated `RuntimeAgentTool` typealias remains for backward compatibility.

### 6.2 ToolMetadata

`Tools/ToolMetadata.swift` — operational metadata separate from the tool implementation:

```swift
public struct ToolMetadata: Sendable {
    var searchHint: String?
    var isEnabled: Bool
    var isReadOnly: Bool
    var isConcurrencySafe: Bool
    var isDestructive: Bool
    var interruptBehavior: InterruptBehavior
    var activityDescription: String?
    var requiresApproval: Bool
    var permissionCategory: AgentPermission?
}
```

Registered as `(any Tool, ToolMetadata)` pairs in `DefaultToolEngine`.

### 6.3 Batch Registries

Tools are partitioned into 3 batches for parallel loading:

| Batch | Count | Categories | File |
|-------|-------|------------|------|
| Batch 1 | ~15 | Read-only: FileRead, Grep, Glob, WebSearch, WebFetch, ListSkills, etc. | `Batch1ToolRegistry.swift` |
| Batch 23 | ~9 | File mutation + commands: FileWrite, FileEdit, Bash, NotebookEdit, LSP | `Batch23ToolRegistry.swift` |
| Batch 45 | ~36 | Task/agent/workflow/MCP/cron/notification: AgentTool, TaskCreate, MCPTool, SkillTool, etc. | `Batch45ToolRegistry.swift` |

Each registry exposes `static func tools(...) -> [(any Tool, ToolMetadata)]` with dependency-injected parameters (working directory, MCP clients, etc.).

### 6.4 DefaultToolEngine

`SubsystemStubs.swift:8` — actor-based tool registry conforming to `ToolEngine`:

```swift
public actor DefaultToolEngine: ToolEngine {
    func register(tool: any Tool, metadata: ToolMetadata)
    func getDefinition(name: String) -> SessionToolDefinition?
    func getAllDefinitions() -> [SessionToolDefinition]
    func execute(name: String, input: Data) async throws -> ToolOutputValue
}
```

Tools are stored in a `[String: (any Tool, ToolMetadata)]` dictionary. `execute` decodes input via `_callFromData` and returns `ToolOutputValue`.

### 6.5 ToolOutputValue

`Tools/ToolOutputValue.swift:9` — two-case enum for tool results:

```swift
public enum ToolOutputValue: Sendable {
    case string(String)
    case blocks([OutputBlock])
}
```

`OutputBlock` has `type` (`text`, `code`, `diff`, `image`, `error`) and `content: String`. The `stringValue` computed property provides a text fallback.

---

## 7. Permissions

### 7.1 AgentPermission

`Providers/AgentPermission.swift:10` — 13 cases across filesystem, network, device, and execution domains:

```swift
public enum AgentPermission: Sendable, CaseIterable {
    case readFiles(paths: Set<String>)
    case writeFiles(paths: Set<String>)
    case network(domains: Set<String>)
    case contacts, calendar, location
    case camera, microphone
    case runCommands, delete
    case all, `default`, plan
}
```

The `toolName` computed property maps each case to a canonical tool name (e.g., `.runCommands → "Bash"`, `.readFiles → "Read"`) for integration with the legacy `PermissionEngine`.

### 7.2 SessionPermissionEngine

`Providers/AgentPermission.swift:103` — single-method protocol:

```swift
public protocol SessionPermissionEngine: Sendable {
    func check(_ permission: AgentPermission) async throws -> Bool
}
```

### 7.3 AgentPermissionBridge

`Providers/Permission/AgentPermissionBridge.swift:12` — adapts the legacy `PermissionEngine` to `SessionPermissionEngine`. Maps each `AgentPermission` case to tool-name-based permission checks through the wrapped engine, encoding associated paths/domains into the input dictionary.

---

## 8. Memory

### 8.1 SessionMemoryStore Protocol

`Providers/SessionMemoryStore.swift:40` — generic key-namespace storage:

```swift
public protocol SessionMemoryStore: Sendable {
    func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws
    func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T?
    func search<T: Codable & Sendable>(query: String, namespace: String) async throws -> [T]
    func summarize(namespace: String) async throws -> String
    func forget(key: String, namespace: String) async throws
    func listNamespaces() async throws -> [String]
}
```

### 8.2 SQLiteMemoryStore

`Providers/Memory/SQLiteMemoryStore.swift:13` — actor-based implementation using direct SQLite3 C API (no third-party dependencies).

- **WAL journal mode** for concurrent read performance.
- **4 schema migrations**: `schema_version` table, `memory_entries` table (key, namespace, value JSON BLOB, updated_at), indexes on namespace and updated_at.
- **Parameterized queries** exclusively — no string interpolation.
- **Serialized access** through the actor — all CRUD calls are `async`.
- Values stored as JSON BLOBs — `Codable` types are encoded/decoded through `JSONEncoder`/`JSONDecoder`.

---

## 9. Error Taxonomy

`AgentRuntimeError.swift:5` — 19 cases across 5 domains, all conforming to `LocalizedError`. Mirrors Apple's `LanguageModelError` pattern with dedicated info structs for rich error context.

### 9.1 Error Info Structs (Apple-aligned)

Six dedicated structs modeled after Apple's `LanguageModelError` nested info types:

| Struct | Properties | Apple Source |
|--------|-----------|--------------|
| `ContextSizeExceeded` | `maxTokens: Int`, `requestedTokens: Int` | `LanguageModelError.ContextSizeExceeded` |
| `RateLimited` | `retryAfter: TimeInterval?` | `LanguageModelError.RateLimited` |
| `Refusal` | `reason: String` | `LanguageModelError.Refusal` |
| `Timeout` | `duration: TimeInterval?` | `LanguageModelError.Timeout` |
| `GuardrailViolation` | `guardrail: String`, `reason: String` | `LanguageModelError.GuardrailViolation` |
| `UnsupportedCapability` | `capability: String` | `LanguageModelError.UnsupportedCapability` |

### 9.2 Error Cases by Domain

| Domain | Cases |
|--------|-------|
| **Model** | `rateLimited(RateLimited)`, `unauthorized(reason:)`, `serverError(statusCode:body:)`, `timeout(Timeout)`, `contextSizeExceeded(ContextSizeExceeded)`, `invalidResponse(reason:)`, `refusal(Refusal)`, `guardrailViolation(GuardrailViolation)`, `unsupportedCapability(UnsupportedCapability)` |
| **Memory** | `storageFull(availableBytes:)`, `keyNotFound(key:namespace:)`, `migrationFailed(fromVersion:toVersion:reason:)` |
| **Permission** | `permissionDenied(permission:reason:)`, `sandboxViolation(resource:)` |
| **Tool** | `toolNotFound(name:)`, `toolExecutionFailed(name:reason:)`, `toolValidationFailed(name:field:reason:)` |
| **Graph** | `cycleDetected(nodes:)`, `nodeFailed(nodeID:reason:)` |

Each case provides a human-readable `errorDescription` for UI display. Model cases (rateLimited, timeout, contextSizeExceeded, refusal, guardrailViolation, unsupportedCapability) carry structured info for programmatic handling — retry-after delays, token counts, refusal reasons, etc.

---

## 10. Integration Layer

### 10.1 App: ThreadViewModel

`ViewModels/ThreadViewModel.swift:40` — `@MainActor` view model for a conversation thread.

**Session creation**: `AppViewModel.makeSession()` creates a `LanguageModelSessionImpl` with:
- `DeepSeekProvider` (Anthropic-compat mode, `deepseek-v4-pro`)
- `SQLiteMemoryStore` at `~/.swift-agent/projects/<path>/`
- `AgentPermissionBridge` wrapping the legacy `PermissionEngine`
- `DefaultToolEngine` loaded with Batch1 + Batch23 tools

**Stream handling** (`send()` at L257 → `startAgentRun()` at L293):
1. Appends user message, creates assistant placeholder, sets `state = .executing`
2. Calls `session.streamResponse(to: trimmed)` → returns `AsyncThrowingStream`
3. `for try await event in stream` dispatches to `handleSessionEvent()`:
   - `.textDelta` / `.thinkingDelta` → appends to assistant message blocks
   - `.toolCallRequested` / `.toolCallCompleted` → adds `ToolUseBlock` / `ToolResultBlock`
   - `.turnCompleted(usage:)` → records token usage
   - `.error` → sets `state = .failed`, cancels streaming
4. Stream exhaustion → `handleStreamComplete()` → finalizes message, persists to JSONL, processes queued messages

**Persistence**: Messages split into thinking + non-thinking blocks, each written as separate JSONL entries with chained `parentUuid` (Claude Code format). File I/O runs in `Task.detached`.

### 10.2 App: AppViewModel

`ViewModels/AppViewModel.swift` — manages API key resolution, provider configuration, and session factory (`makeSession()`). Current model selection is published via `currentModel` (default: `deepseek-v4-pro`). Permission mode (`default`/`acceptEdits`/`bypassPermissions`/`plan`) drives `AgentPermissionBridge` configuration.

### 10.3 CLI: ChatCommand

`ChatCommand.swift` — creates a `LanguageModelSessionImpl` inline with the same 4 dependencies. Iterates `streamResponse(to:)` and renders `SessionEvent` values to ANSI terminal output via `SessionEventRenderer`.

---

## 11. Subsystem Stubs and Future Slots

### 11.1 No-Op Implementations

`SubsystemStubs.swift:53` provides three stubs for protocols not yet implemented:

- **`NoOpSessionContextManager`** — conforms to `SessionContextManager` (empty protocol). Future: context window tracking and auto-compaction.
- **`NoOpProfileManager`** — conforms to `ProfileManager` (empty protocol). Future: agent identity, personality, and behavior profiles.
- **`NoOpSessionHookSystem`** — conforms to `SessionHookSystem` (empty protocol). Future: lifecycle hooks (pre-prompt, post-response, pre-tool).

### 11.2 AgentGraph

`Graph/AgentGraph.swift:10` — protocol-only type-slot for multi-agent orchestration:

```swift
public protocol AgentGraph: Sendable {
    var nodes: [any AgentNode] { get }
    func validate() throws
}
```

Reserved for a future WWDC27 AgentKit `WorkflowGraph` integration. `LanguageModelSessionImpl.graphEngine` is optional — `nil` when no multi-agent graph is active.

### 11.3 PartiallyGenerated

`PartiallyGenerated.swift` — generic snapshot accumulator for structured-output streaming. Holds `snapshot`, `previousSnapshot`, `changedKeys`, `isComplete`. Not yet wired into the agent loop — designed for future structured JSON output modes.

---

## File Index

| File | Purpose |
|------|---------|
| `LanguageModelSession.swift` | Orchestrator protocol + ToolEngine + 3 stub subsystem protocols |
| `LanguageModelSessionImpl.swift` | Actor implementation — agent loop, tool execution, both streaming/non-streaming paths |
| `StreamingGenerationChannel.swift` | Public actor — continuation bridge with snapshot semantics |
| `GenerationChannel.swift` | 6-method streaming abstraction protocol |
| `SessionEvent.swift` | Provider-agnostic streaming event enum |
| `Transcript.swift` | Codable conversation history (7 entry types) |
| `LanguageModel.swift` | LanguageModel protocol + LanguageModelCapabilities |
| `LanguageModelExecutor.swift` | Executor protocol + GenerationOptions + SessionToolDefinition |
| `AgentPermission.swift` | Runtime permission enum (13 cases) + SessionPermissionEngine protocol |
| `AgentRuntimeError.swift` | Unified error type (19 cases, 5 domains, 6 Apple-aligned info structs) |
| `RuntimeAgentTool.swift` | Tool protocol with dual associated types (Arguments, Output) |
| `Prompt.swift` | Prompt/PromptRepresentable/PromptBuilder + multimodal attachment types |
| `Instructions.swift` | Instructions struct + InstructionsBuilder result builder |
| `TranscriptErrorHandlingPolicy.swift` | Error handling policy for generation (tool errors, context overflow) |
| `Usage.swift` | Token usage (CC-aligned NonNullableUsage) |
| `Response.swift` | Response struct + ResponseStream typealias |
| `SubsystemStubs.swift` | NoOp stubs + DefaultToolEngine actor |
| `AgentPermissionBridge.swift` | SessionPermissionEngine adapter for legacy PermissionEngine |
| `SQLiteMemoryStore.swift` | SQLite3 actor-based memory with schema migration |
| **Provider files** | |
| `AnthropicProvider.swift` | Anthropic Messages API provider |
| `DeepSeekProvider.swift` | DeepSeek dual-API provider |
| `OpenAIProvider.swift` | OpenAI Chat Completions provider |
| `AnthropicSSEParser.swift` | Anthropic SSE stream parser |
| `DeepSeekSSEParser.swift` | DeepSeek dual-mode SSE parser |
| `OpenAISSEParser.swift` | OpenAI Chat Completions SSE parser |
| `AnthropicTranscriptTranslator.swift` | Transcript → Anthropic wire format |
| `DeepSeekTranscriptTranslator.swift` | Transcript → DeepSeek wire format (both modes) |
| `OpenAITranscriptTranslator.swift` | Transcript → OpenAI wire format |
| `AnthropicContentAccumulator.swift` | Per-index tool input JSON accumulator |
| **Tool batch files** | |
| `Batch1ToolRegistry.swift` | 15 read-only tools |
| `Batch23ToolRegistry.swift` | 9 file/cmd tools |
| `Batch45ToolRegistry.swift` | 36 task/agent/mcp tools |
| **Integration files** | |
| `ThreadViewModel.swift` | App: session creation, stream handling, persistence |
| `AppViewModel.swift` | App: API key, provider config, session factory |
| `ChatCommand.swift` | CLI: session creation, ANSI rendering |
