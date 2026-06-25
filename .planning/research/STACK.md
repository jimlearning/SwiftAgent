# Technology Stack

**Project:** SwiftAgent FoundationModels API Reorganization
**Researched:** 2026-06-25
**Overall confidence:** HIGH

---

## Deployment Target Context

**Current minimum:** macOS 15.0 (Sequoia) -- cannot directly use Apple FoundationModels framework.

Apple's FoundationModels framework requires:
- **FoundationModels v1 (WWDC25):** iOS 26+ / macOS 26+ -- `LanguageModelSession`, `SystemLanguageModel`, `@Generable` macro
- **FoundationModels v2 (WWDC26):** iOS 27+ / macOS 27+ -- `LanguageModel` protocol, `LanguageModelExecutor`, `ClaudeForFoundationModels`

Since SwiftAgent targets macOS 15.0+, we build our own equivalent abstractions following the same architectural shape. This is the same strategy Apple's `ChatCompletionsLanguageModel` (in `apple/foundation-models-utilities`) takes for bridging OpenAI-compatible APIs into FoundationModels: implement the protocol shape without requiring the framework itself.

**Future:** When SwiftAgent's minimum deployment target reaches macOS 26, the `LanguageModel` protocol and `LanguageModelSession` can be replaced with Apple's framework types via a thin adapter layer. The patterns recommended here are forward-compatible with that migration.

---

## 1. Core Architecture: Model Abstraction Layer

### LanguageModel Protocol

```swift
/// The core model abstraction. Every inference provider conforms to this.
/// Mirrors Apple's WWDC26 `LanguageModel` protocol shape.
public protocol LanguageModel: Sendable {
    /// Declared capabilities of this model (tool calling, reasoning, vision, etc.)
    var capabilities: LanguageModelCapabilities { get }

    /// Create a session bound to this model with the given configuration.
    /// Sessions carry transcript, tools, and streaming state.
    func makeSession(
        instructions: String,
        tools: [any Tool],
        profile: AgentProfile?
    ) -> LanguageModelSession
}
```

**Why this shape instead of Apple's exact `LanguageModel` + `LanguageModelExecutor` split:**
- We target macOS 15.0+, so we cannot use Apple's runtime executor infrastructure.
- We collapse the model + executor into a single protocol with a `makeSession` factory method.
- When macOS 26 becomes the deployment target, add a `LanguageModelExecutor` protocol and a thin adapter: `AppleLanguageModel` wraps our `LanguageModel` as Apple's `LanguageModelExecutor`.
- LOW confidence: The exact WWDC26 `LanguageModelExecutor` shape is still in beta; the session factory pattern is the most stable part of the design.

### LanguageModelCapabilities

```swift
/// Replaces the dual ModelInfo types (Anthropic + DeepSeek) in the current codebase.
/// Matches Apple's LanguageModelCapabilities design.
public struct LanguageModelCapabilities: Sendable, Equatable {
    /// Core capabilities
    public var supportsToolCalling: Bool = true
    public var supportsStreaming: Bool = true
    public var supportsReasoning: Bool = false
    public var supportsVision: Bool = false
    public var supportsGuidedGeneration: Bool = false

    /// Context window size in tokens
    public var contextWindow: Int = 200_000

    /// Maximum output tokens
    public var maxOutputTokens: Int = 8_192

    /// Model identity
    public var modelID: String
    public var displayName: String

    /// Provider identity
    public var provider: LanguageModelProvider
}

/// Identifies which inference backend owns this model.
public enum LanguageModelProvider: String, Sendable {
    case anthropic
    case openai
    case deepseek
    case apple          // future: SystemLanguageModel
    case custom(String) // future: MLX, Ollama, Gemini
}
```

**Why:** The current codebase has `ModelInfo` in `SwiftAgentCore/LLM/ModelRegistry.swift` and `DeepSeekModel` in `SwiftAgentApp/DeepSeek/`. One struct, shared across all providers, eliminates the dual-type problem.

### LanguageModelSession -- Unified Public API

```swift
/// The primary API surface for agent interactions. Replaces QueryEngine + LLMClient
/// as the public entry point. Mirrors Apple's LanguageModelSession.
///
/// Session owns the transcript, tools, and profile. Model is swappable.
public final class LanguageModelSession: Sendable {
    public let model: any LanguageModel
    public let instructions: String
    public let tools: [any Tool]
    public let profile: AgentProfile?

    /// Non-streaming: returns complete response
    public func respond(to prompt: String) async throws -> SessionResponse

    /// Streaming: yields snapshot deltas as they arrive
    public func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error>
}
```

**Why `class` instead of `struct`:** The session carries mutable state (transcript accumulation, tool call state, token usage). Actor isolation would be ideal (see section 2), but Apple's own `LanguageModelSession` is a reference type. Use `@unchecked Sendable` with internal synchronization. When macOS 26 arrives, replace with Apple's `LanguageModelSession` directly.

**Why session is the public API (not model):** This is the central insight from WWDC26's design. The model is a plugin; the session is the agent runtime surface. All business logic (CLI commands, App view models) depends on `LanguageModelSession`, never on a specific model type.

### LanguageModelError

