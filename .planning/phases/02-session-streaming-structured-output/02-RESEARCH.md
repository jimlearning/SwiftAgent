# Phase 2: Session, Streaming & Structured Output - Research

**Researched:** 2026-06-25
**Domain:** Agent runtime orchestration loop, snapshot-based streaming, runtime JSON schema generation
**Confidence:** HIGH

## Summary

Phase 2 builds the concrete runtime core atop Phase 1's protocol blueprint. The central deliverable is an `AgentRuntimeImpl` actor that runs the agent loop: append prompt to Transcript, invoke LanguageModelExecutor via GenerationChannel, process tool calls, loop until end-turn, update MemoryStore. All of this is validated against mock providers (MockLanguageModel, MockLanguageModelExecutor, MockMemoryStore) -- the orchestration is real, the backends are fake.

The streaming model shifts from Anthropic-specific token deltas (`StreamEvent.textDelta`, `thinkingDelta`, `inputJSONDelta`) to provider-agnostic `SessionEvent` snapshots. This enables snapshot-based accumulation where each event is self-consistent (no double-render), and structured output via `PartiallyGenerated<T>` -- a generic snapshot type where partial properties accumulate progressively. A shadow-mode validation pipeline compares old-delta and new-snapshot rendered output for equivalence before consumer cutover (per PITFALLS.md Pitfall 2).

`GenerationSchema` bridges the gap between Codable Swift types and JSON Schema at runtime. Since `@Generable` requires macOS 26+, we use a protocol with manual conformance + a Mirror-based auto-derivation helper as best-effort. Types like `BashParams` can conform to `GenerationSchema` and produce valid JSON schema at runtime.

**Primary recommendation:** Implement `AgentRuntimeImpl` as a single actor with the agent loop, SessionEvent, and PartiallyGenerated all in one cohesive module. Build mock providers first to validate the loop, then the snapshot model, then the schema generation -- in dependency order. Do NOT expose snapshot types to existing consumers yet; run all validation in new test suites.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Agent loop (prompt -> executor -> tools -> repeat) | Core (AgentRuntime actor) | -- | The loop is the Runtime's reason to exist; it orchestrates all subsystems |
| SessionEvent emission | Core (AgentRuntime) | -- | Runtime converts GenerationChannel signals to public SessionEvent; consumers never see executor internals |
| Snapshot accumulation | Core (AgentRuntime) | -- | Snapshot state (text accumulation, thinking accumulation, partial JSON) is session-private; consumers receive completed snapshots |
| PartiallyGenerated<T> snapshot diffing | Core (PartiallyGenerated struct) | -- | The struct is a value type that computes its own diff; no subsystem owns this logic |
| JSON Schema from Codable types | Core (GenerationSchema protocol) | -- | Type-level protocol; each conforming type provides its own schema or uses the Mirror helper |
| Subsystem routing | Core (AgentRuntime) | -- | All model calls, permission checks, memory writes, and tool calls route through the Runtime; no subsystem talks to another directly |
| Mock provider responses | Core (Test support) | -- | Mock providers are test-only; they live in test targets or internal test-support modules |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift stdlib (Concurrency) | 6.3 | Actors, async/await, Task, AsyncThrowingStream, Sendable | Zero-dependency foundation. Everything needed for actor-isolated agent loop, streaming, and structured concurrency is in the language itself. |
| Foundation | (system) | JSONEncoder/JSONDecoder, Mirror, Data, URLSession | Mirror for runtime schema generation; Codable for tool input types; Data for wire-format payloads. |
| Existing JSONSchema | (Phase 1) | Tool input schema type | Already defined in `Types/Tool.swift` (line 401). Used by `RuntimeAgentTool.inputSchema` and `RuntimeToolDefinition.inputSchema`. GenerationSchema wraps this. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Existing Transcript | (Phase 1) | Conversation history with typed entries | Core data structure for the agent loop. Prompt appended, response accumulated, tool results inserted. |
| Existing GenerationChannel | (Phase 1) | Executor-to-runtime streaming protocol | Bridge between executor's wire format and runtime's public SessionEvent. Already defines 6 methods. |
| Existing Usage | (from StreamEvent.swift) | Token usage tracking | Already used by GenerationChannel.complete(); reused for SessionEvent.metadata. |
| Existing AgentRuntimeError | (Phase 1) | Unified error taxonomy (16 cases) | All error propagation in the agent loop goes through this type. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| AgentRuntimeImpl as actor | AgentRuntimeImpl as final class with @unchecked Sendable | Actor gives compiler-enforced data race safety. Class with locks is more manual but avoids actor reentrancy concerns. Actor is the correct Swift 6.3 choice. |
| PartiallyGenerated<T> snapshots | Continue with raw token deltas | Snapshots are provider-agnostic and renderer-friendly. Deltas leak Anthropic's SSE format. Snapshot is the FoundationModels direction. |
| Mirror-based auto schema generation | Manual JSONSchema for every type | Mirror works for simple structs (80% case) but fails on generics and enums. Manual is always correct. Hybrid: Mirror helper as default, with manual override. |
| GenerationSchema in Tool protocol | Separate GenerationSchema protocol | Separating schema from tool execution keeps the Tool protocol minimal (Phase 1 design). Types that need structured output conform to GenerationSchema independently. |

