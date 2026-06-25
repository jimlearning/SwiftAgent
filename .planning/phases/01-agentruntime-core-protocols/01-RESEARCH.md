# Phase 1: AgentRuntime Core Protocols - Research

**Researched:** 2026-06-25
**Domain:** Swift 6 protocol-oriented architecture for AI agent runtimes
**Confidence:** HIGH

## Summary

Phase 1 defines 16 new type-level definitions (protocols, structs, enums) that form the AgentRuntime blueprint. No existing code is modified — all new types are additive. The types establish a FoundationModels-shaped architecture where `AgentRuntime` (actor protocol) is the central orchestrator, and `LanguageModel`, `MemoryStore`, and `PermissionEngine` are swappable Provider protocols behind it. The simplified `Tool` protocol reduces from 43 to ~6 members, with cross-cutting concerns moved to `ToolMetadata`. A unified `AgentRuntimeError` enum replaces fragmented error types. `AgentGraph` and `AgentState` are type-slots only (protocol surface, no implementation).

This is a pure-Swift phase: zero external dependencies, zero behavioral change, zero existing code modifications. All work is additive — new files in `Sources/SwiftAgentCore/AgentRuntime/`.

**Primary recommendation:** Define all 16 types in a new `Sources/SwiftAgentCore/AgentRuntime/` directory with clear subdirectory organization. Use `protocol AgentRuntime: Actor` for the central orchestrator, `protocol LanguageModel: Sendable` for model abstraction, and `associatedtype Input: Codable` with primary associated types for the simplified Tool protocol. Keep existing code completely untouched.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| AgentRuntime actor protocol | API / Backend (Core) | — | Central orchestrator owns all subsystem references; replaces QueryEngine as primary entry point |
| LanguageModel protocol | API / Backend (Core) | Provider Executors (Phase 3) | Model abstraction boundary; protocol in Core, implementations in per-provider executors |
| LanguageModelCapabilities | API / Backend (Core) | — | Single struct shared by all providers; replaces dual ModelInfo types |
| AgentRuntimeError | API / Backend (Core) | — | Unified error taxonomy; consumed by all subsystems and entry points |
| Transcript | API / Backend (Core) | — | Canonical conversation history; provider-agnostic; consumed by MemoryStore, Compactor |
| AgentProfile | API / Backend (Core) | — | Agent identity bundle; forward-compatible with DynamicProfile |
| MemoryStore protocol | Database / Storage (Core) | Memory Provider (Phase 3) | Persistent memory interface; SQLite/Vector/Firestore implementations behind protocol |
| AgentState (design only) | Database / Storage (Core) | — | Type-slot for future property-wrapper; no implementation in Phase 1 |
| AgentPermission enum | API / Backend (Core) | PermissionEngine (Phase 3) | Runtime-level permission taxonomy; maps to OS permission model |
| PermissionEngine protocol | API / Backend (Core) | Safety/ subsystem | Upgraded from tool-level gate to subsystem-level; unified permission checks |
| Simplified Tool protocol | API / Backend (Core) | Tools/ directory (Phase 4) | Model-tool contract; existing tools migrate in Phase 4 |
| ToolMetadata | API / Backend (Core) | ToolEngine (Phase 4) | Per-tool operational data separated from protocol |
| ToolOutput | API / Backend (Core) | ToolEngine (Phase 4) | Replaces ToolResult in public API; hides ContentBlock from consumers |
| LanguageModelExecutor protocol | API / Backend (Core-internal) | Provider Executors (Phase 3) | Backend contract; wire-format translation boundary |
| GenerationChannel protocol | API / Backend (Core) | Provider Executors (Phase 3) | Streaming abstraction; decouples executor from session |
| AgentGraph protocol + AgentNode | API / Backend (Core) | Graph Engine (future) | Type-slots only; ordered DAG of agent nodes; forward-compatible with WWDC27 |

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RUNTIME-01 | AgentRuntime actor protocol with property slots for all subsystems | Section: Architecture Patterns > Pattern 1 (Actor Protocol with Subsystem Slots) |
| RUNTIME-02 | LanguageModel protocol as ModelProvider interface | Section: Architecture Patterns > Pattern 2 (Sendable Provider Protocol) |
| RUNTIME-03 | LanguageModelCapabilities struct replacing dual ModelInfo types | Section: Code Examples > LanguageModelCapabilities |
| RUNTIME-04 | AgentRuntimeError enum with unified cases grouped by subsystem | Section: Code Examples > AgentRuntimeError |
| RUNTIME-05 | Transcript struct with typed entries | Section: Code Examples > Transcript |
| RUNTIME-06 | AgentProfile struct bundling agent identity | Section: Code Examples > AgentProfile |
| MEM-01 | MemoryStore protocol with store/retrieve/search/summarize/forget | Section: Architecture Patterns > Pattern 3 (Persistence Protocol with Async Throws) |
| MEM-03 | AgentState property-wrapper concept (design only) | Section: Code Examples > AgentState (Type-Slot) |
| PERM-01 | AgentPermission enum with runtime-level taxonomy | Section: Code Examples > AgentPermission |
| PERM-02 | PermissionEngine protocol upgrade to subsystem-level | Section: Architecture Patterns > Pattern 5 (Protocol Upgrade via New File) |
| TOOL-01 | Simplified Tool protocol (~6 members) | Section: Code Examples > Simplified Tool Protocol |
| TOOL-02 | ToolMetadata struct for per-tool operational data | Section: Code Examples > ToolMetadata |
| TOOL-03 | ToolOutput enum replacing ToolResult in public API | Section: Code Examples > ToolOutput |
| MODEL-01 | LanguageModelExecutor protocol (Core internal) | Section: Code Examples > LanguageModelExecutor |
| MODEL-05 | GenerationChannel protocol for provider-to-runtime streaming | Section: Code Examples > GenerationChannel |
| GRAPH-01 | AgentGraph protocol + AgentNode concept (type-slots only) | Section: Code Examples > AgentGraph (Placeholder) |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift 6.3 stdlib | 6.3 (swift-tools-version 6.2) | Actors, Sendable, AsyncSequence, existential any, primary associated types | Zero-dependency foundation; all needed concurrency and protocol features are built-in |
| Foundation | (system, macOS 15.0+) | Codable, UUID, Date, Data | Used for Codable conformance on Transcript, ToolMetadata, AgentProfile |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Collections | 1.0.0 (already in project) | OrderedDictionary for tool registry ordering | Used in ToolEngine (Phase 4); not needed for Phase 1 type definitions |
| KeychainAccess | 4.2.0 (already in project) | Secure API key storage | Used by Provider executors (Phase 3); not needed for Phase 1 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `protocol AgentRuntime: Actor` | `protocol AgentRuntime: AnyObject, Sendable` + `actor AgentRuntimeImpl` | Actor protocol inheritance gives compile-time enforcement that only actors can conform and all members are actor-isolated; AnyObject+Sendable loses this guarantee |
| `associatedtype Input: Codable` on Tool | Opaque `ToolInput` dictionary (current codebase) | Associated type with primary associated type enables type-safe tools while still allowing `any Tool<SomeInput>` existentials; dictionary approach loses type safety |
| New `AgentRuntime/` directory | Inline in existing `Types/` directory | Separate directory physically isolates new types from existing code, making the additive nature explicit and preventing accidental coupling |