```swift
/// Unified error type replacing LLMClientError, DeepSeekError, etc.
/// Matches Apple's LanguageModelError shape.
public enum LanguageModelError: Error, Sendable {
    case contextSizeExceeded(maxTokens: Int, requestedTokens: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case authenticationFailed(reason: String)
    case invalidRequest(message: String)
    case serverError(statusCode: Int, body: String?)
    case modelUnavailable(modelID: String)
    case toolExecutionFailed(toolName: String, underlying: Error?)
    case unsupportedCapability(String)
}
```

**Why:** The current codebase has fragmented error types (LLMClient.swift has inline error handling, DeepSeekClient has its own, etc.). One enum, used everywhere, with per-provider mapping at the executor boundary.

### Provider Executor Pattern

Each provider implements a `LanguageModelExecutor` behind the `LanguageModel` protocol:

```swift
/// Internal protocol for per-provider inference. Not exposed to business logic.
/// Mirrors Apple's LanguageModelExecutor shape.
protocol LanguageModelExecutor: Sendable {
    associatedtype Model: LanguageModel

    func respond(
        to request: GenerationRequest,
        model: Model,
        streamingInto channel: GenerationChannel
    ) async throws
}

/// The generation channel: executor pushes typed events, session consumes them.
/// Decouples executor internals from the session's public API.
actor GenerationChannel {
    private var continuation: AsyncThrowingStream<SessionEvent, Error>.Continuation?

    func setContinuation(_ c: AsyncThrowingStream<SessionEvent, Error>.Continuation) {
        self.continuation = c
    }

    func send(_ event: SessionEvent) {
        continuation?.yield(event)
    }

    func finish(throwing error: Error? = nil) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}
```

**Why `actor` for GenerationChannel:** The executor may run on a background task; the session consumes on the main actor. The channel is the synchronization point. `actor` gives us serialized access to the continuation without manual locking. This is the canonical pattern from ClaudeIsland's `AsyncStream` broadcast design.

**Why this split:** Wire-format isolation. Each executor (AnthropicExecutor, DeepSeekExecutor, OpenAIExecutor) owns its own `StreamEvent`/`ContentBlock` types internally. The `GenerationChannel` only accepts the public `SessionEvent` type. This eliminates the current problem where Anthropic's `ContentBlock` type leaks through the entire agent loop.

### GenerationRequest -- Internal Type

```swift
/// Normalized request from Session to Executor. Session translates its transcript
/// into this format before calling the executor.
struct GenerationRequest: Sendable {
    let modelID: String
    let systemPrompt: String
    let messages: [TranscriptEntry]   // session-owned transcript entries
    let tools: [ToolDefinition]       // simplified tool definitions
    let generationOptions: GenerationOptions
}

struct GenerationOptions: Sendable {
    var maxTokens: Int?
    var temperature: Double?
    var reasoningBudget: Int?         // nil = disabled
    var stream: Bool = true
}
```

**Why:** Each executor maps `GenerationRequest` to its own wire format (Anthropic Messages API, OpenAI Chat Completions, etc.). The session never knows about Anthropic-specific JSON shapes.

---

## 2. Swift Concurrency Patterns

### Pattern A: Actor-Isolated Session State

For mutable session state (transcript, token counts, tool call tracking):

```swift
actor SessionState {
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var tokenUsage: TokenUsage = .zero
    private var inProgressToolCalls: Set<String> = []

    func appendEntry(_ entry: TranscriptEntry) {
        transcript.append(entry)
    }

    func trackToolCall(_ id: String) {
        inProgressToolCalls.insert(id)
    }

    func completeToolCall(_ id: String) {
        inProgressToolCalls.remove(id)
    }

    // IMPORTANT: Re-check after every suspension point (actor reentrancy)
    func getTokenUsage() -> TokenUsage { tokenUsage }
}
```

**Why:** The current `QueryEngine` uses unstructured state mutation across multiple types. Actor isolation gives us:
1. Compiler-enforced data race safety (Swift 6 strict concurrency)
2. Clear mutation points (only `actor` methods can mutate)
3. Reentrancy-awareness at suspension points (the compiler warns about re-checking after `await`)

**Pitfall: Actor reentrancy.** When an actor method `await`s, other tasks can run on the actor. Always re-verify state after suspension points. This is the #1 actor bug pattern.

### Pattern B: AsyncThrowingStream for Snapshot Streaming

The current codebase streams raw `StreamEvent` tokens (Anthropic SSE format). The new design streams typed `SessionEvent` snapshots:

```swift
/// Public streaming events — executor-agnostic.
enum SessionEvent: Sendable {
    /// A partially generated piece of content (text, thinking, structured output).
    case partial(PartiallyGeneratedContent)

    /// A tool use request from the model.
    case toolUseRequest(ToolUseRequest)

    /// A tool execution result.
    case toolResult(ToolUseResult)

    /// Stream metadata update (token counts, model ID, timing).
    case metadata(SessionMetadata)

    /// Stream terminated (either complete or with error).
    case finished(FinishReason)
}

struct PartiallyGeneratedContent: Sendable {
    let textDelta: String?
    let thinkingDelta: String?
    let partialStructuredOutput: JSONValue?   // for type-driven structured output
}

enum FinishReason: Sendable {
    case endTurn
    case maxTokens
    case toolUse
    case stopSequence(String)
    case error(LanguageModelError)
}
```

