import Foundation

// MARK: - DefaultToolEngine

/// Dictionary-backed tool registry and execution engine.
/// Stores tools by name and provides type-erased lookup/execution.
///
/// In Phase 2, `execute` returns a canned string stub. The full type-safe
/// execution path with permission gating arrives in Phase 3.
public actor DefaultToolEngine: ToolEngine {
    private var registry: [String: (tool: any RuntimeAgentTool, metadata: ToolMetadata)] = [:]

    public init() {}

    /// Register a tool with metadata. The tool is stored keyed by its `name`.
    public func register(tool: any RuntimeAgentTool, metadata: ToolMetadata) async {
        registry[tool.name] = (tool: tool, metadata: metadata)
    }

    /// Look up a tool by name and return its normalized definition.
    public func getDefinition(name: String) async -> RuntimeToolDefinition? {
        guard let entry = registry[name] else { return nil }
        return RuntimeToolDefinition(
            name: entry.tool.name,
            description: entry.tool.description,
            inputSchema: entry.tool.inputSchema
        )
    }

    /// Return all registered tool definitions for passing to an executor.
    public func getAllDefinitions() async -> [RuntimeToolDefinition] {
        registry.map { name, entry in
            RuntimeToolDefinition(
                name: entry.tool.name,
                description: entry.tool.description,
                inputSchema: entry.tool.inputSchema
            )
        }
    }

    /// Execute a tool by name. In Phase 2 this returns a canned string stub
    /// for registered tools; the type-safe execution path arrives in Phase 3.
    public func execute(name: String, input: Data) async throws -> ToolOutputValue {
        guard registry[name] != nil else {
            throw AgentRuntimeError.toolNotFound(name: name)
        }
        // Stub output — real execution path arrives in Phase 3 with
        // type-erased decoding and permission gating.
        return .string("[Phase 2 stub] tool \(name) executed with \(input.count) bytes of input")
    }
}

// MARK: - NoOpContextManager

/// No-op implementation of RuntimeContextManager. Satisfies the empty protocol
/// contract. Real context window management and compaction arrive in Phase 3.
public struct NoOpContextManager: RuntimeContextManager, Sendable {
    public init() {}
}

// MARK: - NoOpProfileManager

/// No-op implementation of ProfileManager. Satisfies the empty protocol
/// contract. Real profile management arrives in a future phase.
public struct NoOpProfileManager: ProfileManager, Sendable {
    public init() {}
}

// MARK: - NoOpHookSystem

/// No-op implementation of RuntimeHookSystem. Satisfies the empty protocol
/// contract. Real lifecycle hook dispatch arrives in a future phase.
public struct NoOpHookSystem: RuntimeHookSystem, Sendable {
    public init() {}
}
