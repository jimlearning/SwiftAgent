import Foundation

// MARK: - Placeholder Subsystem Protocols

/// Tool registry and execution engine.
/// Placeholder protocol — full definition in Phase 2.
public protocol ToolEngine: Sendable { }

/// Context window management and compaction.
///
/// Named RuntimeContextManager to avoid collision with the existing
/// `ContextManager` struct in Agent/ContextManager.swift, following the
/// established Runtime prefix convention.
///
/// Placeholder protocol — full definition in Phase 2.
public protocol RuntimeContextManager: Sendable { }

/// Agent identity and profile management.
/// Placeholder protocol — full definition in Phase 2.
public protocol ProfileManager: Sendable { }

/// Hook system for lifecycle events.
///
/// Named RuntimeHookSystem to avoid collision with the existing
/// `HookSystem` actor in Hooks/HookSystem.swift, following the
/// established Runtime prefix convention.
///
/// Placeholder protocol — full definition in Phase 2.
public protocol RuntimeHookSystem: Sendable { }

// MARK: - AgentRuntime

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
/// let runtime: any AgentRuntime = ...
/// let provider = await runtime.modelProvider   // await to cross actor boundary
/// let caps = provider.capabilities             // synchronous access
/// ```
public protocol AgentRuntime: Actor {
    /// The language model provider for inference.
    var modelProvider: any LanguageModel { get }

    /// Persistent memory store for agent state and context.
    var memoryStore: any RuntimeMemoryStore { get }

    /// Permission engine for runtime-level access control.
    var permissionEngine: any RuntimePermissionEngine { get }

    /// Tool registry and execution engine.
    var toolEngine: any ToolEngine { get }

    /// Context window management and compaction.
    var contextManager: any RuntimeContextManager { get }

    /// Agent identity and profile management.
    var profileManager: any ProfileManager { get }

    /// Agent graph orchestration (placeholder for WWDC27 AgentGraph).
    /// Optional — nil when no multi-agent graph is active.
    var graphEngine: (any AgentGraph)? { get }

    /// Hook system for lifecycle events.
    var hookSystem: any RuntimeHookSystem { get }
}