**Why snapshots over token deltas:**
- The current system exposes raw SSE events (`textDelta`, `thinkingDelta`, `inputJSONDelta`) directly. This leaks Anthropic's wire format.
- FoundationModels uses `AsyncSequence<PartiallyGenerated<T>>` -- a snapshot model where each event is a complete partial view, not a raw delta.
- Snapshot streaming simplifies the renderer: no need to accumulate deltas and reconstruct state. Each event is self-consistent.
- The executor converts provider-specific SSE events → `SessionEvent` internally. Neither the session nor the renderer knows about SSE.

**AsyncThrowingStream setup pattern:**

```swift
func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                let channel = GenerationChannel()
                await channel.setContinuation(continuation)

                let request = buildGenerationRequest(from: prompt)
                try await model.executor.respond(
                    to: request,
                    model: model,
                    streamingInto: channel
                )
                await channel.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

**Why `Task` inside `AsyncThrowingStream`:** The executor's `respond()` is async (it makes network calls). The stream's builder closure is synchronous because `AsyncThrowingStream` uses a `Continuation`. We launch a `Task` to bridge async work into the continuation. The `GenerationChannel` actor bridges between them.

### Pattern C: @MainActor + @Observable for UI State

For the App target's SwiftUI layer:

```swift
@MainActor
@Observable
final class SessionViewModel {
    private(set) var partialContent: String = ""
    private(set) var thinkingContent: String = ""
    private(set) var toolCalls: [ToolUseRequest] = []
    private(set) var isStreaming: Bool = false
    private(set) var error: LanguageModelError?

    private var streamTask: Task<Void, Never>?

    func respond(to prompt: String) {
        isStreaming = true
        error = nil

        streamTask = Task { @MainActor in
            do {
                for try await event in session.streamResponse(to: prompt) {
                    switch event {
                    case .partial(let p):
                        if let delta = p.textDelta { partialContent += delta }
                        if let delta = p.thinkingDelta { thinkingContent += delta }
                    case .toolUseRequest(let req):
                        toolCalls.append(req)
                    case .toolResult(let res):
                        applyToolResult(res)
                    case .metadata(let meta):
                        updateMetadata(meta)
                    case .finished(let reason):
                        handleFinish(reason)
                    }
                }
            } catch {
                self.error = error as? LanguageModelError ?? .serverError(statusCode: 0, body: nil)
            }
            isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        isStreaming = false
    }
}
```

**Why `@MainActor @Observable` instead of `@Published`:** `@Observable` (Swift 5.9+, iOS 17+/macOS 14+) provides fine-grained reactivity -- only views reading changed properties re-render. This matters for streaming: when `partialContent` updates 50 times/second, only the text bubble re-renders, not the entire view hierarchy. `@Published` triggers full `objectWillChange` on every update.

### Pattern D: Sendable Data Types

All types crossing actor boundaries must be `Sendable`. This is non-negotiable in Swift 6 strict concurrency mode:

```swift
// VALUE TYPES: Easy Sendable
struct TranscriptEntry: Sendable, Codable { ... }
struct ToolUseRequest: Sendable, Codable { ... }
struct GenerationOptions: Sendable { ... }

// ENUMS: Easy Sendable with associated value discipline
enum SessionEvent: Sendable { ... }
enum FinishReason: Sendable { ... }

// REFERENCE TYPES: Must be @unchecked Sendable with internal sync,
// OR use actor isolation instead
final class LanguageModelSession: @unchecked Sendable { ... }
actor SessionState { ... }
```

**Current codebase issue:** `ToolUseContext` (in Tool.swift) has many non-Sendable closures and `Any`-typed fields. The reorganized API moves closures into dedicated protocols with `@Sendable` annotations, and replaces `Any` with typed `Sendable` wrappers.

### Pattern E: Task Cancellation

```swift
// Session-level cancellation
func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            // ... streaming work ...
        }
        continuation.onTermination = { @Sendable reason in
            if case .cancelled = reason {
                task.cancel()
            }
        }
    }
}
```

**Why `continuation.onTermination`:** When the consumer stops iterating the `AsyncThrowingStream` (e.g., user presses ESC), this callback fires and we cancel the underlying `Task`. Without this, the network request continues indefinitely.

---

## 3. Tool System: Simplified Protocol

### Target: ~6 Members

The current `Tool` protocol has 43 members (29 required + 14 with defaults). The reorganized protocol targets ~6 core members:

```swift
/// Simplified tool protocol matching FoundationModels design.
/// Providers that need the full Claude Code Tool surface implement
/// the extended CCTool protocol separately.
public protocol Tool: Sendable {
    /// The tool name as seen by the LLM (PascalCase, e.g., "Bash", "Read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    var description: String { get }

    /// Input schema defining the tool's parameters.
    var inputSchema: ToolInputSchema { get }

    /// Whether this tool is read-only (safe for auto-approval).
    var isReadOnly: Bool { get }