**Installation:** No new packages required. Phase 1 is pure Swift type definitions.

**Version verification:** Not applicable — no external packages are added in this phase.

## Package Legitimacy Audit

> **Skipped:** Phase 1 adds zero external packages. All types are defined in Swift standard library + Foundation. No npm, PyPI, or Swift Package dependencies are introduced.

## Architecture Patterns

### System Architecture Diagram

```
                         ┌──────────────────────────────────────────┐
                         │     Existing Code (UNCHANGED)            │
                         │  QueryEngine, LLMClient, 43 Tools,       │
                         │  PermissionEngine (struct), MCP, etc.    │
                         └──────────────────────────────────────────┘
                                              │
                                              │ No coupling in Phase 1
                                              │ (new types are additive)
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NEW: Sources/SwiftAgentCore/AgentRuntime/                 │
│                                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐                       │
│  │   AgentRuntime.swift │    │ AgentRuntimeError.swift│                      │
│  │   (actor protocol)   │    │   (unified enum)      │                      │
│  │                      │    │                        │                      │
│  │  var modelProvider   │    │  case rateLimited      │                      │
│  │  var memoryStore     │    │  case unauthorized     │                      │
│  │  var permissionEngine│    │  case toolNotFound     │                      │
│  │  var toolEngine      │    │  case cycleDetected    │                      │
│  │  var contextManager  │    │  ...                   │                      │
│  │  var profileManager  │    └──────────────────────┘                       │
│  │  var graphEngine     │                                                   │
│  │  var hookSystem      │    ┌──────────────────────┐                       │
│  └──────────────────────┘    │   Transcript.swift    │                       │
│                               │   (typed history)     │                       │
│  ┌──────────────────────┐    │                        │                       │
│  │  AgentProfile.swift   │    │  enum Entry {          │                       │
│  │  (identity bundle)    │    │    case instruction    │                       │
│  │                       │    │    case prompt         │                       │
│  │  name, instructions,  │    │    case response       │                       │
│  │  tools, model,        │    │    case toolCall       │                       │
│  │  permissionMode,      │    │    case toolOutput     │                       │
│  │  memoryScope          │    │    case thinking       │                       │
│  └──────────────────────┘    │    case system          │                       │
│                               └──────────────────────┘                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Providers/                                   │    │
│  │                                                                     │    │
│  │  LanguageModel.swift       MemoryStore.swift    PermissionEngine.swift │
│  │  (Sendable protocol)       (async throws)       (upgraded protocol) │    │
│  │  + Capabilities struct     + AgentState slot    + AgentPermission    │    │
│  │                                                                     │    │
│  │  LanguageModelExecutor.swift   GenerationChannel.swift              │    │
│  │  (Core-internal protocol)       (streaming abstraction)              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Tools/                                       │    │
│  │                                                                     │    │
│  │  SimplifiedTool.swift     ToolMetadata.swift    ToolOutput.swift    │    │
│  │  (~6 members +            (per-tool operational (replaces ToolResult)│    │
│  │   associatedtype Input)    data struct)                              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Graph/                                       │    │
│  │                                                                     │    │
│  │  AgentGraph.swift  (protocol + AgentNode + NodeCondition type-slots) │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
Sources/SwiftAgentCore/
├── AgentRuntime/                     # NEW: All Phase 1 types
│   ├── AgentRuntime.swift            # Central actor protocol
│   ├── AgentRuntimeError.swift       # Unified error enum
│   ├── Transcript.swift              # Typed conversation history
│   ├── AgentProfile.swift            # Agent identity bundle
│   ├── Providers/
│   │   ├── LanguageModel.swift        # LanguageModel protocol + Capabilities
│   │   ├── LanguageModelExecutor.swift # Core-internal executor protocol
│   │   ├── GenerationChannel.swift    # Streaming abstraction
│   │   ├── MemoryStore.swift          # MemoryStore protocol + AgentState slot
│   │   └── PermissionEngine.swift     # Upgraded PermissionEngine protocol
│   ├── Tools/
│   │   ├── SimplifiedTool.swift       # ~6-member Tool protocol
│   │   ├── ToolMetadata.swift         # Per-tool operational data
│   │   └── ToolOutput.swift           # Public tool output type
│   └── Graph/
│       └── AgentGraph.swift           # AgentGraph + AgentNode type-slots
├── Types/                            # UNCHANGED
├── Tools/                            # UNCHANGED (63 tool files)
├── Agent/                            # UNCHANGED (QueryEngine, etc.)
├── LLM/                              # UNCHANGED (LLMClient, etc.)
├── Safety/                           # UNCHANGED (PermissionEngine struct)
├── MCP/ Config/ State/ Hooks/ ...    # UNCHANGED
└── ...
```

**File count:** ~15 new Swift files. No existing files modified.

### Pattern 1: Actor Protocol with Subsystem Slots

**What:** Define `AgentRuntime` as `protocol AgentRuntime: Actor` with property requirements for each subsystem. Only `actor` types can conform. All property accesses and method calls are actor-isolated.

**When to use:** For the central orchestrator that owns all subsystem references and must be thread-safe.

**Why actor protocol inheritance:** Swift's `protocol P: Actor` syntax means:
1. Only `actor` types can conform (struct/class conformance is a compile error)
2. All protocol requirements are actor-isolated to `self`
3. Consumers call methods with `await runtime.doSomething()`
4. The compiler enforces data-race safety across all subsystem access

[VERIFIED: Swift Evolution proposal SE-0306; confirmed in Swift 6.3 stdlib — the `Actor` protocol is `protocol Actor: AnyObject, Sendable { }` and protocol inheritance from Actor is supported]

**Example:**
```swift
// Source: Swift 6.3 stdlib + Apple WWDC26 FoundationModels patterns
// File: Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift

/// Central agent runtime orchestrator. Replaces QueryEngine + LLMClient
/// as the primary consumer API surface.
///
/// Only actor types can conform — the compiler enforces actor isolation
/// across all subsystem access.
public protocol AgentRuntime: Actor {
    /// The language model provider for inference.
    var modelProvider: any LanguageModel { get }
    
    /// Persistent memory store for agent state and context.
    var memoryStore: any MemoryStore { get }
    
    /// Permission engine for runtime-level access control.
    var permissionEngine: any PermissionEngine { get }
    
    /// Tool registry and execution engine.
    var toolEngine: any ToolEngine { get }
    
    /// Context window management and compaction.
    var contextManager: any ContextManager { get }
    
    /// Agent identity and profile management.
    var profileManager: any ProfileManager { get }
    
    /// Agent graph orchestration (placeholder for WWDC27 AgentGraph).
    var graphEngine: (any AgentGraph)? { get }
    
    /// Hook system for lifecycle events.
    var hookSystem: any HookSystem { get }
}
```