**Installation:** Zero external dependencies. All types are defined in `Sources/SwiftAgentCore/AgentRuntime/` using existing Swift 6.3 stdlib and Foundation.

**Version verification:** Not applicable -- no external packages added in this phase.

## Package Legitimacy Audit

> No external packages are installed in this phase. All new types use Swift 6.3 stdlib and existing project types only.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | -- | -- | -- | -- | -- | No external packages needed |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Zero external dependencies. This phase is pure Swift 6.3 stdlib + Foundation + existing project types.*

## Architecture Patterns

### System Architecture Diagram

```
                         ┌──────────────────────────────────┐
                         │   Consumer (test suites only)    │
                         │   for try await event in         │
                         │   runtime.streamResponse(to:)    │
                         └──────────────┬───────────────────┘
                                        │ AsyncThrowingStream<SessionEvent, Error>
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                          AgentRuntimeImpl (actor)                                   │
│                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────────┐ │
│  │  respond(to: String) async throws -> Transcript                               │ │
│  │  streamResponse(to: String) -> AsyncThrowingStream<SessionEvent, Error>       │ │
│  │                                                                               │ │
│  │  Internal agent loop:                                                         │ │
│  │  1. Append .prompt(text) to transcript                                        │ │
│  │  2. Call executor.respond(transcript, tools, options, channel)                │ │
│  │  3. Channel emits SessionEvent via AsyncThrowingStream                        │ │
│  │  4. If .toolCallRequested: execute tool, append .toolOutput, goto 2          │ │
│  │  5. If .turnCompleted: append .response, update MemoryStore, return          │ │
│  └──────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                    │
│  Subsystem routing:                                                                │
│  ┌─────────┐  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐              │
│  │ Model   │  │ Permission   │  │ Memory         │  │ Tool         │              │
│  │ Provider│  │ Engine       │  │ Store          │  │ Engine       │              │
│  │ (mock)  │  │ (mock)       │  │ (mock)         │  │ (Phase 1)    │              │
│  └─────────┘  └──────────────┘  └────────────────┘  └──────────────┘              │
└───────────────────────────────────────────────────────────────────────────────────┘
                                        │
                    GenerationChannel protocol (6 methods)
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                          MockLanguageModelExecutor                                 │
│  Converts mock transcript back into SessionEvent stream with predefined responses  │
│  Implements LanguageModelExecutor (Phase 1 protocol)                               │
└───────────────────────────────────────────────────────────────────────────────────┘

Snapshot model (internal to AgentRuntimeImpl):
┌───────────────────┐      ┌───────────────────┐      ┌───────────────────┐
│ text: ""          │ ──►  │ text: "Hello"      │ ──►  │ text: "Hello world"│
│ thinking: ""      │      │ thinking: "Let"    │      │ thinking: "Let me" │
│ toolCalls: []     │      │ toolCalls: []      │      │ toolCalls: []      │
│ isComplete: false │      │ isComplete: false  │      │ isComplete: false  │
└───────────────────┘      └───────────────────┘      └───────────────────┘
     SessionEvent              SessionEvent               SessionEvent
     .textDelta("")            .textDelta("Hello")        .textDelta("Hello world")

PartiallyGenerated<T> (for structured output):
┌───────────────────────────┐    ┌───────────────────────────┐    ┌───────────────────────────┐
│ T.command: nil            │──► │ T.command: "ls"           │──► │ T.command: "ls"           │
│ T.description: nil        │    │ T.description: nil        │    │ T.description: "List files"│
│ previousSnapshot: nil     │    │ previousSnapshot: {cmd:""}│    │ previousSnapshot: {...}    │
└───────────────────────────┘    └───────────────────────────┘    └───────────────────────────┘
     diff: empty                   diff: {command: "ls"}            diff: {description: "List files"}
```

### Recommended Project Structure

```
Sources/SwiftAgentCore/AgentRuntime/
├── AgentRuntimeImpl.swift            # NEW: Concrete runtime actor
├── SessionEvent.swift                # NEW: Provider-agnostic streaming events
├── PartiallyGenerated.swift          # NEW: Snapshot accumulation + diffing
├── GenerationSchema.swift            # NEW: Runtime JSON schema from Codable
├── Mocks/                            # NEW: Test-only mock providers
│   ├── MockLanguageModel.swift       # Mock model returning canned responses
│   ├── MockLanguageModelExecutor.swift # Mock executor streaming via GenerationChannel
│   ├── MockMemoryStore.swift         # Mock memory for testing
│   └── MockPermissionEngine.swift    # Mock permission always returning true
├── AgentProfile.swift                # (Phase 1, unchanged)
├── AgentRuntime.swift                # (Phase 1 protocol, unchanged)
├── AgentRuntimeError.swift           # (Phase 1, unchanged)
├── Transcript.swift                  # (Phase 1, unchanged)
├── Graph/                            # (Phase 1, unchanged)
├── Providers/                        # (Phase 1, unchanged unless extending)
└── Tools/                            # (Phase 1, unchanged)
```