    /// Execute the tool with the given input.
    func call(_ input: ToolInput) async throws -> ToolResult
}
```

**Why 6 members instead of 43:** The 43-member protocol is a direct port of Claude Code's internal Tool type -- which includes Claude-Code-specific UX concerns (searchOrReadCommand, userFacingNameBackgroundColor, activityDescription, etc.). These are rendering concerns, not inference concerns. The simplified protocol captures what the LLM needs:
- `name` + `description` → system prompt rendering
- `inputSchema` → API tool definition
- `isReadOnly` → permission gating
- `call()` → execution

### Progressive Disclosure via Protocol Extensions

For tools that need CC-level detail, use protocol extensions and optional requirements:

```swift
/// Extended tool protocol for Claude Code compatibility.
/// Tools can adopt this independently of the base Tool protocol.
protocol CCToolExtensions {
    var aliases: [String] { get }
    var isConcurrencySafe: Bool { get }
    var strict: Bool { get }
    var outputSchema: ToolInputSchema? { get }
    func isDestructive(_ input: ToolInput) -> Bool
    func getPath(_ input: ToolInput) -> String?
    func getActivityDescription(_ input: ToolInput) -> String?
    func isSearchOrReadCommand(_ input: ToolInput) -> SearchOrReadResult
}

extension CCToolExtensions {
    var aliases: [String] { [] }
    var isConcurrencySafe: Bool { false }
    var strict: Bool { false }
    var outputSchema: ToolInputSchema? { nil }
    func isDestructive(_ input: ToolInput) -> Bool { false }
    func getPath(_ input: ToolInput) -> String? { nil }
    func getActivityDescription(_ input: ToolInput) -> String? { nil }
    func isSearchOrReadCommand(_ input: ToolInput) -> SearchOrReadResult { .none }
}
```

**Why separate protocols:** The `LanguageModel` protocol and `LanguageModelSession` only depend on `Tool`. The CC-specific concerns live in `CCToolExtensions`, used by the CLI/App rendering layer but invisible to the agent runtime.

### ToolInput and ToolInputSchema

```swift
/// Type-safe tool input -- replaces [String: JSONValue] dictionaries.
/// FoundationModels uses compiler-generated Codable types via @Generable.
/// We use a Sendable dictionary until macros become available.
public struct ToolInput: Sendable, ExpressibleByDictionaryLiteral {
    private var storage: [String: ToolInputValue]

    public subscript(key: String) -> ToolInputValue? {
        storage[key]
    }

    /// Typed accessor -- avoids stringly-typed JSONValue checks.
    public func getString(_ key: String) -> String? {
        if case .string(let s) = storage[key] { return s }
        return nil
    }
    public func getInt(_ key: String) -> Int? {
        if case .number(let n) = storage[key] { return Int(n) }
        return nil
    }
    public func getBool(_ key: String) -> Bool? {
        if case .bool(let b) = storage[key] { return b }
        return nil
    }
    public func getArray(_ key: String) -> [ToolInputValue]? {
        if case .array(let a) = storage[key] { return a }
        return nil
    }
}

/// Schema for tool input parameters. Compatible with Anthropic/OpenAI JSON Schema subsets.
/// When macOS 26 is available, this can be auto-generated via @Generable macro.
public struct ToolInputSchema: Sendable {
    public let type: String = "object"
    public let properties: [String: PropertySchema]
    public let required: [String]

    public struct PropertySchema: Sendable {
        public let type: String
        public let description: String?
        public let `enum`: [String]?
        public let items: PropertySchema?
    }
}
```

**Why not [String: JSONValue]:** The current `Tool` protocol uses `[String: JSONValue]` everywhere. This is untyped -- tools must manually cast and validate. `ToolInput` provides typed accessors while maintaining Sendable compatibility. The future direction is `@Generable`-generated per-tool input types (each tool gets its own Codable struct).

### Tool Registry Pattern

```swift
/// Registry of available tools. LanguageModelSession queries this for
/// tool definitions to include in API requests.
actor ToolRegistry {
    private var tools: [String: any Tool] = [:]

    func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    func get(_ name: String) -> (any Tool)? {
        tools[name]
    }

    var allTools: [any Tool] {
        Array(tools.values)
    }

    /// Filter tools by capability requested by the model
    func filter(for capabilities: LanguageModelCapabilities) -> [any Tool] {
        // Some providers can't handle certain tools -- filter here
        allTools
    }
}
```

**Why `actor`:** The current tool registry is mutated during MCP server connection (dynamic tools). Actor isolation makes this safe without locks.

---

## 4. Streaming Architecture

### Two-Phase Streaming: Provider → Executor → Session

```
SSE Bytes (URLSession.AsyncBytes)
    │
    ▼
Executor.parseSSE() → Internal Wire Events (AnthropicStreamEvent)
    │
    ▼
Executor.normalize() → SessionEvent (public type)
    │
    ▼
GenerationChannel.send() → AsyncThrowingStream<SessionEvent>
    │
    ▼