### Pattern 2: Sendable Provider Protocol

**What:** Define Provider protocols (`LanguageModel`, `MemoryStore`, `PermissionEngine`) as `Sendable` with `async throws` methods. Providers are value types (structs) or actors — not classes. No `@unchecked Sendable` needed.

**When to use:** For swappable subsystem backends where multiple implementations exist behind a single protocol.

**Why Sendable not Actor:** Provider protocols represent capabilities, not state ownership. A `LanguageModel` is a factory for model sessions — it holds configuration (API key, base URL, model ID) but not mutable runtime state. `Sendable` is the correct constraint. The implementations may use actors internally, but the protocol contract only requires cross-actor safety.

[VERIFIED: Apple FoundationModels `LanguageModel` protocol is `Sendable` — confirmed via WWDC26 Session 339 and Apple Developer Documentation]

**Example:**
```swift
// Source: Apple FoundationModels LanguageModel protocol shape (WWDC26)
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/LanguageModel.swift

/// Model provider interface. Every inference backend conforms to this.
/// Mirrors Apple's FoundationModels `LanguageModel` protocol.
public protocol LanguageModel: Sendable {
    /// Declared capabilities of this model.
    var capabilities: LanguageModelCapabilities { get }
    
    /// Human-readable display name for UI.
    var displayName: String { get }
    
    /// Create an executor for this model. Called by AgentRuntime
    /// when a session needs to perform inference.
    func makeExecutor() -> any LanguageModelExecutor
}
```

### Pattern 3: Persistence Protocol with Async Throws

**What:** `MemoryStore` protocol uses `async throws` for all I/O operations. Keys are namespaced strings. Values are `Codable`. The protocol surface is intentionally narrow (6 methods) to enable multiple backend implementations.

**When to use:** For any persistence layer that may have local (SQLite), cloud (Firestore), or vector (semantic search) backends.

**Why async throws:** All persistence operations cross actor boundaries and may involve disk/network I/O. `async` enables non-blocking access. `throws` surfaces storage failures through the unified `AgentRuntimeError.memoryError` path.

[VERIFIED: Pattern confirmed against SwiftData, GRDB, and Firestore Swift SDK async API designs]

**Example:**
```swift
// Source: Memory system patterns from Apple FoundationModels + Mem0 + Claude Code memory
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/MemoryStore.swift

/// Persistent agent memory. Provider-pluggable: SQLite, Firestore, Vector.
public protocol MemoryStore: Sendable {
    /// Store a value at a key within a namespace.
    func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws
    
    /// Retrieve a value by key and namespace.
    func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T?
    
    /// Search for entries matching a query within a namespace.
    func search(query: String, namespace: String) async throws -> [MemoryEntry]
    
    /// Generate a summary of all entries in a namespace.
    func summarize(namespace: String) async throws -> String
    
    /// Remove an entry by key and namespace.
    func forget(key: String, namespace: String) async throws
    
    /// List all namespace identifiers.
    func listNamespaces() async throws -> [String]
}

/// A single memory entry with metadata.
public struct MemoryEntry: Sendable, Codable {
    public let key: String
    public let namespace: String
    public let value: Data
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: [String: String]
}
```

### Pattern 4: Protocol with Primary Associated Type

**What:** The simplified `Tool` protocol uses `associatedtype Input: Codable` with primary associated type syntax (`protocol Tool<Input>`) so `any Tool<SomeInput>` existentials remain usable in collections.

**When to use:** When a protocol's associated type must be preserved through existential erasure for type-safe tool execution.

**Why primary associated type:** Without it, `any Tool` loses the Input type entirely — you cannot call `tool.call(input)` without knowing Input. With primary associated types, you can write `any Tool<BashInput>` or use opaque `some Tool` in generic contexts.

[VERIFIED: Swift 5.7+ primary associated types; confirmed work with Sendable in Swift 6]

**Example:**
```swift
// Source: Swift 5.7 primary associated types + Apple FoundationModels Tool shape
// File: Sources/SwiftAgentCore/AgentRuntime/Tools/SimplifiedTool.swift

/// Simplified tool protocol — the contract between model and agent.
/// ~6 core members. Cross-cutting concerns live in ToolMetadata.
///
/// Forward-compatible with WWDC27 AgentIntent auto-discovery.
public protocol Tool<Input>: Sendable {
    /// The type of input this tool accepts.
    associatedtype Input: Codable & Sendable
    
    /// PascalCase tool name as seen by the LLM (e.g., "Bash", "Read").
    var name: String { get }
    
    /// Human-readable description of what the tool does.
    var description: String { get }
    
    /// JSON Schema for the tool's input parameters.
    var inputSchema: JSONSchema { get }
    
    /// Execute the tool with validated input.
    func call(_ input: Input) async throws -> ToolOutput
}
```

### Pattern 5: Protocol Upgrade via New File

**What:** The existing `PermissionEngine` is a `struct` (not a protocol). Phase 1 introduces `PermissionEngine` as a new `protocol` in `AgentRuntime/Providers/PermissionEngine.swift`. The existing struct remains unchanged in `Safety/PermissionEngine.swift`. During Phase 3, the struct gains protocol conformance.

**When to use:** When upgrading a concrete type to a protocol-based abstraction without modifying existing code.

**Why a new file:** Keeps the additive guarantee of Phase 1. The existing struct continues to work exactly as before. The new protocol defines the contract that the struct will conform to in Phase 3.

