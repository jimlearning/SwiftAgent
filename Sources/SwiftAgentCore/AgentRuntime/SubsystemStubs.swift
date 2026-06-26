import Foundation

// MARK: - DefaultToolEngine

/// Dictionary-backed tool registry and execution engine.
/// Stores tools by name and provides type-erased lookup/execution.
/// Dispatches through `Tool._callFromData` for concrete execution.
public actor DefaultToolEngine: ToolEngine {
    private var registry: [String: (tool: any Tool, metadata: ToolMetadata)] = [:]

    public init() {}

    /// Register a tool with metadata. The tool is stored keyed by its `name`.
    public func register(tool: any Tool, metadata: ToolMetadata) async {
        registry[tool.name] = (tool: tool, metadata: metadata)
    }

    /// Look up a tool by name and return its normalized definition.
    public func getDefinition(name: String) async -> SessionToolDefinition? {
        guard let entry = registry[name] else { return nil }
        return SessionToolDefinition(
            name: entry.tool.name,
            description: entry.tool.description,
            inputSchema: entry.tool.inputSchema
        )
    }

    /// Return all registered tool definitions for passing to an executor.
    public func getAllDefinitions() async -> [SessionToolDefinition] {
        registry.map { name, entry in
            SessionToolDefinition(
                name: entry.tool.name,
                description: entry.tool.description,
                inputSchema: entry.tool.inputSchema
            )
        }
    }

    /// Execute a tool by name. Dispatches through the type-erased
    /// `_callFromData` path to the concrete tool's `call(arguments:)`.
    public func execute(name: String, input: Data) async throws -> ToolOutputValue {
        guard let entry = registry[name] else {
            throw AgentRuntimeError.toolNotFound(name: name)
        }
        return try await entry.tool._callFromData(input)
    }
}

// MARK: - NoOpSessionContextManager

/// No-op implementation of SessionContextManager. Satisfies the empty protocol
/// contract. Real context window management and compaction arrive in Phase 3.
public struct NoOpSessionContextManager: SessionContextManager, Sendable {
    public init() {}
}

// MARK: - NoOpProfileManager

/// No-op implementation of ProfileManager. Satisfies the empty protocol
/// contract. Real profile management arrives in a future phase.
public struct NoOpProfileManager: ProfileManager, Sendable {
    public init() {}
}

// MARK: - NoOpSessionHookSystem

/// No-op implementation of SessionHookSystem. Satisfies the empty protocol
/// contract. Real lifecycle hook dispatch arrives in a future phase.
public struct NoOpSessionHookSystem: SessionHookSystem, Sendable {
    public init() {}
}