LanguageModelSession.streamResponse() → Consumer (CLI/App)
```

**Phase 1: Executor-level SSE parsing.** Each executor owns its SSE parser. AnthropicExecutor parses Anthropic's `data: {...}` format. DeepSeekExecutor parses DeepSeek's format. OpenAIExecutor parses OpenAI's format. These parsers produce executor-internal types.

**Phase 2: Normalization to `SessionEvent`.** The executor converts its internal events to the public `SessionEvent` type. This is the wire-format isolation boundary.

**Why two phases:** Phase 1 is provider-specific and testable in isolation. Phase 2 is a pure function (internal type → public type) that can be snapshot-tested. The session never sees raw SSE.

### URLSession.AsyncBytes for HTTP Streaming

```swift
/// Inside AnthropicExecutor.respond()
func streamRequest(_ request: URLRequest) async throws {
    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw LanguageModelError.serverError(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            body: nil
        )
    }

    var buffer = ""

    for try await line in asyncBytes.lines {
        buffer += line

        // SSE events are separated by double newlines
        while let range = buffer.range(of: "\n\n") {
            let event = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            if let sessionEvent = parseSSEEvent(event) {
                await channel.send(sessionEvent)
            }
        }
    }
}
```

**Why `URLSession.shared.bytes(for:)`:** This returns `AsyncBytes` which conforms to `AsyncSequence`. It uses HTTP/1.1 chunked transfer encoding or HTTP/2 frames natively. The `.lines` property gives us line-by-line iteration for SSE parsing. No manual buffer management needed. This is the standard Swift 6 pattern for streaming HTTP -- used by the Open Agent SDK and A2A Swift SDK.

### Thinking/Reasoning Streaming

```swift
/// Inside AnthropicExecutor -- handling thinking blocks
func normalizeDelta(_ event: AnthropicStreamEvent, to channel: GenerationChannel) async {
    switch event {
    case .contentBlockDelta(let delta):
        switch delta.type {
        case "text_delta":
            await channel.send(.partial(PartiallyGeneratedContent(textDelta: delta.text)))
        case "thinking_delta":
            await channel.send(.partial(PartiallyGeneratedContent(thinkingDelta: delta.thinking)))
        case "redacted_thinking_delta":
            await channel.send(.partial(PartiallyGeneratedContent(thinkingDelta: "[thinking redacted]")))
        case "input_json_delta":
            await channel.send(.partial(PartiallyGeneratedContent(
                partialStructuredOutput: accumulateJSON(delta.partialJSON)
            )))
        }
    case .contentBlockStop:
        await channel.send(.finished(.endTurn))
    }
}
```

**Why thinking is a separate delta from text:** The renderer needs to display thinking in a dimmed/collapsible section. The session event distinguishes `textDelta` from `thinkingDelta`. The renderer decides how to display each.

---

## 5. Structured Output: Runtime Approach

### Current State: Manual JSONSchema

The current codebase uses `JSONSchema` structs defined in `Tool.swift`. Tools manually construct schemas:

```swift
struct BashTool: Tool {
    var inputSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "command": JSONSchemaProperty(type: "string", description: "The command to run"),
                "timeout": JSONSchemaProperty(type: "number", description: "Timeout in seconds")
            ],
            required: ["command"]
        )
    }
}
```

### Target: Type-Driven Schema Generation

We cannot use `@Generable` (requires macOS 26+ / iOS 26+). Instead, use a runtime equivalent:

```swift
/// Generates a ToolInputSchema from a Codable Swift type at runtime.
/// This is the migration path toward @Generable -- when macOS 26 becomes
/// the deployment target, replace this with the macro.
protocol ToolInputRepresentable: Codable, Sendable {
    static var toolInputSchema: ToolInputSchema { get }
}

// A macro-like runtime generator using Mirror reflection
func generateSchema<T: Codable>(for type: T.Type) -> ToolInputSchema {
    // Uses Mirror + CodingKeys to derive JSON Schema at runtime
    // Falls back to manual schema definition when reflection is insufficient
    // ...
}
```

**Why runtime instead of macros:** Swift macros require Swift 5.9+ and macOS 14+, which we have. But `@Generable` specifically requires FoundationModels framework (macOS 26+). We can't use `@Generable` directly. A runtime schema generator using `Mirror` + `Codable` gives us 80% of the value today. When we raise the deployment target, swapping to `@Generable` is a search-and-replace of the schema generation call site.

**What we lose without `@Generable`:**
- Constrained decoding (model forced to output valid JSON): not available through third-party APIs anyway
- `PartiallyGenerated<T>` streaming of structured types: can simulate with JSON accumulation
- Compile-time schema validation: can approximate with unit tests

---

## 6. Provider Implementations

### 6.1 AnthropicExecutor

```swift
/// Executor for Anthropic's Messages API.
/// Internal to the LanguageModel boundary. Not exposed to business logic.
actor AnthropicExecutor: LanguageModelExecutor {
    typealias Model = AnthropicModel

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    func respond(
        to request: GenerationRequest,
        model: AnthropicModel,
        streamingInto channel: GenerationChannel
    ) async throws {
        let (messages, system) = translateTranscript(request.messages, instructions: request.instructions)
        let tools = translateToolDefinitions(request.tools)

        var body: [String: Any] = [
            "model": model.modelID,
            "messages": messages,
            "max_tokens": request.generationOptions.maxTokens ?? 4096
        ]
        if let system = system { body["system"] = system }
        if !tools.isEmpty { body["tools"] = tools }
        if let budget = request.generationOptions.reasoningBudget {
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }

        let urlRequest = buildRequest(url: baseURL.appendingPathComponent("v1/messages"), body: body)
        let (asyncBytes, response) = try await session.bytes(for: urlRequest)

        // ... SSE parsing + normalization to SessionEvent ...
    }
}
```

**Why `actor`:** The executor holds `URLSession` (not Sendable in all configurations). Actor isolation makes this safe.

### 6.2 DeepSeekExecutor (Unified)

Current state: Two separate DeepSeek code paths:
1. `LLMClient` configured for `https://api.deepseek.com/anthropic` (Anthropic-compat)
2. `DeepSeekClient` directly calls `https://api.deepseek.com/v1/chat/completions` (OpenAI-compat)

