import Foundation

/// Schedules and executes tools, supporting concurrent and serial execution.
/// Mirrors Claude Code's `partitionToolCalls()` + tool execution pipeline.
public struct ToolExecutor: Sendable {
    public let registry: ToolRegistry

    public init(registry: ToolRegistry) {
        self.registry = registry
    }

    /// Execute a single tool by name.
    /// Matches CC's tool execution pipeline with progress support.
    public func execute(
        name: String,
        input: [String: JSONValue],
        context: ToolUseContext,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
        guard let tool = registry.tool(named: name) else {
            return ToolResult(content: "Error: tool '\(name)' not found", isError: true)
        }

        // Step 1: Validate input against tool schema (matches CC's inputSchema.parse)
        if let schemaError = tool.inputSchema.validate(input) {
            return ToolResult(content: "Error: invalid input - \(schemaError)", isError: true)
        }

        // Step 2: Permission check
        let permission = await tool.checkPermissions(input: input, context: context)
        switch permission {
        case .deny(let decision):
            return ToolResult(content: "Denied: \(decision.message)", isError: true)
        case .ask(let decision):
            // Delegate to interactive permission prompt handler (matching CC's permission prompt flow).
            if let handler = context.permissionPromptHandler {
                let response = await handler(tool.name, context.toolUseID ?? "", decision)
                switch response {
                case .allow:
                    break
                case .deny(let reason):
                    return ToolResult(content: "Denied: \(reason)", isError: true)
                }
            } else {
                // No handler configured — deny by default in non-interactive contexts.
                return ToolResult(content: "Requires approval: \(decision.message)", isError: true)
            }
        case .allow:
            break
        case .passthrough:
            // Passthrough — let the caller decide
            break
        }

        do {
            var result = try await tool.call(input: input, context: context, canUseTool: nil, parentMessage: nil, onProgress: onProgress)

            // Persist large tool results to disk (matching CC's processToolResultBlock).
            let toolUseId = context.toolUseID ?? name
            let (newContent, persisted, persistPath) = ToolResultStorage.processToolResult(
                content: result.content,
                toolName: name,
                maxResultSizeChars: tool.maxResultSizeChars,
                toolUseId: toolUseId,
                cwd: context.workingDirectory,
                sessionId: context.sessionID
            )
            if persisted {
                result.content = newContent
                result.persistedToDisk = true
                result.persistDirPath = persistPath
            }

            return result
        } catch {
            return ToolResult(content: "Tool error: \(error.localizedDescription)", isError: true)
        }
    }

    /// Execute multiple tools — runs concurrently when possible, serially otherwise.
    /// Matches CC's StreamingToolExecutor concurrent/serial partitioning.
    /// Results are returned in original call order.
    public func executeBatch(
        calls: [(name: String, input: [String: JSONValue])],
        context: ToolUseContext,
        onProgress: ToolCallProgress? = nil
    ) async -> [(name: String, result: ToolResult)] {
        // Partition into concurrent-safe and serial, tracking original indices
        var concurrent: [(index: Int, name: String, input: [String: JSONValue])] = []
        var serial: [(index: Int, name: String, input: [String: JSONValue])] = []

        for (i, call) in calls.enumerated() {
            if let tool = registry.tool(named: call.name), tool.isConcurrencySafe {
                concurrent.append((index: i, name: call.name, input: call.input))
            } else {
                serial.append((index: i, name: call.name, input: call.input))
            }
        }

        // Results collected by original index for ordered output
        var orderedResults: [Int: ToolResult] = [:]

        // Run concurrent tools in parallel (TaskGroup with unordered collection)
        if !concurrent.isEmpty {
            await withTaskGroup(of: (index: Int, name: String, result: ToolResult).self) { group in
                for call in concurrent {
                    let idx = call.index
                    let name = call.name
                    let input = call.input
                    group.addTask {
                        let result = (try? await self.execute(name: name, input: input, context: context, onProgress: onProgress))
                            ?? ToolResult(content: "Failed to execute", isError: true)
                        return (idx, name, result)
                    }
                }
                for await entry in group {
                    orderedResults[entry.index] = entry.result
                }
            }
        }

        // Run serial tools in sequence
        for call in serial {
            let result = (try? await execute(name: call.name, input: call.input, context: context, onProgress: onProgress))
                ?? ToolResult(content: "Failed to execute", isError: true)
            orderedResults[call.index] = result
        }

        // Return results in original call order
        return calls.enumerated().compactMap { (i, call) in
            orderedResults[i].map { (call.name, $0) }
        }
    }
}

/// Registry that holds all available tools.
public final class ToolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [String: any Tool] = [:]

    public init() {}

    public func register(_ tool: any Tool) {
        lock.lock()
        tools[tool.name] = tool
        lock.unlock()
    }

    /// Look up a tool by name or alias. Matches CC's findToolByName() in Tool.ts.
    public func tool(named name: String) -> (any Tool)? {
        lock.lock()
        defer { lock.unlock() }
        if let tool = tools[name] { return tool }
        for (_, tool) in tools {
            if tool.aliases.contains(name) { return tool }
        }
        return nil
    }

    public var allTools: [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values)
    }

    /// Build ToolDefinition list for API calls.
    /// Matches CC's toolToAPISchema() pattern: calls tool.prompt() to get
    /// the LLM-facing description, passing tools and permission context.
    public func toolDefinitions() async -> [ToolDefinition] {
        let toolList = syncGetToolList()
        var defs: [ToolDefinition] = []
        let permContext = ToolPermissionContext()
        for tool in toolList {
            let desc = await tool.prompt(
                getToolPermissionContext: { permContext },
                tools: toolList,
                agents: [],
                allowedAgentTypes: nil
            )
            defs.append(ToolDefinition(name: tool.name, description: desc, inputSchema: tool.inputSchema))
        }
        return defs
    }

    /// Synchronous helper to copy tool list under lock.
    private func syncGetToolList() -> [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values)
    }

    /// Filter tools by deny rules — remove tools that match blanket deny patterns.
    /// Matches CC's filterToolsByDenyRules in tools.ts:
    /// iterates the tool pool before model sees it, removing disallowed tools.
    public func filterToolsByDenyRules(denyRules: [String]) async -> [ToolDefinition] {
        let toolList = syncGetToolList()
        var defs: [ToolDefinition] = []
        let permContext = ToolPermissionContext()
        for tool in toolList {
            // Check if tool name matches any deny rule
            let isDenied = denyRules.contains { rule in
                tool.name == rule || tool.aliases.contains(rule)
            }
            guard !isDenied else { continue }
            let desc = await tool.prompt(
                getToolPermissionContext: { permContext },
                tools: toolList,
                agents: [],
                allowedAgentTypes: nil
            )
            defs.append(ToolDefinition(name: tool.name, description: desc, inputSchema: tool.inputSchema))
        }
        return defs
    }
}