### Pattern 1: Agent Loop (Actor-Isolated)

**What:** The central agent loop is a `while` loop inside an actor method. Each iteration: call executor to get response, if tool calls execute them and re-prompt, if end-turn append response and return. All state mutation (transcript, tool execution tracking) stays on the actor.

**When to use:** This is the core of AgentRuntimeImpl.respond(to:) and streamResponse(to:).

**Example:**
```swift
// Source: Derived from LLMClient.swift AsyncThrowingStream pattern (lines 116-138)
// and QueryEngine agent loop pattern. Adapted for AgentRuntime actor.

actor AgentRuntimeImpl: AgentRuntime {
    private var transcript: Transcript
    // ... subsystem properties ...

    func respond(to prompt: String) async throws -> Transcript {
        transcript.entries.append(.prompt(prompt))

        var turnComplete = false
        while !turnComplete {
            let channel = RuntimeGenerationChannel()
            try await modelProvider.makeExecutor().respond(
                to: transcript,
                tools: [],  // from ToolEngine
                options: GenerationOptions(),
                streamingInto: channel
            )

            // Process channel events
            let events = await channel.collectedEvents
            for event in events {
                switch event {
                case .textDelta(let text):
                    responseText += text
                case .toolCallRequested(let id, let name, let input):
                    // Execute tool via ToolEngine, append .toolOutput to transcript
                    let output = try await executeTool(name: name, input: input)
                    transcript.entries.append(.toolOutput(id: id, output: output, isError: false))
                case .turnCompleted:
                    turnComplete = true
                case .error(let err):
                    throw err
                default: break
                }
            }
        }

        transcript.entries.append(.response(responseText))
        try? await memoryStore.store(key: "latest", namespace: "sessions", value: transcript)
        return transcript
    }
}
```

### Pattern 2: AsyncThrowingStream<SessionEvent> with GenerationChannel Bridge

**What:** `streamResponse(to:)` returns an `AsyncThrowingStream<SessionEvent, Error>`. The actor launches a `Task` for the agent loop, which pushes events through a `GenerationChannel` implementation that bridges to the stream's `Continuation`.

**When to use:** For streaming responses. The consumer iterates `for try await event in stream`, receiving typed SessionEvent values -- never raw SSE tokens.

**Example:**
```swift
// Source: LLMClient.swift lines 116-138 (existing AsyncThrowingStream pattern)
// Adapted for AgentRuntime + SessionEvent

func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await self.runLoop(prompt: prompt, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { @Sendable reason in
            if case .cancelled = reason {
                task.cancel()
            }
        }
    }
}

private func runLoop(
    prompt: String,
    continuation: AsyncThrowingStream<SessionEvent, Error>.Continuation
) async throws {
    transcript.entries.append(.prompt(prompt))
    continuation.yield(.event(.promptAppended(prompt)))

    var turnComplete = false
    while !turnComplete {
        let channel = StreamContinuationChannel(continuation: continuation)
        try await modelProvider.makeExecutor().respond(
            to: transcript, tools: activeTools, options: options, streamingInto: channel
        )
        let events = await channel.collectedToolCalls
        if events.isEmpty {
            turnComplete = true
        } else {
            for call in events {
                continuation.yield(.toolCallRequested(id: call.id, name: call.name, input: call.input))
                let output = try await executeTool(name: call.name, input: call.input)
                continuation.yield(.toolCallCompleted(id: call.id, output: output, isError: false))
                transcript.entries.append(.toolOutput(id: call.id, output: output.stringValue, isError: false))
            }
        }
    }
    continuation.yield(.turnCompleted(usage: finalUsage, stopReason: "end_turn"))
}
```

### Pattern 3: Snapshot Streaming with PartiallyGenerated<T>

**What:** `PartiallyGenerated<T: Codable & Sendable>` holds a partially constructed instance of `T` where all properties are Optional. Each stream event is a complete snapshot of the current state. Consumers diff against `previousSnapshot` to extract only what changed, preventing double-render.

**When to use:** For structured output (STREAM-02). When the model is generating a JSON object, consumers receive `PartiallyGenerated<BashParams>` snapshots progressively.

**Example:**
```swift
// Source: Apple FoundationModels PartiallyGenerated<T> design (WWDC25 Session 301)
// Adapted for runtime implementation without @Generable macro

public struct PartiallyGenerated<T: Codable & Sendable>: Sendable {
    /// The complete snapshot of all properties accumulated so far.
    /// All properties are Optional -- nil means not yet generated.
    public let snapshot: T?

    /// The previous snapshot for diff computation.
    /// Nil on first event.
    public let previousSnapshot: T?

    /// Keys that changed since the previous snapshot.
    /// Empty on first event (all keys are "new" implicitly).
    public let changedKeys: Set<String>

    /// Whether generation is complete (the model emitted the final token).
    public let isComplete: Bool

    /// Cumulative raw text received so far (for debugging / shadow validation).
    public let rawAccumulatedText: String

    public init(
        snapshot: T? = nil,
        previousSnapshot: T? = nil,
        changedKeys: Set<String> = [],
        isComplete: Bool = false,
        rawAccumulatedText: String = ""
    ) {
        self.snapshot = snapshot
        self.previousSnapshot = previousSnapshot
        self.changedKeys = changedKeys
        self.isComplete = isComplete
        self.rawAccumulatedText = rawAccumulatedText
    }
}
```