Target: Single `DeepSeekExecutor`:

```swift
actor DeepSeekExecutor: LanguageModelExecutor {
    typealias Model = DeepSeekModel

    enum APICompatibility {
        case anthropicCompatible   // /anthropic endpoint
        case openAICompatible      // /v1/chat/completions endpoint
    }

    private let compatibility: APICompatibility

    func respond(
        to request: GenerationRequest,
        model: DeepSeekModel,
        streamingInto channel: GenerationChannel
    ) async throws {
        switch compatibility {
        case .anthropicCompatible:
            try await streamAnthropicCompatible(request, model: model, channel: channel)
        case .openAICompatible:
            try await streamOpenAICompatible(request, model: model, channel: channel)
        }
    }
}
```

**Why one executor, two paths internally:** DeepSeek's API is one service with two endpoint formats. A single executor with an internal `APICompatibility` switch is cleaner than two separate executors or (worse) two separate code paths in the app layer. The business logic never knows which endpoint format is used.

### 6.3 OpenAIExecutor

```swift
actor OpenAIExecutor: LanguageModelExecutor {
    typealias Model = OpenAIModel

    func respond(
        to request: GenerationRequest,
        model: OpenAIModel,
        streamingInto channel: GenerationChannel
    ) async throws {
        // Translate GenerationRequest → OpenAI Chat Completions format
        let openAIMessages = translateTranscript(request.messages)
        let tools = translateToolDefinitions(request.tools)

        let body: [String: Any] = [
            "model": model.modelID,
            "messages": openAIMessages,
            "stream": true
        ]
        // ... OpenAI-specific tool_choice, response_format, etc.

        let urlRequest = buildRequest(
            url: baseURL.appendingPathComponent("v1/chat/completions"),
            body: body,
            authHeader: "Bearer \(apiKey)"
        )

        let (asyncBytes, response) = try await session.bytes(for: urlRequest)
        // ... SSE parsing + normalization to SessionEvent ...
    }

    /// OpenAI SSE delta → SessionEvent
    func normalizeChunk(_ chunk: OpenAIStreamChunk, to channel: GenerationChannel) async {
        if let delta = chunk.choices.first?.delta {
            if let content = delta.content {
                await channel.send(.partial(PartiallyGeneratedContent(textDelta: content)))
            }
            if let toolCalls = delta.tool_calls {
                for tc in toolCalls {
                    // Accumulate tool call JSON across chunks
                    // Emit .toolUseRequest when complete
                }
            }
        }
        if chunk.choices.first?.finish_reason != nil {
            await channel.send(.finished(.endTurn))
        }
    }
}
```

### 6.4 Provider Model Types

```swift
/// Per-provider model configuration. Each conforms to LanguageModel
/// and carries provider-specific settings.
struct AnthropicModel: LanguageModel {
    let modelID: String
    let displayName: String
    let apiKey: String
    let baseURL: URL
    let betas: [AnthropicBeta]?

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(
            supportsToolCalling: true,
            supportsStreaming: true,
            supportsReasoning: modelID.contains("sonnet") || modelID.contains("opus"),
            supportsVision: modelID.contains("sonnet") || modelID.contains("opus"),
            contextWindow: contextWindowForModel(modelID),
            maxOutputTokens: 8192,
            modelID: modelID,
            displayName: displayName,
            provider: .anthropic
        )
    }

    func makeSession(instructions: String, tools: [any Tool], profile: AgentProfile?) -> LanguageModelSession {
        LanguageModelSession(
            model: self,
            instructions: instructions,
            tools: tools,
            profile: profile,
            executor: AnthropicExecutor(apiKey: apiKey, baseURL: baseURL)
        )
    }
}
```

**Why structs for models, not classes:** Models are value types (identity is their configuration). They cross actor boundaries when passed to executors. `Sendable` struct is the natural fit.

---

## 7. Supporting Libraries

### What to Use

| Library | Version | Purpose | Rationale |
|---------|---------|---------|-----------|
| **Swift 6.3 stdlib** | 6.3 | AsyncThrowingStream, actors, Sendable, Task, @Observable | Zero-dependency foundation. Everything we need for streaming, concurrency, and reactivity is in the stdlib. |
| **Foundation** | (system) | URLSession, JSONEncoder/Decoder, FileManager | URLSession.AsyncBytes for SSE streaming. Codable for tool input types. |
| **swift-collections** | 1.0+ | OrderedDictionary, OrderedSet | Tool registry ordering. OrderedSet for deduplication of MCP tool names. Already in the project. |
| **KeychainAccess** | 4.2+ | API key storage | Already in the project. Used by KeychainStore. Compatible with the new auth model. |

### What NOT to Use (and Why)

