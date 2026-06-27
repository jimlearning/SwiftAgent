import Foundation

// MARK: - GraphResult

/// The result of executing an entire agent graph.
public struct GraphResult: Sendable {
    /// Per-node results keyed by node name.
    public let nodeResults: [String: NodeExecutionResult]
    /// Total token usage across all nodes.
    public let totalUsage: Usage
}

/// The result of executing a single graph node.
public struct NodeExecutionResult: Sendable {
    /// The node's agent name.
    public let nodeName: String
    /// Node output values keyed by output name.
    public let outputs: [String: String]
    /// The final transcript from this node's session.
    public let transcript: Transcript
    /// Token usage for this node.
    public let usage: Usage?
}

// MARK: - GraphExecutor

/// Executes a `SimpleAgentGraph` by walking nodes in topological order,
/// threading upstream outputs into downstream instructions via template
/// substitution (`{{outputName}}`).
///
/// Each node gets its own `LanguageModelSession` created by the factory
/// closure, configured from the node's `AgentProfile` (instructions, tools, model).
///
/// ## Example
/// ```swift
/// let executor = GraphExecutor { profile in
///     LanguageModelSessionImpl(
///         modelProvider: myModel,
///         memoryStore: MockMemoryStore(),
///         permissionEngine: MockPermissionEngine(),
///         toolEngine: myToolEngine,
///         systemPrompt: profile.instructions
///     )
/// }
///
/// let result = try await executor.run(
///     graph: graph,
///     initialPrompt: "Build a REST API for a todo app"
/// )
///
/// for (name, nodeResult) in result.nodeResults {
///     print("[\(name)] → \(nodeResult.outputs)")
/// }
/// ```
public struct GraphExecutor: Sendable {

    /// Factory that creates a LanguageModelSession for a given AgentProfile.
    public let sessionFactory: @Sendable (AgentProfile) async -> any LanguageModelSession

    public init(
        sessionFactory: @escaping @Sendable (AgentProfile) async -> any LanguageModelSession
    ) {
        self.sessionFactory = sessionFactory
    }

    // MARK: - Run

    /// Execute all nodes in the graph in topological order.
    ///
    /// - Parameters:
    ///   - graph: The graph to execute.
    ///   - initialPrompt: The initial user prompt fed to the first node(s).
    /// - Returns: `GraphResult` with per-node outputs and aggregate usage.
    /// - Throws: `AgentGraphError` for structural failures, `AgentRuntimeError` for execution failures.
    public func run(
        graph: SimpleAgentGraph,
        initialPrompt: String
    ) async throws -> GraphResult {
        // 1. Validate graph structure
        try graph.validate()

        // 2. Topological sort
        let sorted = try graph.topologicalSort()

        // 3. Execute nodes in order, accumulating outputs
        var outputValues: [String: [String: String]] = [:]  // nodeName → outputValues
        var nodeResults: [String: NodeExecutionResult] = [:]
        var totalTokens: Double = 0

        // Expose the initial prompt as a pseudo-output so root nodes can
        // reference it via `{{input}}`.
        outputValues["__input__"] = ["input": initialPrompt]

        for node in sorted {
            // 3a. Resolve upstream outputs
            let upstream = graph.resolveUpstream(for: node, outputValues: outputValues)

            // 3b. Check condition
            if let condition = node.condition {
                switch condition {
                case .always:
                    break
                case .whenPresent(let name):
                    guard upstream[name] != nil else { continue }
                case .expression:
                    break  // expression evaluation not yet implemented
                }
            }

            // 3c. Compose prompt with template substitution
            var prompt = composePrompt(
                instructions: node.agent.instructions,
                upstream: upstream,
                initialPrompt: initialPrompt
            )

            // 3d. Create session and execute
            let session = await sessionFactory(node.agent)
            let response = try await session.respond(to: prompt)

            // 3e. Extract outputs
            let responseText = extractResponseText(from: response.transcript)
            var outputs: [String: String] = [:]
            for output in node.outputs {
                outputs[output.name] = responseText
            }

            outputValues[node.agent.name] = outputs

            // 3f. Record usage
            if let usage = response.usage {
                totalTokens += Double(usage.inputTokens + usage.outputTokens
                    + usage.cacheCreationInputTokens + usage.cacheReadInputTokens)
            }

            nodeResults[node.agent.name] = NodeExecutionResult(
                nodeName: node.agent.name,
                outputs: outputs,
                transcript: response.transcript,
                usage: response.usage
            )
        }

        return GraphResult(
            nodeResults: nodeResults,
            totalUsage: Usage(inputTokens: Int(totalTokens))
        )
    }

    // MARK: - Private Helpers

    /// Compose the prompt for a node by substituting `{{outputName}}` templates
    /// in the instructions with upstream output values.
    private func composePrompt(
        instructions: String,
        upstream: [String: String],
        initialPrompt: String
    ) -> String {
        var result = instructions

        // Merge initial prompt as "input" if not overridden by upstream
        var allVars = upstream
        if allVars["input"] == nil {
            allVars["input"] = initialPrompt
        }

        for (key, value) in allVars {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // If no templates were substituted, the instructions ARE the prompt.
        // Prepend the initial prompt so the model has context.
        if !instructions.contains("{{") {
            return "\(initialPrompt)\n\n\(instructions)"
        }

        return result
    }

    /// Extract the final model response text from a transcript.
    private func extractResponseText(from transcript: Transcript) -> String {
        // Walk backwards to find the last response entry
        for entry in transcript.entries.reversed() {
            if case .response(let text) = entry {
                return text
            }
        }
        // Fallback: return the last thinking or prompt entry
        for entry in transcript.entries.reversed() {
            switch entry {
            case .thinking(let text, _): return text
            case .prompt(let text): return text
            default: break
            }
        }
        return ""
    }
}