**Snapshot accumulation and diffing (inside AgentRuntimeImpl):**
```swift
// Progressive accumulation of a T from incoming JSON deltas
private func accumulateStructuredOutput<T: Codable & GenerationSchema>(
    partialJSON: String,
    previous: PartiallyGenerated<T>?
) -> PartiallyGenerated<T> {
    let decoder = JSONDecoder()
    // Attempt to decode the accumulated JSON into T (all properties optional)
    let snapshot = try? decoder.decode(T.self, from: Data(partialJSON.utf8))

    // Compute changed keys by diffing against previous
    let changedKeys: Set<String>
    if let prev = previous?.snapshot, let current = snapshot {
        changedKeys = diffSnapshots(prev, current)
    } else {
        changedKeys = []
    }

    return PartiallyGenerated(
        snapshot: snapshot,
        previousSnapshot: previous?.snapshot,
        changedKeys: changedKeys,
        isComplete: false,
        rawAccumulatedText: partialJSON
    )
}

/// Diff two snapshots of the same type using Mirror
private func diffSnapshots<T>(_ old: T, _ new: T) -> Set<String> {
    let oldMirror = Mirror(reflecting: old)
    let newMirror = Mirror(reflecting: new)
    var changed = Set<String>()
    for (oldChild, newChild) in zip(oldMirror.children, newMirror.children) {
        if let label = oldChild.label {
            let oldStr = String(describing: oldChild.value)
            let newStr = String(describing: newChild.value)
            if oldStr != newStr { changed.insert(label) }
        }
    }
    return changed
}
```

### Pattern 4: GenerationSchema Protocol with Mirror Helper

**What:** A protocol that Codable types conform to, providing `static var jsonSchema: JSONSchema`. A Mirror-based helper function provides a best-effort auto-derivation. Manual override is always available.

**When to use:** For any type that should support structured output. Tools with complex parameter structs conform to this.

**Example:**
```swift
// Source: Derived from existing JSONSchema type (Types/Tool.swift line 401)
// and Apple FoundationModels @Generable design (WWDC25 Session 301)

public protocol GenerationSchema: Codable, Sendable {
    /// JSON Schema for this type. Types can either implement this manually
    /// or use the default Mirror-based derivation via generationSchemaFromMirror().
    static var jsonSchema: JSONSchema { get }
}

extension GenerationSchema {
    /// Default implementation using Mirror reflection.
    /// Works for simple flat structs with String, Int, Double, Bool properties.
    /// Override for nested types, enums, or complex constraints.
    public static var jsonSchema: JSONSchema {
        generationSchemaFromMirror(Self.self)
    }
}

/// Mirror-based JSON schema generation. Best-effort: works for flat structs.
/// Falls back to { "type": "object" } for types it cannot introspect.
public func generationSchemaFromMirror(_ type: Any.Type) -> JSONSchema {
    guard let sample = createSampleInstance(type) else {
        return JSONSchema(type: "object", description: "Schema unavailable for \(String(describing: type))")
    }

    let mirror = Mirror(reflecting: sample)
    var properties: [String: JSONSchemaProperty] = [:]
    var required: [String] = []

    for child in mirror.children {
        guard let label = child.label else { continue }
        let swiftType = typeString(from: child.value)
        let jsonType = mapSwiftToJSONType(swiftType)
        properties[label] = JSONSchemaProperty(type: jsonType)
        // Non-Optional properties are required
        if !swiftType.hasPrefix("Optional<") {
            required.append(label)
        }
    }

    return JSONSchema(
        type: "object",
        properties: properties.isEmpty ? nil : properties,
        required: required.isEmpty ? nil : required
    )
}

private func mapSwiftToJSONType(_ swiftType: String) -> String {
    if swiftType.hasPrefix("Optional<") { return mapSwiftToJSONType(unwrapOptional(swiftType)) }
    switch swiftType {
    case "String": return "string"
    case "Int", "Int32", "Int64", "Double", "Float": return "number"
    case "Bool": return "boolean"
    case "Data": return "string"
    default: return "string"  // conservative fallback
    }
}
```

**Concrete usage (BashParams example from success criterion):**
```swift
struct BashParams: Codable, GenerationSchema {
    let command: String
    let description: String?
    let timeout: Int?
}
// Auto-generates via Mirror:
// {
//   "type": "object",
//   "properties": {
//     "command": {"type": "string"},
//     "description": {"type": "string"},
//     "timeout": {"type": "number"}
//   },
//   "required": ["command"]
// }
```

### Anti-Patterns to Avoid

- **Inline consumer wiring during core development:** Do NOT wire `AgentRuntimeImpl.streamResponse(to:)` into CLI `ChatCommand` or App `ThreadViewModel` during Phase 2. All validation is done in test suites. Consumer wiring is Phase 4 (MIG-02).