| Library | Why Not |
|---------|---------|
| **Swift OpenAPI Generator** | Generates client code from OpenAPI specs. None of the major LLM providers publish maintained OpenAPI specs for their streaming APIs. The generated code would be obsolete faster than hand-written executors. Anthropic doesn't publish an OpenAPI spec for Messages API streaming. |
| **AsyncAlgorithms** (Apple) | Provides `AsyncSequence` combinators (merge, zip, debounce). Not needed: we have a single stream per session. The complexity of merging multiple provider streams is handled inside the executor, not via AsyncSequence combinators. |
| **SwiftNIO** | Low-level networking. Overkill for HTTP streaming. `URLSession.AsyncBytes` handles SSE efficiently. NIO would require manual HTTP/2 frame parsing. |
| **GRPC / Connect-Swift** | No LLM provider uses gRPC for inference streaming. All major providers use HTTP+SSE or WebSocket. |
| **Combine** | `AsyncThrowingStream` replaces `PassthroughSubject` for streaming. `@Observable` replaces `@Published`. Combine adds a dependency for patterns the stdlib now handles natively. |
| **Vapor / Hummingbird** | Server-side frameworks. SwiftAgent is a local agent -- no server runtime needed. The OAuth callback server uses a minimal `NWListener` (already implemented). |
| **SwiftData** | Overkill for session transcripts. The existing file-based JSONL persistence is simpler, faster, and CC-compatible. SwiftData would require schema migrations for every message format change. |

### For Future Consideration (Post-Reorganization)

| Library | When to Adopt |
|---------|---------------|
| **FoundationModels framework** | When deployment target reaches macOS 26. Replace our `LanguageModel` protocol with Apple's. Keep our executors, just adapt them to `LanguageModelExecutor`. |
| **ClaudeForFoundationModels** | After adopting FoundationModels framework. Replaces our `AnthropicExecutor` with Anthropic's official one. |
| **@Generable macro** | After adopting FoundationModels framework. Replaces runtime schema generation with compile-time. |
| **MLX Swift** | When adding local/on-device model support. For MLX-based models running on Apple Silicon. |
| **Swift Testing** (Apple) | When migrating tests from XCTest. Better async support, parameterized tests. Not urgent. |

---

## 8. Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Model abstraction | Custom `LanguageModel` protocol (mirrors Apple's) | Open Agent SDK `LLMClient` protocol | Open Agent SDK normalizes everything to Anthropic format internally. We want format neutrality (each executor owns its format). Also, Open Agent SDK is a dependency; our protocol is zero-dependency. |
| Streaming | `AsyncThrowingStream<SessionEvent, Error>` | Combine `PassthroughSubject<SessionEvent, Error>` | Combine is being deprecated in favor of Swift Concurrency. `AsyncSequence` is the standard Swift 6 pattern. |
| Session API surface | `LanguageModelSession` (class) | `QueryEngine` + `LLMClient` (current) | Current design couples the agent loop to Anthropic's wire types. Session encapsulates transcript, tools, and streaming behind a provider-agnostic interface. |
| Tool protocol size | 6 core members + optional `CCToolExtensions` | Keep 43-member protocol | The 43-member protocol is rendering-layer concerns mixed with inference concerns. Separation enables the `LanguageModelSession` to depend only on what inference needs. |
| Structured output | Runtime schema from Codable types | Manual `JSONSchema` (current) | Runtime generation is 80% of the value of `@Generable` with zero additional tooling. Can be replaced with `@Generable` when macOS 26 is available. |
| DeepSeek integration | Single `DeepSeekExecutor` with internal compat switch | Two separate code paths (current) | Eliminates duplication. Both paths produce the same `SessionEvent` type. The compat switch is internal to the executor. |
| Error handling | Single `LanguageModelError` enum | Fragmented error types (current) | Enables unified error handling in Session. Each executor maps provider-specific errors to `LanguageModelError` cases. |

---

## 9. File Structure for the Reorganized API

```
Sources/SwiftAgentCore/
├── LanguageModel/                    # NEW: Model abstraction layer
│   ├── LanguageModel.swift           # Core protocol
│   ├── LanguageModelSession.swift    # Unified public API
│   ├── LanguageModelCapabilities.swift
│   ├── LanguageModelError.swift
│   ├── GenerationRequest.swift       # Internal request type
│   ├── GenerationChannel.swift       # Actor-based streaming channel
│   └── SessionEvent.swift            # Public streaming event types
├── Executors/                        # NEW: Provider implementations
│   ├── AnthropicExecutor.swift       # Anthropic Messages API
│   ├── DeepSeekExecutor.swift        # Unified DeepSeek (Anthropic + OpenAI compat)
│   └── OpenAIExecutor.swift          # OpenAI Chat Completions
├── Tools/                            # MODIFIED: Simplified Tool protocol
│   ├── Tool.swift                    # 6-member core protocol + ToolInput, ToolInputSchema
│   ├── CCToolExtensions.swift        # CC-specific optional extensions
│   ├── ToolRegistry.swift            # Actor-based tool registry
│   └── [43 tool files unchanged]     # Existing tools adopt new protocol
├── Session/                          # RENAMED from Agent/
│   ├── ToolExecutor.swift            # Tool execution (unchanged core logic)
│   ├── StreamRenderer.swift          # Adapts SessionEvent → render output
│   ├── Compactor.swift               # Context compaction (unchanged)
│   └── HookEngine.swift              # Hook system (unchanged)
├── Types/                            # MODIFIED: Reduced, Sendable-clean
│   ├── Conversation.swift            # TranscriptEntry, Message (Sendable)
│   ├── AgentProfile.swift            # NEW: Profile concept
│   ├── StreamEvent.swift             # DEPRECATED: Move to AnthropicExecutor internal
│   └── [permission types unchanged]
├── LLM/                              # DEPRECATED: Absorbed into LanguageModel + Executors
└── Storage/ Config/ MCP/ Hooks/      # Unchanged
```