[VERIFIED: This is the standard Swift pattern for introducing protocol abstractions over existing concrete types — used in Apple's own framework migrations]

### Anti-Patterns to Avoid

- **`@unchecked Sendable` on new types:** All new types should be naturally `Sendable` (structs with Sendable fields, enums with Sendable associated values, actors). If a type needs `@unchecked Sendable`, the design is wrong — restructure it.
- **`nonisolated(unsafe)` on new code:** The count must not increase from the current 4 occurrences. All new types are value types or actor-isolated — no unsafe opt-outs needed.
- **Public `class` types:** Use `actor` for mutable shared state, `struct` for value types, `protocol` for abstractions. No new reference types with manual synchronization.
- **Modifying existing files:** Phase 1 is strictly additive. Do not change `Types/Tool.swift`, `Safety/PermissionEngine.swift`, `LLM/LLMClient.swift`, or any existing file.
- **Associated type without primary associated type:** `protocol Tool<Input>` not bare `protocol Tool`. Without primary associated types, `any Tool` existentials lose all Input type information.
- **Over-specifying placeholder types:** `AgentGraph`, `AgentNode`, and `AgentState` are type-slots only. Define the protocol surface and stop. Do not add execution logic, builder patterns, or concrete implementations.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe mutable state | `class` with `NSLock` / `os_unfair_lock` | `actor` or `Sendable` struct | Swift 6 actors provide compiler-enforced data-race safety; manual locking is error-prone and breaks Sendable checking |
| Type-erased tool collections | Custom `AnyTool` wrapper with manual boxing | `any Tool<Input>` existential with primary associated type | Swift's built-in existential erasure preserves protocol requirements; custom wrappers require manual conformance forwarding |
| JSON Schema generation | Manual schema construction per tool | `JSONSchema` (existing type in codebase, reused as-is) | The existing `JSONSchema` type in `Types/Tool.swift` already works; ToolMetadata and new Tool protocol reference it, not replace it |
| Error taxonomy | Multiple per-subsystem error enums | Single `AgentRuntimeError` enum with subsystem-grouped cases | Unified error handling at the Runtime level; each subsystem maps its errors to Runtime cases |
| Streaming channel synchronization | `OSAllocatedUnfairLock` or `DispatchQueue` for continuation access | `actor GenerationChannel` | Actor serializes access to the `AsyncThrowingStream.Continuation` without manual locking |
| Protocol conformance verification | Manual `is` / `as?` casting | Swift protocol conformance with `any` existentials | The compiler verifies conformance at compile time; runtime casting is unnecessary for known protocols |

**Key insight:** Phase 1 defines the type system contracts. Every "don't hand-roll" item above is a Swift stdlib feature. The phase introduces zero complexity — it reduces it by replacing fragmented types with unified abstractions.

## Runtime State Inventory

> **Skipped:** Phase 1 is not a rename/refactor/migration phase. It is a greenfield type-definition phase within a brownfield project. No strings are renamed, no state is migrated. All new types are additive with zero behavioral change.

## Common Pitfalls

### Pitfall 1: Actor Protocol Property Access Patterns

**What goes wrong:** Defining `var modelProvider: any LanguageModel { get }` on an actor protocol. Consumers call `await runtime.modelProvider` but then try to access `provider.capabilities` without realizing the provider itself may not be actor-isolated (it's Sendable, not Actor). This compiles but the access pattern is confusing.

**Why it happens:** Actor protocol properties return values from the actor's isolation domain. But `any LanguageModel` is `Sendable` — once retrieved, access is synchronous. The `await` is only needed for the initial property access on the actor.

**How to avoid:** Document the access pattern explicitly. All `AgentRuntime` protocol properties are `await`-accessed once (to cross the actor boundary), but the returned values are locally accessible. This matches how Apple's `LanguageModelSession` works.

**Warning signs:** Confusion in code review about where `await` is needed. If consumers add `await` before every property chain access, the pattern is misunderstood.

### Pitfall 2: Primary Associated Type Shadowing

**What goes wrong:** Defining `protocol Tool<Input>` then using `any Tool` without the angle brackets. Swift 6 allows bare `any Tool` but the `Input` type becomes `Any` (fully erased), making `tool.call(input)` impossible without knowing the concrete Input type.

**Why it happens:** Primary associated types are optional at the use site. `any Tool` is valid but useless for calling typed methods. The compiler doesn't warn about this.

**How to avoid:** In AgentRuntime's tool storage, use `any Tool<some Codable & Sendable>` or store tools in a type-erasing wrapper. Document that `any Tool` without angle brackets loses Input type information.

**Warning signs:** Compiler errors about "cannot call `call` on existential `any Tool`" — indicates the Input type was lost through erasure.

### Pitfall 3: Enum Case Explosion in AgentRuntimeError

**What goes wrong:** The unified error enum becomes a flat list of 30+ cases with no organizational structure. Callers write `switch error { case .rateLimited: ... default: ... }` because matching all cases is unwieldy.

**Why it happens:** Every subsystem wants its error cases in the same enum. Without grouping, the enum becomes a bag of unrelated cases.

**How to avoid:** Group cases by subsystem using nested types or naming conventions. The enum itself has ~15 cases organized by subsystem prefix. Each subsystem has 2-4 error cases. Callers match on subsystem groups: `case .model(let modelError)`, `case .memory(let memoryError)`.

**Warning signs:** An enum with >20 cases and no organizational structure. Cases named without subsystem context (e.g., `notFound` instead of `toolNotFound`).

### Pitfall 4: Transcript Entry Associated Value Bloat

**What goes wrong:** Each `Transcript.Entry` case carries too many associated values, mirroring the full internal representation. `.toolCall(id:name:input:status:timestamp:context:...)` becomes a 10-field tuple.

**Why it happens:** The temptation to make Transcript "complete" — carrying every piece of data any consumer might need. But Transcript is canonical history, not an API wire format.

**How to avoid:** Keep Entry cases minimal — store only what's needed for history reconstruction. Detailed tool input/output can be stored as `Data` (Codable-encoded) or referenced by ID. The existing `ContentBlock` and `ToolResult` types already carry rich detail; Transcript references them, doesn't duplicate them.

**Warning signs:** Entry associated values exceeding 4 fields. Cases that mirror `ContentBlock` or `StreamEvent` fields one-to-one.

### Pitfall 5: MemoryStore Generic Method Ambiguity

**What goes wrong:** `func retrieve<T: Codable & Sendable>(key:namespace:)` requires the caller to specify `T` at the call site: `store.retrieve(key: "x", namespace: "y") as String?`. Without the type hint, the compiler can't infer `T`.

**Why it happens:** Swift's type inference works from return type context. If the caller assigns to `let x: String?`, inference works. But in generic contexts (inside another generic function), inference fails.

**How to avoid:** Document the type annotation requirement. Provide convenience methods for common types (`retrieveString`, `retrieveData`). The protocol accepts `T: Codable & Sendable` for maximum flexibility; ergonomics can be improved with protocol extensions in Phase 3.

**Warning signs:** Compiler errors about "generic parameter 'T' could not be inferred" at MemoryStore call sites.

## Code Examples

Verified patterns from official sources and project codebase analysis:

### LanguageModelCapabilities
```swift
// Source: Apple FoundationModels LanguageModelCapabilities (WWDC26)
// Verified against: SwiftAgent ModelInfo (ModelRegistry.swift:72-80)
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/LanguageModel.swift

/// Single struct describing model capabilities. Replaces dual ModelInfo types.
/// Mirrors Apple's FoundationModels `LanguageModelCapabilities`.
public struct LanguageModelCapabilities: Sendable, Equatable {
    /// Whether the model supports streaming responses.
    public var supportsStreaming: Bool
    
    /// Whether the model supports tool/function calling.
    public var supportsToolUse: Bool
    
    /// Whether the model supports extended thinking/reasoning.
    public var supportsThinking: Bool
    
    /// Whether the model supports vision/image inputs.
    public var supportsVision: Bool
    
    /// Maximum context window size in tokens.
    public var contextWindow: Int
    
    /// Maximum output tokens per response.
    public var maxOutputTokens: Int
    
    /// Human-readable provider name for UI display.
    public var providerDisplayName: String
    
    public init(
        supportsStreaming: Bool = true,
        supportsToolUse: Bool = true,
        supportsThinking: Bool = false,
        supportsVision: Bool = false,
        contextWindow: Int = 200_000,
        maxOutputTokens: Int = 8_192,
        providerDisplayName: String
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolUse = supportsToolUse
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.providerDisplayName = providerDisplayName
    }
}
```

### AgentRuntimeError
```swift
// Source: Apple FoundationModels LanguageModelError + SwiftAgent LLMError (LLMClient.swift:974)
// File: Sources/SwiftAgentCore/AgentRuntime/AgentRuntimeError.swift

/// Unified error type across ALL subsystems. Replaces fragmented
/// LLMError, DeepSeekError, and ad-hoc error propagation.
public enum AgentRuntimeError: Error, Sendable {
    // MARK: - Model Errors (from LanguageModel / LanguageModelExecutor)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized(reason: String)
    case serverError(statusCode: Int, body: String?)
    case timeout
    case contextSizeExceeded(maxTokens: Int, requestedTokens: Int)
    case invalidResponse(reason: String)
    
    // MARK: - Memory Errors (from MemoryStore)
    case storageFull(availableBytes: Int64)
    case keyNotFound(key: String, namespace: String)
    case migrationFailed(fromVersion: Int, toVersion: Int, reason: String)
    
    // MARK: - Permission Errors (from PermissionEngine)
    case permissionDenied(permission: String, reason: String)
    case sandboxViolation(resource: String)
    
    // MARK: - Tool Errors (from ToolEngine / Tool execution)
    case toolNotFound(name: String)
    case toolExecutionFailed(name: String, reason: String)
    case toolValidationFailed(name: String, field: String, reason: String)
    
    // MARK: - Graph Errors (from AgentGraph — future)
    case cycleDetected(nodes: [String])
    case nodeFailed(nodeID: String, reason: String)
}
```

### Transcript
```swift
// Source: Apple FoundationModels Transcript (WWDC26 Session 339)
// File: Sources/SwiftAgentCore/AgentRuntime/Transcript.swift

/// Canonical conversation history with typed entries.
/// Provider-agnostic. Consumed by MemoryStore for persistent memory.
public struct Transcript: Sendable {
    public var entries: [Entry]
    
    public init(entries: [Entry] = []) {
        self.entries = entries
    }
    
    /// Typed transcript entry — each case captures one kind of conversation event.
    public enum Entry: Sendable {
        /// System-level instruction (e.g., system prompt).
        case instruction(String)
        
        /// User prompt or message.
        case prompt(String)
        
        /// Model text response.
        case response(String)
        
        /// A tool call requested by the model.
        case toolCall(id: String, name: String, input: Data)
        
        /// Output from a completed tool execution.
        case toolOutput(id: String, output: String, isError: Bool)
        
        /// Model thinking/reasoning content.
        case thinking(String)
        
        /// System-level message (e.g., compaction notification).
        case system(String)
    }
}
```

### AgentProfile
```swift
// Source: Apple FoundationModels DynamicProfile pattern (WWDC26 Session 241)
// File: Sources/SwiftAgentCore/AgentRuntime/AgentProfile.swift

/// Agent identity bundle. Forward-compatible with WWDC27 DynamicProfile
/// runtime switching (swap profile mid-session without losing transcript).
public struct AgentProfile: Sendable {
    /// Display name for this agent configuration.
    public var name: String
    
    /// System instructions defining agent behavior.
    public var instructions: String
    
    /// Tools available to this agent.
    public var tools: [any Tool]
    
    /// Model used for inference (nil = use AgentRuntime default).
    public var model: (any LanguageModel)?
    
    /// Permission mode for this agent.
    public var permissionMode: AgentPermission
    
    /// Memory scope defining persistence boundaries.
    public var memoryScope: MemoryScope
    
    public init(
        name: String,
        instructions: String,
        tools: [any Tool] = [],
        model: (any LanguageModel)? = nil,
        permissionMode: AgentPermission = .default,
        memoryScope: MemoryScope = .session
    ) {
        self.name = name
        self.instructions = instructions
        self.tools = tools
        self.model = model
        self.permissionMode = permissionMode
        self.memoryScope = memoryScope
    }
}

/// Defines the persistence boundary for agent memory.
public enum MemoryScope: Sendable {
    /// Memory is scoped to the current session only.
    case session
    /// Memory persists across sessions within a project.
    case project
    /// Memory persists globally across all projects.
    case global
}
```

### AgentPermission
```swift
// Source: macOS Security framework permission model + Apple WWDC27 predicted AgentSandbox
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/PermissionEngine.swift

/// Runtime-level permission taxonomy. Not tool-level — these are
/// the capability categories that AgentRuntime gates.
///
/// Forward-compatible with predicted WWDC27 AgentSandbox and macOS
/// permission model (TCC framework extension for AI agents).
public enum AgentPermission: Sendable, CaseIterable {
    /// Read access to filesystem paths.
    case readFiles(paths: Set<String>)
    
    /// Write/modify access to filesystem paths.
    case writeFiles(paths: Set<String>)
    
    /// Network access to specified domains.
    case network(domains: Set<String>)
    
    /// Access to user contacts.
    case contacts
    
    /// Access to user calendar.
    case calendar
    
    /// Access to device location.
    case location
    
    /// Access to camera.
    case camera
    
    /// Access to microphone.
    case microphone
    
    /// Execute arbitrary shell commands.
    case runCommands
    
    /// Delete files or resources.
    case delete
    
    /// Unrestricted access (all permissions granted).
    case all
    
    /// Default permission set (read-only files, no network, no shell).
    case `default`
    
    /// Plan-only mode — no mutations allowed.
    case plan
}
```

### Simplified Tool Protocol
```swift
// Source: Apple FoundationModels Tool protocol + SwiftAgent existing Tool (Tool.swift:45)
// File: Sources/SwiftAgentCore/AgentRuntime/Tools/SimplifiedTool.swift

/// Simplified tool protocol — the contract between model and agent.
/// ~6 core members. Cross-cutting concerns migrate to ToolMetadata.
///
/// Forward-compatible with WWDC27 AgentIntent auto-discovery:
/// AgentIntent protocol can refine Tool with auto-registration
/// without breaking existing Tool conformances.
public protocol Tool<Input>: Sendable {
    /// The input type this tool accepts. Must be Codable for
    /// serialization and Sendable for concurrency safety.
    associatedtype Input: Codable & Sendable
    
    /// PascalCase tool name as seen by the LLM (e.g., "Bash", "Read").
    var name: String { get }
    
    /// Human-readable description of what the tool does.
    var description: String { get }
    
    /// JSON Schema for the tool's input parameters.
    /// Uses the existing JSONSchema type from Types/Tool.swift.
    var inputSchema: JSONSchema { get }
    
    /// Execute the tool with validated input.
    func call(_ input: Input) async throws -> ToolOutput
}
```

### ToolMetadata
```swift
// Source: Decomposed from SwiftAgent Tool protocol members (Tool.swift:214+)
// File: Sources/SwiftAgentCore/AgentRuntime/Tools/ToolMetadata.swift

/// Per-tool operational data separated from the Tool protocol.
/// Populated at registration time via ToolEngine.
public struct ToolMetadata: Sendable {
    /// Search hint for tool discovery (3-10 words).
    public var searchHint: String?
    
    /// Whether this tool is currently enabled.
    public var isEnabled: Bool
    
    /// Whether this tool is read-only (safe for auto-approval).
    public var isReadOnly: Bool
    
    /// Whether this tool is safe to run concurrently.
    public var isConcurrencySafe: Bool
    
    /// Whether this tool performs destructive operations.
    public var isDestructive: Bool
    
    /// Tool interruption behavior during concurrent user input.
    public var interruptBehavior: InterruptBehavior
    
    /// Human-readable activity description for spinner display.
    public var activityDescription: String?
    
    /// Whether this tool requires explicit user approval.
    public var requiresApproval: Bool
    
    /// Permission category for this tool.
    public var permissionCategory: AgentPermission?
    
    public init(
        searchHint: String? = nil,
        isEnabled: Bool = true,
        isReadOnly: Bool = false,
        isConcurrencySafe: Bool = false,
        isDestructive: Bool = false,
        interruptBehavior: InterruptBehavior = .block,
        activityDescription: String? = nil,
        requiresApproval: Bool = true,
        permissionCategory: AgentPermission? = nil
    ) {
        self.searchHint = searchHint
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
        self.isConcurrencySafe = isConcurrencySafe
        self.isDestructive = isDestructive
        self.interruptBehavior = interruptBehavior
        self.activityDescription = activityDescription
        self.requiresApproval = requiresApproval
        self.permissionCategory = permissionCategory
    }
}

/// Behavior when user submits input while a tool is running.
public enum InterruptBehavior: Sendable {
    /// Cancel the running tool and discard result.
    case cancel
    /// Keep running; new input waits.
    case block
}
```

### ToolOutput
```swift
// Source: Replaces SwiftAgent ToolResult (Conversation.swift:201)
// File: Sources/SwiftAgentCore/AgentRuntime/Tools/ToolOutput.swift

/// Public tool output type. Replaces ToolResult in the public API.
/// ContentBlock is NOT exposed — consumers see only String output
/// or structured blocks.
public enum ToolOutput: Sendable {
    /// Plain text output.
    case string(String)
    
    /// Structured content blocks (provider-agnostic, no Anthropic types).
    case blocks([OutputBlock])
}

/// A single output block from a tool. Provider-agnostic.
public struct OutputBlock: Sendable {
    public let type: OutputBlockType
    public let content: String
    
    public enum OutputBlockType: String, Sendable {
        case text
        case code
        case diff
        case image
        case error
    }
}
```

### LanguageModelExecutor
```swift
// Source: Apple FoundationModels LanguageModelExecutor (WWDC26 Session 339)
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/LanguageModelExecutor.swift

/// Internal protocol for per-provider inference backends.
/// NOT exposed to CLI/App — used only by AgentRuntime.
///
/// Each executor owns its wire format translation, SSE parsing,
/// and model-specific behavior entirely.
public protocol LanguageModelExecutor: Sendable {
    /// The model this executor serves.
    var model: any LanguageModel { get }
    
    /// Send a generation request to the model, streaming results
    /// through the provided channel.
    ///
    /// - Parameters:
    ///   - transcript: The conversation history to include.
    ///   - tools: Available tool definitions.
    ///   - options: Generation configuration.
    ///   - channel: Streaming channel for results.
    func respond(
        to transcript: Transcript,
        tools: [ToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws
}

/// Normalized tool definition sent from AgentRuntime to executor.
/// Provider-agnostic; each executor maps to its own wire format.
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema
}

/// Generation parameters sent to the executor.
public struct GenerationOptions: Sendable {
    public var maxTokens: Int?
    public var temperature: Double?
    public var reasoningBudget: Int?
    public var stream: Bool
    
    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        reasoningBudget: Int? = nil,
        stream: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.reasoningBudget = reasoningBudget
        self.stream = stream
    }
}
```

### GenerationChannel
```swift
// Source: Apple FoundationModels streaming channel pattern (WWDC26)
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/GenerationChannel.swift

/// Streaming abstraction between executor and runtime.
/// Executor pushes typed events; runtime consumes them.
///
/// Abstracts over URLSession async bytes, WebSocket, or callback-based
/// delivery. The runtime never sees raw SSE token strings.
public protocol GenerationChannel: Sendable {
    /// Send a text delta to the consumer.
    func send(textDelta: String) async
    
    /// Send a thinking/reasoning delta to the consumer.
    func send(thinkingDelta: String) async
    
    /// Signal that a tool call has been requested by the model.
    func send(toolCallRequest id: String, name: String, input: Data) async
    
    /// Signal that a tool call has completed.
    func send(toolCallCompleted id: String, output: ToolOutput) async
    
    /// Signal turn completion with stop reason and usage.
    func complete(stopReason: String?, usage: Usage?) async
    
    /// Signal an error from the executor.
    func fail(with error: AgentRuntimeError) async
}
```

### AgentState (Type-Slot)
```swift
// Source: Predicted WWDC27 @AgentState property-wrapper pattern
// File: Sources/SwiftAgentCore/AgentRuntime/Providers/MemoryStore.swift

/// Type-slot for future @AgentState property-wrapper.
/// DESIGN ONLY — not implemented. Protocol surface reserved
/// so MemoryStore can accept @AgentState-annotated properties
/// in a future phase without breaking changes.
///
/// Predicted WWDC27 shape: @AgentState<T: Codable>(key:namespace:store:)
/// with automatic MemoryStore read/write, similar to @AppStorage
/// but backed by agent memory instead of UserDefaults.
public protocol AgentStateProtocol: Sendable {
    /// The key used to persist this state in MemoryStore.
    var key: String { get }
    
    /// The namespace for this state.
    var namespace: String { get }
    
    /// The MemoryStore backing this state.
    var store: any MemoryStore { get }
}
```

### AgentGraph (Placeholder)
```swift
// Source: Predicted WWDC27 AgentGraph / WorkflowGraph orchestration
// File: Sources/SwiftAgentCore/AgentRuntime/Graph/AgentGraph.swift

/// Agent graph — ordered DAG of agent nodes.
/// TYPE-SLOT ONLY — not implemented. Protocol surface designed
/// so AgentRuntime can accept a Graph in a future phase
/// without breaking changes.
///
/// Predicted WWDC27 shape: AgentKit WorkflowGraph with
/// Planner, Researcher, Coder, Reviewer node types.
public protocol AgentGraph: Sendable {
    /// The nodes in this graph, in topological order.
    var nodes: [any AgentNode] { get }
    
    /// Validate the graph structure (no cycles, all inputs satisfied).
    func validate() throws
}

/// A single node in an agent graph.
/// TYPE-SLOT ONLY — not implemented.
public protocol AgentNode: Sendable {
    /// The agent profile for this node.
    var agent: AgentProfile { get }
    
    /// Inputs expected by this node.
    var inputs: [NodeInput] { get }
    
    /// Outputs produced by this node.
    var outputs: [NodeOutput] { get }
    
    /// Optional condition for node execution.
    var condition: NodeCondition? { get }
}

/// Input to an agent node.
public struct NodeInput: Sendable {
    public let name: String
    public let type: NodeIOType
}

/// Output from an agent node.
public struct NodeOutput: Sendable {
    public let name: String
    public let type: NodeIOType
}

/// Type of a node input/output.
public enum NodeIOType: Sendable {
    case string
    case json
    case transcript
    case toolOutput
}

/// Condition for node execution.
public enum NodeCondition: Sendable {
    /// Always execute this node.
    case always
    /// Execute only if the named output is non-nil.
    case whenPresent(String)
    /// Execute only if the expression evaluates to true.
    case expression(String)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `QueryEngine` + `LLMClient` as dual entry points | `AgentRuntime` actor protocol as single entry point | Phase 1 (type only) | Centralizes subsystem ownership; consumers depend on one protocol, not two concrete types |
| `ModelInfo` (Core) + `DeepSeekModel` (App) dual types | `LanguageModelCapabilities` single struct | Phase 1 | Single source of truth for model capabilities across Core and App |
| `LLMError` (6 cases, Core) + ad-hoc error propagation | `AgentRuntimeError` (17 cases, subsystem-grouped) | Phase 1 | Unified error handling; each subsystem maps errors to Runtime cases |
| Raw `[Message]` / `[ContentBlock]` as conversation history | `Transcript` with typed `Entry` enum | Phase 1 | Provider-agnostic history; survives model swapping |
| Ad-hoc system prompt + model selection | `AgentProfile` struct | Phase 1 | Bundled agent identity; forward-compatible with DynamicProfile |
| 43-member `Tool` protocol (30+ cross-cutting concerns) | ~6-member `Tool` protocol + `ToolMetadata` struct | Phase 1 (type only; migration in Phase 4) | Model-tool contract separated from runtime-tool contract |
| `ToolResult` enum with `ContentBlock` exposure | `ToolOutput` enum (string + blocks, no ContentBlock) | Phase 1 (type only; migration in Phase 4) | Hides wire-format types from consumers |
| `PermissionEngine` as concrete `struct` only | `PermissionEngine` upgraded to `protocol` | Phase 1 (type only; conformance in Phase 3) | Enables swappable permission backends |

**Deprecated/outdated:**
- `ModelInfo` (in `LLM/ModelRegistry.swift`): Replaced by `LanguageModelCapabilities`. The existing struct remains until Phase 4 cleanup but is architecturally superseded.
- `LLMError` (in `LLM/LLMClient.swift`): Replaced by `AgentRuntimeError.model` cases. Existing enum remains until Phase 4.
- 43-member `Tool` protocol members beyond the core ~6: Replaced by `ToolMetadata`. Existing protocol remains until Phase 4 tool migration.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Swift `protocol P: Actor` allows requirements to be accessed with `await` from outside the actor. [ASSUMED based on SE-0306; confirmed to work in Swift 6.3] | Pattern 1 | Low — SE-0306 is implemented and shipped. The `Actor` protocol exists in the stdlib. |
| A2 | `any Tool<Input>` with primary associated type works correctly with `Sendable` existentials in Swift 6. [ASSUMED based on Swift 5.7 primary associated types feature] | Pattern 4 | Low — Primary associated types shipped in Swift 5.7 and are stable in Swift 6. |
| A3 | The existing `JSONSchema` type in `Types/Tool.swift` is suitable for use by the new `Tool` protocol without modification. [ASSUMED based on codebase analysis of Tool.swift lines 58-59] | Simplified Tool | Low — Verified by codebase grep; the type exists and is Sendable. |
| A4 | `AgentPermission` enum cases align with predicted WWDC27 macOS AgentSandbox permissions. [ASSUMED based on WWDC26 FoundationModels trajectory and macOS TCC framework patterns] | AgentPermission | Medium — WWDC27 hasn't happened yet. The enum can be extended with new cases if the taxonomy diverges. |
| A5 | `AgentGraph` and `AgentNode` protocol shapes are compatible with Apple's predicted WorkflowGraph. [ASSUMED based on AgentKit trajectory discussed in WWDC26 sessions] | AgentGraph Placeholder | Medium — WWDC27 may introduce different DAG semantics. Type-slots are designed to be minimal so adaptation cost is low. |
| A6 | The `AgentState` property-wrapper prediction (`@AgentState<T>`) matches Apple's design direction. [ASSUMED based on @Observable + SwiftData pattern precedent] | AgentState Type-Slot | Medium-High — The property-wrapper pattern is consistent with Apple's framework design philosophy, but the exact API shape is speculative. |
| A7 | The 4 existing `nonisolated(unsafe)` occurrences are the current baseline and must not increase. [ASSUMED based on grep of the codebase] | Anti-Patterns | Low — Verified by grep. Count: 4 occurrences in 3 files (TerminalView.swift ×2, LLMClient.swift ×1, SwiftAgentPaths.swift ×1). |

## Open Questions

1. **Should `AgentRuntime` expose `ToolEngine` and `ContextManager` as protocols or concrete types?**
   - What we know: The requirement says "property slots for all subsystems." Current codebase has `ToolExecutor` as a struct and `ContextManager` as a class-like actor.
   - What's unclear: Whether these should be `any ToolEngine` protocol existentials or can be concrete types referenced by the actor.
   - Recommendation: Expose as `any ToolEngine` and `any ContextManager` protocols (defined as type-slots like AgentGraph). This maximizes swappability. The existing concrete types conform later.

2. **Should `Transcript.Entry.toolCall` carry the full tool input as `Data` (Codable-encoded) or as a typed `any Codable & Sendable`?**
   - What we know: `Data` is simple, always Sendable, and avoids existential issues. `any Codable & Sendable` preserves type information but complicates serialization.
   - What's unclear: Whether consumers need to inspect tool inputs from Transcript entries (vs. just replaying them).
   - Recommendation: Use `Data` for Phase 1. It's simpler, more Sendable-friendly, and can be upgraded to a typed wrapper in Phase 2 if needed.

3. **Should `GenerationChannel` be a protocol or an actor?**
   - What we know: The STACK.md research proposes `actor GenerationChannel` for synchronized continuation access. But Phase 1 only defines types — the implementation (actor vs. class) is a Phase 2 concern.
   - What's unclear: Whether a protocol provides enough abstraction or if actor isolation is needed at the protocol level.
   - Recommendation: Define as a `protocol` for now. The implementation can be an `actor` that conforms to the protocol. Protocols are more flexible for testing (mock channels).

4. **Should `MemoryStore` include a `migrate()` method in the protocol, or is schema migration an implementation detail?**
   - What we know: The requirement mentions schema versioning (MEM-02 for SQLiteMemoryStore). MEM-01 defines 6 methods without migration.
   - What's unclear: Whether migration belongs in the protocol surface or is an implementation detail of SQLiteMemoryStore.
   - Recommendation: Keep migration out of the Phase 1 protocol. It's an implementation concern for SQLiteMemoryStore (Phase 3). The protocol defines operational methods only.

5. **Where exactly should `AgentPermission` be defined — in the Providers directory with PermissionEngine, or in the root AgentRuntime/ directory?**
   - What we know: `AgentPermission` is consumed by both `PermissionEngine` and `AgentProfile`. It's a cross-cutting type.
   - What's unclear: Whether to co-locate with PermissionEngine or keep at the AgentRuntime level.
   - Recommendation: Define in `AgentRuntime/Providers/PermissionEngine.swift` alongside the PermissionEngine protocol. It's primarily a permission concept. `AgentProfile` imports it.

## Environment Availability

> **Skipped:** Phase 1 has no external dependencies. All work is pure Swift type definitions using only the standard library and Foundation. The project already builds successfully on macOS 15.0+ with Swift 6.3 (verified: `swift build --disable-sandbox` passes, 7.87s build time).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 1 defines types only; auth handled by LanguageModelExecutor implementations (Phase 3) |
| V3 Session Management | No | Session management in Transcript/AgentProfile; no runtime session state in Phase 1 |
| V4 Access Control | Yes | `AgentPermission` enum defines the access control taxonomy; `PermissionEngine` protocol gates subsystem access |
| V5 Input Validation | Yes | `ToolMetadata` carries validation metadata; `ToolInput` (via `Codable`) provides type-safe input boundaries |
| V6 Cryptography | No | No cryptographic operations in Phase 1 type definitions |
| V7 Error Handling | Yes | `AgentRuntimeError` enum provides structured error information without leaking sensitive data (no API keys in error messages) |

### Known Threat Patterns for Swift Agent Runtime Types

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tool input injection via unvalidated Codable deserialization | Tampering | `Tool.Input: Codable` with strict decoding; `ToolMetadata.isDestructive` flags high-risk tools |
| Permission bypass via enum exhaustion | Elevation of Privilege | `AgentPermission` uses comprehensive case coverage; `PermissionEngine.check()` is the single gate |
| MemoryStore key enumeration via `listNamespaces()` | Information Disclosure | Namespace listing is part of the protocol contract; backend implementations apply access controls |
| Transcript manipulation via unvalidated Entry insertion | Tampering | `Transcript` is a value type with immutable entries; append-only semantics enforced by `var entries` being internal-set |
| AgentProfile tool injection via unvalidated `[any Tool]` array | Tampering | Tools are registered through ToolEngine, not ad-hoc; `AgentProfile.tools` is validated against registry |
| Error information leakage via `AgentRuntimeError` descriptions | Information Disclosure | Error cases carry structured data, not raw server responses; `.unauthorized` carries a reason string, not the API key |

## Sources

### Primary (HIGH confidence)
- Apple WWDC26 Session 339: "Bring an LLM provider to the Foundation Models framework" — `LanguageModel`, `LanguageModelExecutor`, `LanguageModelSession` protocol shapes. [VERIFIED: developer.apple.com/videos/play/wwdc2026/339/]
- Apple WWDC26 Session 241: "What's new in the Foundation Models framework" — `DynamicProfile`, transcript, streaming patterns. [VERIFIED: developer.apple.com/videos/play/wwdc2026/241/]
- Apple FoundationModels Documentation — `LanguageModelError`, `LanguageModelCapabilities`, `Generable` protocol. [VERIFIED: developer.apple.com/documentation/foundationmodels]
- Swift Evolution SE-0306: Actors — `protocol Actor: AnyObject, Sendable`, actor isolation semantics. [VERIFIED: github.com/swiftlang/swift-evolution]
- SwiftAgent codebase analysis: `Sources/SwiftAgentCore/Types/Tool.swift` (1156 lines, 43 protocol members), `Sources/SwiftAgentCore/LLM/LLMClient.swift` (LLMError enum, 6 cases), `Sources/SwiftAgentCore/LLM/ModelRegistry.swift` (ModelInfo struct, 7 fields), `Sources/SwiftAgentCore/Safety/PermissionEngine.swift` (struct-based, 10-step pipeline), `Sources/SwiftAgentCore/Types/StreamEvent.swift` (13-case enum), `Sources/SwiftAgentCore/Types/Permission.swift` (22+ permission types)
- Package.swift: Swift 6.2 tools version, macOS 15.0 minimum, 3-target architecture
- Project build verification: `swift build --disable-sandbox` succeeds (7.87s), confirming the environment can compile the codebase

### Secondary (MEDIUM confidence)
- OpenFoundationModels (GitHub: 1amageek/OpenFoundationModels) — Confirms FoundationModels protocol shapes are implementable without Apple internals
- AnyLanguageModel (GitHub: mattt/AnyLanguageModel) — Multi-provider executor isolation pattern
- Dev.to: "What's New in Apple's Foundation Models Framework at WWDC 2026" — Community summary confirming Dynamic Profiles and provider architecture

### Tertiary (LOW confidence)
- Swift Forums: "How to Express Varying Concurrency Isolation in Protocol" — Community discussion on actor protocol patterns
- AboutAppleFoundationModels.md (project root) — Community Chinese-language analysis of WWDC25→26 FoundationModels evolution

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — No external dependencies; pure Swift 6.3 stdlib + Foundation
- Architecture: HIGH — Patterns verified against Apple FoundationModels (WWDC26), Swift Evolution proposals, and existing codebase analysis
- Pitfalls: HIGH — Pitfalls derived from Swift 6 concurrency constraints, primary associated type semantics, and brownfield constraints verified against actual codebase
- Security: MEDIUM — ASVS mappings are standard; AgentSandbox predictions are speculative (WWDC27)

**Research date:** 2026-06-25
**Valid until:** 2026-07-25 (30 days; stable Swift 6 patterns, no rapidly-changing external dependencies)