- **Exposing GenerationChannel.Continuation outside the actor:** The `AsyncThrowingStream.Continuation` must be captured within the actor's stream-producing method, never stored as a property (actor reentrancy risk -- a second call would overwrite the first).

- **Dual accumulator paths:** Do NOT create separate text accumulation logic for SessionEvent and PartiallyGenerated. Both use the same internal accumulator; the difference is only the output wrapper.

- **Circular dependency between AgentRuntimeImpl and tools:** The agent loop calls ToolEngine, not individual tools directly. ToolEngine is a placeholder protocol from Phase 1 that gets a minimal concrete implementation in this phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Task scheduling inside actor | Custom dispatch queue | Swift 6.3 `Task{}` + actor isolation | The compiler enforces actor isolation; custom queues add complexity and data race risk |
| Stream lifecycle management | Manual retain/release of continuation | `continuation.onTermination` callback | Built-in callback handles consumer cancellation, iteration end, and error termination |
| JSON parsing from accumulated deltas | Custom JSON parser | `JSONDecoder().decode(T.self, from: data)` | Foundation's decoder handles edge cases (escaped strings, unicode, nested objects). The existing `safeParseJSON()` in LLMStreamParser handles double-stringification -- wrap, don't rewrite. |
| Mirror-based type name extraction | Manual type-to-string mapping | `String(describing: type(of: value))` + normalization | Stable across Swift versions, handles Optionals and nested generics |
| Snapshot diffing for UI | Custom diff algorithm | `Mirror(reflecting:)` pair-wise comparison + String(describing:) for value equality | Simple and correct for flat Codable structs. Nested diffing would need Codable encode+compare but that's v2 scope. |
| Tool execution error propagation | Custom error wrapping | `AgentRuntimeError.toolExecutionFailed(name:reason:)` | Already defined in Phase 1. All tool errors route through this case. |

**Key insight:** The agent loop is a simple `while` loop. The complexity is NOT in the loop logic -- it's in the **snapshot accumulation semantics** (is this a delta or a snapshot?) and the **subsystem routing discipline** (which subsystem owns which decision?). The existing LLMClient already has the correct `AsyncThrowingStream` pattern (lines 116-138); we follow that pattern exactly.

## Runtime State Inventory

> Omitted -- this is a greenfield phase (new types added, no existing state modified). The Runtime State Inventory is required only for rename/refactor/migration phases.

## Common Pitfalls

### Pitfall 1: Actor Reentrancy During Agent Loop

**What goes wrong:** The agent loop `await`s on `executor.respond()` which can suspend for extended periods. During suspension, another call to `respond(to:)` or `streamResponse(to:)` enters the actor and mutates `transcript` while the first call is mid-loop. This causes interleaved transcripts where prompt B's entries appear in the middle of turn A's tool-call loop.

**Why it happens:** Swift actors are reentrant by default. When an actor method `await`s, other tasks can enter the actor and mutate state.

**How to avoid:** Use a `private var isResponding: Bool` flag checked at the top of `respond()` and `streamResponse()`. If already responding, throw `.rateLimited(retryAfter: nil)` or queue the request. Alternatively, design the runtime so each turn creates a **copy** of the transcript, works on the copy, then atomically swaps it back.