---

## 10. Migration Strategy: Risk-Controlled Refactoring

### Phase Order

1. **Define new types first** (zero behavioral change):
   - `LanguageModel` protocol, `LanguageModelSession`, `LanguageModelCapabilities`, `LanguageModelError`
   - `SessionEvent`, `GenerationChannel`, `ToolInputSchema`
   - Simplified `Tool` protocol (6 members)

2. **Build executors behind the new protocol** (existing code unchanged):
   - `AnthropicExecutor` wrapping existing `LLMClient` internally
   - `DeepSeekExecutor` wrapping existing `DeepSeekClient` + `LLMClient`(anthropic compat)
   - `OpenAIExecutor` as new implementation

3. **Wire `LanguageModelSession` into CLI/App** (replace `QueryEngine` entry points):
   - Switch callers from `QueryEngine.query()` + `LLMClient.stream()` to `session.streamResponse()`
   - Keep old code path behind a feature flag during transition

4. **Deprecate and remove old types:**
   - `LLMClient`, `LLMStreamParser` → absorbed into AnthropicExecutor internals
   - `StreamEvent` → becomes AnthropicExecutor internal
   - `ContentBlock` → becomes AnthropicExecutor internal
   - `QueryEngine` → replaced by LanguageModelSession
   - `AppLLMProvider`, `ProviderRegistry` → replaced by LanguageModel + ToolRegistry

**Why this order:** Every step is testable independently. Step 1 adds types without breaking anything. Step 2 adds new code paths. Step 3 switches consumers one at a time. Step 4 removes dead code only after validation.

### Test Safety

- All 258+ tests must pass at each step
- New executors get their own test suites before replacing old code
- Feature flag: `LANGUAGE_MODEL_SESSION_ENABLED` gates the new code path
- The old `QueryEngine` + `LLMClient` path remains until the new path is stable in production

---

## 11. Confidence Assessment

| Recommendation | Confidence | Basis |
|----------------|------------|-------|
| `LanguageModel` protocol shape | MEDIUM | Mirrors Apple's WWDC26 design (public API confirmed). But WWDC26 is beta -- exact API shape may change. Our protocol is simpler (no `executorConfiguration` struct) to stay flexible. |
| `LanguageModelSession` as public API | HIGH | Apple's WWDC25+26 design, Open Agent SDK pattern, Operator pattern -- all use session-as-primary-API. This is the consensus architecture. |
| Actor isolation for state | HIGH | Swift 6 strict concurrency requires it. ClaudeIsland, Open Agent SDK, and A2A Swift all use this pattern. |
| `AsyncThrowingStream` for streaming | HIGH | Standard Swift 6 pattern. FoundationModels uses `AsyncSequence`. Open Agent SDK uses `AsyncThrowingStream`. |
| Simplified Tool protocol (6 members) | HIGH | FoundationModels Tool has ~4 members. Open Agent SDK has ~6. Our current 43 members is an outlier. |
| Runtime schema generation vs macros | MEDIUM | `@Generable` is the right direction but unavailable (macOS 26+). Runtime generation with Mirror is the pragmatic bridge. The risk is that Mirror-based schema generation may miss edge cases (nested generics, complex enums). |
| Wire-format isolation (executor-internal) | HIGH | FoundationModels' explicit design goal. Open Agent SDK does it. The current leakage of `ContentBlock`/`StreamEvent` is a known problem. |
| Unified DeepSeek executor | HIGH | Both code paths hit the same API service. The compat switch is a minor implementation detail. |

---

## 12. Sources

- [WWDC26 Session 339: Bring an LLM Provider to Foundation Models](https://developer.apple.com/videos/play/wwdc2026/339/) -- HIGH confidence (official Apple)
- [WWDC26 Session 241: What's New in Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/) -- HIGH confidence (official Apple)
- [Claude For Foundation Models (Anthropic docs)](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models) -- HIGH confidence (official Anthropic)
- [Open Agent SDK (Swift)](https://github.com/terryso/open-agent-sdk-swift) -- HIGH confidence (source code, MIT licensed)
- [AgentKitten](https://github.com/fbeeper/agentkitten) -- MEDIUM confidence (third-party, but comprehensive)
- [Operator](https://github.com/bensyverson/Operator) -- MEDIUM confidence (third-party, well-documented)
- [A2A for Swift](https://github.com/Victory-Apps/a2a-swift) -- MEDIUM confidence (Google A2A protocol implementation)
- [ClaudeIsland architecture (DeepWiki)](https://deepwiki.com/engels74/claude-island/2.4-concurrency-and-actor-model) -- MEDIUM confidence (third-party analysis)
- [Swift 6 Concurrency Agent Skill](https://github.com/avdlee/swift-concurrency-agent-skill) -- LOW confidence (community skill, not official)
- [Apple FoundationModels Documentation](https://developer.apple.com/documentation/foundationmodels) -- HIGH confidence (official Apple)
- [AboutAppleFoundationModels.md (project)](../AboutAppleFoundationModels.md) -- LOW confidence (community analysis, but comprehensive)
- Current SwiftAgent codebase analysis (`Sources/SwiftAgentCore/Types/Tool.swift`, `Sources/SwiftAgentCore/LLM/`, `Sources/SwiftAgentApp/LLM/`) -- HIGH confidence (primary source)

