import Foundation

// MARK: - Placeholder Subsystem Protocols

/// Tool registry and execution engine.
///
/// All methods are `async` to support actor-based implementations
/// (e.g., DefaultToolEngine). The protocol itself remains `Sendable`
/// rather than `Actor`-constrained so concrete types can choose
/// actor or non-actor storage.
public protocol ToolEngine: Sendable {
    /// Register a tool with its metadata.
    func register(tool: any Tool, metadata: ToolMetadata) async

    /// Retrieve the normalized definition for a tool by name.
    func getDefinition(name: String) async -> SessionToolDefinition?

    /// Retrieve all registered tool definitions for passing to an executor.
    func getAllDefinitions() async -> [SessionToolDefinition]

    /// Execute a tool by name with JSON-encoded input data.
    /// Returns the tool's output. Throws AgentRuntimeError if tool not found
    /// or execution fails.
    func execute(name: String, input: Data) async throws -> ToolOutputValue
}

/// Context window management and compaction.
///
/// Named SessionContextManager to avoid collision with the existing
/// `ContextManager` struct in Agent/ContextManager.swift, following the
/// established Runtime prefix convention.
///
/// Placeholder protocol — full definition in Phase 2.
public protocol SessionContextManager: Sendable { }

/// Agent identity and profile management.
/// Placeholder protocol — full definition in Phase 2.
public protocol ProfileManager: Sendable { }

/// Hook system for lifecycle events.
///
/// Named SessionHookSystem to avoid collision with the existing
/// `HookSystem` actor in Hooks/HookSystem.swift, following the
/// established Runtime prefix convention.
///
/// Placeholder protocol — full definition in Phase 2.
public protocol SessionHookSystem: Sendable { }

// MARK: - LanguageModelSession

/// Central agent runtime orchestrator. Replaces QueryEngine + LLMClient
/// as the primary consumer API surface.
///
/// Only actor types can conform — the compiler enforces actor isolation
/// across all subsystem access.
///
/// ## Access Pattern
///
/// Accessing properties crosses the actor boundary (requires `await`),
/// but the returned protocol values are `Sendable` and accessible
/// synchronously without additional `await`:
///
/// ```swift
/// let runtime: any LanguageModelSession = ...
/// let provider = await runtime.modelProvider   // await to cross actor boundary
/// let caps = provider.capabilities             // synchronous access
/// ```
public protocol LanguageModelSession: Actor {
    /// The language model provider for inference.
    var modelProvider: any LanguageModel { get }

    /// Persistent memory store for agent state and context.
    var memoryStore: any SessionMemoryStore { get }

    /// Permission engine for runtime-level access control.
    var permissionEngine: any SessionPermissionEngine { get }

    /// Tool registry and execution engine.
    var toolEngine: any ToolEngine { get }

    /// Context window management and compaction.
    var contextManager: any SessionContextManager { get }

    /// Agent identity and profile management.
    var profileManager: any ProfileManager { get }

    /// Agent graph orchestration (placeholder for WWDC27 AgentGraph).
    /// Optional — nil when no multi-agent graph is active.
    var graphEngine: (any AgentGraph)? { get }

    /// Hook system for lifecycle events.
    var hookSystem: any SessionHookSystem { get }

    /// Whether a turn is currently in progress.
    /// Consumers can use this to guard against concurrent requests.
    var isResponding: Bool { get }

    /// Run a single conversation turn with the given prompt.
    /// Appends prompt to transcript, invokes the model, processes tool calls,
    /// and updates the memory store. Returns a Response with the transcript,
    /// usage metadata, and stop reason.
    func respond(to prompt: String) async throws -> Response

    /// Stream a conversation turn, yielding SessionEvent values progressively.
    /// Each event is a provider-agnostic snapshot of the current state.
    /// The consumer iterates `for try await event in stream` to receive
    /// text deltas, tool calls, and turn completion.
    func streamResponse(to prompt: String) -> ResponseStream
}