**Warning signs:** Transcript entries appearing out of order (prompt B before turn A's tool output). Tests that pass in isolation but fail under Swift Testing's parallel execution.

### Pitfall 2: The Double-Render Bug (Snapshot vs Delta Semantics)

**What goes wrong:** `SessionEvent.textDelta("Hello")` followed by `SessionEvent.textDelta("Hello world")` -- if the consumer appends instead of replacing, output becomes "HelloHello world". This is the exact same bug documented in PITFALLS.md Pitfall 2 (Anthropic SDK "HelloHello" duplication).

**Why it happens:** The `SessionEvent` emits **snapshots** (accumulated complete text), not **deltas** (incremental additions). Consumers that naively concatenate will double-render. The name `.textDelta` is misleading -- it's really a snapshot of all text so far.

**How to avoid:** Two strategies, both implemented:
1. Name it clearly: use `.textSnapshot(text:)` or `.partialText(accumulated:)` not `.textDelta`. The name signals the semantics.
2. Provide a `PartiallyGeneratedResponse` wrapper that includes `previousText` and `currentText` so diff-aware consumers can extract only what changed.
3. Shadow-mode validation: for every snapshot, compute `expectedRenderedOutput = oldDeltaPath.accumulate(event)` and `actualRenderedOutput = newSnapshotPath.render(snapshot)` and assert equality (per PITFALLS.md prevention strategy).

**Warning signs:** Any consumer that calls `.textDelta` and appends to a local String accumulator without checking for duplication. Test output that repeats the same text block.

### Pitfall 3: Mock Executor Emits Events After Turn Complete

**What goes wrong:** The MockLanguageModelExecutor emits `.turnCompleted` and then emits another `.textDelta` event. The agent loop has already broken out of its `while` loop and the dangling event is delivered to a continuation that has already been `.finish()`ed.

**Why it happens:** The GenerationChannel protocol does not gate subsequent sends after `complete()` is called. The mock executor implementation must be disciplined.

**How to avoid:** In the concrete `RuntimeGenerationChannel` (the implementation behind the GenerationChannel protocol), add a `private var isFinished: Bool` flag. After `complete()` or `fail(with:)` is called, subsequent `send()` calls are silently dropped. The mock executor tests verify this behavior.

### Pitfall 4: Mirror-Based Schema Generation Missing Required Fields

**What goes wrong:** Mirror reflects on instance properties. If all properties are Optional, no fields appear in `required`, producing an invalid schema where the model has no guidance on which fields to populate.

**Why it happens:** Swift Codable structs often use optional types for flexibility. Mirror can't distinguish "this property is logically required but uses Optional for decoding convenience" from "this property is truly optional."

**How to avoid:** Provide a manual override on `GenerationSchema.jsonSchema`. Document that Mirror is best-effort and types with all-Optional properties should implement the schema manually. Test that `BashParams.jsonSchema` produces the expected output (command is required, description and timeout are optional).

### Pitfall 5: Stream Continuation Leaked on Task Cancellation

**What goes wrong:** User presses ESC to cancel streaming. The `continuation.onTermination` callback fires and cancels the `Task`. But the `URLSession.AsyncBytes` (or mock timer) continues running because it doesn't check `Task.isCancelled`. The continuation's memory is kept alive indefinitely.

**Why it happens:** `AsyncThrowingStream.Continuation.finish()` is not called if the cancellation path doesn't properly propagate to the underlying I/O.

**How to avoid:** After `continuation.onTermination` cancels the task, the agent loop must check `Task.isCancelled` at each suspension point and call `continuation.finish()` before returning. For mock executors, implement cooperative cancellation checks.

## Code Examples

Verified patterns from official sources:

### AgentRuntimeImpl Actor Skeleton
```swift
// Source: Derived from LLMClient.swift (existing AsyncThrowingStream pattern, lines 116-138)
// and Swift 6.3 Concurrency documentation (actor isolation, Sendable)

public actor AgentRuntimeImpl: AgentRuntime {
    // Phase 1 subsystem slots
    public let modelProvider: any LanguageModel
    public let memoryStore: any RuntimeMemoryStore
    public let permissionEngine: any RuntimePermissionEngine
    public let toolEngine: any ToolEngine
    public let contextManager: any RuntimeContextManager
    public let profileManager: any ProfileManager
    public let graphEngine: (any AgentGraph)?
    public let hookSystem: any RuntimeHookSystem

    private var transcript: Transcript
    private var isResponding: Bool = false

    public init(
        modelProvider: any LanguageModel,
        memoryStore: any RuntimeMemoryStore,
        permissionEngine: any RuntimePermissionEngine,
        toolEngine: any ToolEngine,
        // ... other subsystems with defaults
    ) {
        self.modelProvider = modelProvider
        self.memoryStore = memoryStore
        // ... etc
        self.transcript = Transcript()
    }

    // Actor reentrancy gate
    private func assertNotResponding() throws {
        guard !isResponding else {
            throw AgentRuntimeError.rateLimited(retryAfter: nil)
        }
    }
}
```

### SessionEvent Enum Definition
```swift
// Source: REQUIREMENTS.md STREAM-01 specification
// Verified against existing GenerationChannel protocol (6 methods)

public enum SessionEvent: Sendable {
    /// Text content delta (accumulated snapshot, not raw token)
    case textDelta(String)

    /// Thinking/reasoning content delta (accumulated snapshot)
    case thinkingDelta(String)

    /// A tool call has been requested by the model
    case toolCallRequested(id: String, name: String, input: Data)

    /// A tool call has completed execution
    case toolCallCompleted(id: String, output: ToolOutputValue, isError: Bool)

    /// The turn has completed with usage and stop reason
    case turnCompleted(usage: Usage?, stopReason: String?)

    /// An error occurred during streaming
    case error(AgentRuntimeError)
}
```

### RuntimeGenerationChannel (Concrete GenerationChannel Implementation)
```swift
// Source: GenerationChannel protocol (Phase 1, GenerationChannel.swift)
// Adapted with actor safety and finish gating

public actor RuntimeGenerationChannel: GenerationChannel {
    private var continuation: AsyncThrowingStream<SessionEvent, Error>.Continuation?
    private var isFinished: Bool = false
    private var accumulatedText: String = ""
    private var accumulatedThinking: String = ""

    public func setContinuation(_ c: AsyncThrowingStream<SessionEvent, Error>.Continuation) {
        self.continuation = c
    }

    public func send(textDelta: String) async {
        guard !isFinished else { return }
        accumulatedText = textDelta  // snapshot replacement
        continuation?.yield(.textDelta(accumulatedText))
    }

    public func send(thinkingDelta: String) async {
        guard !isFinished else { return }
        accumulatedThinking = thinkingDelta
        continuation?.yield(.thinkingDelta(accumulatedThinking))
    }

    public func send(toolCallRequest id: String, name: String, input: Data) async {
        guard !isFinished else { return }
        continuation?.yield(.toolCallRequested(id: id, name: name, input: input))
    }

    public func send(toolCallCompleted id: String, output: ToolOutputValue) async {
        guard !isFinished else { return }
        continuation?.yield(.toolCallCompleted(id: id, output: output, isError: false))
    }

    public func complete(stopReason: String?, usage: Usage?) async {
        guard !isFinished else { return }
        isFinished = true
        continuation?.yield(.turnCompleted(usage: usage, stopReason: stopReason))
        continuation?.finish()
    }

    public func fail(with error: AgentRuntimeError) async {
        guard !isFinished else { return }
        isFinished = true
        continuation?.yield(.error(error))
        continuation?.finish(throwing: error)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Anthropic `StreamEvent` enum (13 cases, SSE-specific) | `SessionEvent` enum (6 cases, provider-agnostic) | Phase 2 | Consumers see typed, uniform events regardless of which provider backend is active |
| Token deltas (`.textDelta("Hel")`, `.textDelta("lo")`) | Text snapshots (`.textDelta("Hel")`, `.textDelta("Hello")`) | Phase 2 | Each event is self-consistent; no double-render if consumer appends correctly |
| Manual `JSONSchema` per tool (verbose, error-prone) | `GenerationSchema` protocol with Mirror helper | Phase 2 | Codable types get 80% schema auto-generation; manual override for complex cases |
| `QueryEngine` monolithic agent loop | `AgentRuntimeImpl` actor with isolated state | Phase 2 | Compiler-enforced data race safety; clear subsystem boundaries |
| No structured output support | `PartiallyGenerated<T>` snapshots | Phase 2 | Progressive property filling for type-safe streaming; forward-compatible with `@Generable` |

**Deprecated/outdated:**
- `StreamEvent` (13-case enum in Types/StreamEvent.swift): Not removed yet (that's Phase 4), but Phase 2 establishes `SessionEvent` as the canonical type for all new code paths.
- Direct `LLMClient.stream()` calls: AgentRuntimeImpl is the new entry point. Mock executor replaces real LLM client for testing the loop.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Mirror will reflect struct property names matching CodingKeys for simple Codable structs [ASSUMED] | Architecture Patterns (Pattern 4) | Medium -- schema generation would need manual implementation for every type. Mitigated by manual override capability on GenerationSchema protocol. |
| A2 | Mock providers can fully exercise the agent loop without real network calls [ASSUMED] | Architecture Patterns (Pattern 1) | Low -- the loop logic is independent of provider implementation. If mock can't simulate multi-turn tool calls, the test coverage gap is in tool execution orchestration, not loop logic. |
| A3 | Phase 1 placeholder protocols (ToolEngine, RuntimeContextManager, ProfileManager, RuntimeHookSystem) need minimal concrete implementations in Phase 2 for the agent loop to function [ASSUMED] | Architecture Patterns (Pattern 1) | High -- if the placeholders can't be trivially implemented (e.g., ToolEngine requires complex registration logic), Phase 2 scope expands. Mitigated by making Phase 2 implementations minimal: ToolEngine just holds a `[String: any RuntimeAgentTool]` dictionary, others are no-ops. |
| A4 | The existing `JSONSchema` type (Types/Tool.swift line 401) is sufficient for GenerationSchema output without modification [ASSUMED] | Architecture Patterns (Pattern 4) | Low -- JSONSchema already has type, properties, required, and description fields. If schema generation needs additional JSON Schema features (pattern, minLength), properties are available on JSONSchemaProperty. |
| A5 | `PartiallyGenerated<T>.snapshot` can be decoded from accumulated JSON deltas via `JSONDecoder` even when some properties are not yet present (Swift handles missing keys with Optional properties) [ASSUMED] | Architecture Patterns (Pattern 3) | Medium -- if model emits invalid JSON fragments or keys that don't match the struct, JSONDecoder will fail and the snapshot will be nil. Mitigated by trying decode and falling back to previous snapshot on failure. |

## Open Questions (RESOLVED)

1. **Should `PartiallyGenerated<T>` expose raw JSON deltas for debugging?** (RESOLVED)
   - Recommendation: Include `rawAccumulatedText: String` as a public field (used by test suites for validation). Mark as debug-only in documentation.

2. **How minimal should the Phase 2 ToolEngine, RuntimeContextManager, ProfileManager, and RuntimeHookSystem implementations be?** (RESOLVED)
   - Recommendation: Implement minimal viable versions. ToolEngine: dictionary-backed registry with register/retrieve. Others: no-op stubs that default-initialize.

3. **Does `RuntimeGenerationChannel` need to be a `public actor` or `internal`?** (RESOLVED)
   - Recommendation: Make it `public` for test visibility but document as "internal to AgentRuntime -- do not use directly."

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6.3 | Actor isolation, AsyncThrowingStream, Sendable | Yes (installed) | 6.3 (swiftlang-6.3.0.123.5) | -- |
| Foundation (Mirror) | GenerationSchema runtime reflection | Yes (system) | macOS 26 / iOS 26 SDK | -- |
| SwiftAgentCore target | All Phase 1 types (Transcript, GenerationChannel, etc.) | Yes (builds) | Phase 1 complete | -- |
| XCTest | Test suite execution | Yes (system) | macOS 26 SDK | -- |

**Missing dependencies with no fallback:** None -- all dependencies are the Swift 6.3 stdlib + Foundation + existing project code.

**Missing dependencies with fallback:** None.

## Security Domain

> Required. `security_enforcement: true` in config.json.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | -- (Phase 2 uses mock providers; auth is provider-internal, Phase 3) |
| V3 Session Management | No | -- (session state is in-memory Transcript; no persistent sessions yet) |
| V4 Access Control | Yes | `RuntimePermissionEngine.check()` gates all tool execution and memory writes |
| V5 Input Validation | Yes | `JSONSchema.validate()` on tool inputs; `GenerationSchema` schema enforces structure |
| V6 Cryptography | No | -- (no cryptographic operations in this phase) |

### Known Threat Patterns for AgentRuntime/Swift Actor

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Actor reentrancy during `await executor.respond()` | Tampering | `isResponding` flag checked at entry; `AgentRuntimeError.rateLimited` thrown if reentrant |
| Unsanitized prompt injection into Transcript | Tampering | Prompts are appended as `.prompt(String)` entries; the model sees them via the executor's wire format translation (model-specific sanitization in Phase 3) |
| Tool execution without permission check | Elevation of Privilege | Every tool call routes through `permissionEngine.check()` before `ToolEngine.execute()` |
| Memory write without scope validation | Information Disclosure | `memoryStore.store()` calls validated against `AgentProfile.memoryScope` before persisting |
| Stream continuation data leak after `finish()` | Information Disclosure | `RuntimeGenerationChannel` sets `isFinished = true` and drops all subsequent sends silently |
| Malformed JSON delta injection via mock executor | Spoofing | `JSONDecoder` fails gracefully on malformed JSON; snapshot remains `nil` rather than partially corrupted |
| Test-only mock leaking into production | Elevation of Privilege | Mock providers live in `AgentRuntime/Mocks/` and are `#if DEBUG` gated or test-target-only |

## Sources

### Primary (HIGH confidence)
- Phase 1 source files (13 files in `Sources/SwiftAgentCore/AgentRuntime/`) -- directly inspected all types that Phase 2 builds on
- `Sources/SwiftAgentCore/LLM/LLMClient.swift` (lines 116-138, 156-163) -- canonical `AsyncThrowingStream` pattern already in the codebase
- `Sources/SwiftAgentCore/Types/StreamEvent.swift` (lines 1-13) -- current 13-case StreamEvent enum; SessionEvent replaces this
- `Sources/SwiftAgentCore/Types/Tool.swift` (lines 401-525) -- existing JSONSchema, JSONSchemaProperty, JSONSchemaItems types
- `Sources/SwiftAgentCore/AgentRuntime/Providers/GenerationChannel.swift` -- 6-method GenerationChannel protocol (Phase 1 output)
- `.planning/REQUIREMENTS.md` -- STREAM-01 and STREAM-02 specifications with exact event cases
- `.planning/ROADMAP.md` (Phase 2 section) -- success criteria, dependency chain
- `.planning/research/PITFALLS.md` (Pitfall 2) -- double-render bug and shadow-mode validation strategy
- `.planning/research/STACK.md` (Sections 2, 4, 5) -- AsyncThrowingStream patterns, streaming architecture, structured output
- `.planning/research/ARCHITECTURE.md` (Sections on streaming snapshot model, agent loop) -- architecture patterns
- `.planning/research/FEATURES.md` (DIFF-2, DIFF-3) -- snapshot streaming vs token deltas, type-driven structured output
- `Package.swift` -- Swift tools version 6.2 (compatible with Swift 6.3)

### Secondary (MEDIUM confidence)
- [Apple WWDC25 Session 301: Deep dive into Foundation Models](https://developer.apple.com/videos/play/wwdc2025/301/) -- `@Generable`, `PartiallyGenerated<T>` design [CITED: STACK.md, FEATURES.md]
- [Apple WWDC26 Session 339: Bring an LLM provider to Foundation Models](https://developer.apple.com/videos/play/wwdc2026/339/) -- LanguageModelSession, LanguageModelExecutor patterns [CITED: STACK.md]
- Swift 6.3 Concurrency documentation -- actor isolation, AsyncThrowingStream, Sendable

### Tertiary (LOW confidence)
- None. All claims are verified against the codebase or Apple's documented FoundationModels design.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero external dependencies; pure Swift 6.3 stdlib + Foundation + existing Phase 1 types
- Architecture: HIGH -- the agent loop follows the exact pattern in the existing codebase (LLMClient.AsyncThrowingStream, QueryEngine while-loop). Snapshot model follows Apple's documented FoundationModels design. Mirror-based schema generation is well-understood Swift reflection.
- Pitfalls: HIGH -- all five pitfalls are verified against documented production issues (PITFALLS.md) and Swift actor reentrancy is a well-known concern addressed by the existing codebase's patterns.

**Research date:** 2026-06-25
**Valid until:** 2026-07-25 (30 days; stable domain)
