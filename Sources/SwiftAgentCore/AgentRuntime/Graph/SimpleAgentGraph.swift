import Foundation

// MARK: - SimpleAgentNode

/// Concrete implementation of `AgentNode` for graph-based agent workflows.
///
/// Each node wraps an `AgentProfile` (instructions, tools, model) with declared
/// inputs (consumed from upstream nodes) and outputs (produced for downstream nodes).
///
/// ## Example
/// ```swift
/// let plannerNode = SimpleAgentNode(
///     agent: AgentProfile(name: "Planner", instructions: "Create a plan for: {{task}}"),
///     inputs: [NodeInput(name: "task", type: .string)],
///     outputs: [NodeOutput(name: "plan", type: .string)]
/// )
/// ```
public struct SimpleAgentNode: AgentNode, Sendable {
    public let agent: AgentProfile
    public let inputs: [NodeInput]
    public let outputs: [NodeOutput]
    public let condition: NodeCondition?

    public init(
        agent: AgentProfile,
        inputs: [NodeInput] = [],
        outputs: [NodeOutput] = [],
        condition: NodeCondition? = nil
    ) {
        self.agent = agent
        self.inputs = inputs
        self.outputs = outputs
        self.condition = condition
    }
}

// MARK: - SimpleAgentGraph

/// Concrete implementation of `AgentGraph` — an ordered DAG of agent nodes.
///
/// Nodes execute in topological order. Each node receives outputs from upstream
/// nodes via template substitution in its instructions (`{{outputName}}`).
///
/// ## Example
/// ```swift
/// let graph = SimpleAgentGraph(nodes: [
///     SimpleAgentNode(
///         agent: AgentProfile(name: "Planner", instructions: "Plan: {{task}}"),
///         inputs: [NodeInput(name: "task", type: .string)],
///         outputs: [NodeOutput(name: "plan", type: .string)]
///     ),
///     SimpleAgentNode(
///         agent: AgentProfile(name: "Coder", instructions: "Implement per plan:\n{{plan}}"),
///         inputs: [NodeInput(name: "plan", type: .string)],
///         outputs: [NodeOutput(name: "code", type: .string)]
///     ),
/// ])
/// ```
public struct SimpleAgentGraph: AgentGraph, Sendable {
    public let nodes: [any AgentNode]

    public init(nodes: [any AgentNode]) {
        self.nodes = nodes
    }

    /// Validate the graph structure:
    /// - No duplicate node names
    /// - All input references are satisfiable by upstream outputs
    /// - No cycles (topological sort succeeds)
    public func validate() throws {
        // 1. No duplicate node names
        let names = nodes.map { $0.agent.name }
        let nameSet = Set(names)
        guard names.count == nameSet.count else {
            let duplicates = names.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
                .filter { $0.value > 1 }.keys.sorted()
            throw AgentGraphError.duplicateNodeNames(Array(duplicates))
        }

        // 2. All input references satisfiable
        let allOutputs = Set(nodes.flatMap { $0.outputs.map(\.name) })
        for node in nodes {
            for input in node.inputs {
                guard allOutputs.contains(input.name) else {
                    throw AgentGraphError.unsatisfiedInput(
                        node: node.agent.name,
                        input: input.name
                    )
                }
            }

            // 3. Check node conditions reference existing outputs
            if let condition = node.condition {
                switch condition {
                case .whenPresent(let outputName), .expression(let outputName):
                    guard allOutputs.contains(outputName) else {
                        throw AgentGraphError.unsatisfiedCondition(
                            node: node.agent.name,
                            reference: outputName
                        )
                    }
                case .always:
                    break
                }
            }
        }

        // 4. No cycles — topological sort
        _ = try topologicalSort()
    }

    /// Return nodes in topological (execution) order.
    /// Throws if a cycle is detected.
    public func topologicalSort() throws -> [any AgentNode] {
        let nodeNames = nodes.map { $0.agent.name }

        // Build adjacency: for each node, which downstream nodes consume its outputs?
        // A downstream node depends on an upstream node if one of the downstream's
        // inputs matches one of the upstream's outputs.
        var adjacency: [Int: [Int]] = [:]   // upstream index → downstream indices
        var inDegree: [Int] = Array(repeating: 0, count: nodes.count)

        for (upIdx, upstream) in nodes.enumerated() {
            let upstreamOutputs = Set(upstream.outputs.map(\.name))
            for (downIdx, downstream) in nodes.enumerated() where upIdx != downIdx {
                let downstreamRequiredInputs = Set(downstream.inputs.map(\.name))
                if !upstreamOutputs.intersection(downstreamRequiredInputs).isEmpty {
                    adjacency[upIdx, default: []].append(downIdx)
                    inDegree[downIdx] += 1
                }
            }
        }

        // Kahn's algorithm
        var queue: [Int] = (0..<nodes.count).filter { inDegree[$0] == 0 }
        var sorted: [any AgentNode] = []

        while !queue.isEmpty {
            let idx = queue.removeFirst()
            sorted.append(nodes[idx])
            for downIdx in adjacency[idx] ?? [] {
                inDegree[downIdx] -= 1
                if inDegree[downIdx] == 0 {
                    queue.append(downIdx)
                }
            }
        }

        guard sorted.count == nodes.count else {
            // Find nodes involved in the cycle for error reporting
            let remaining = (0..<nodes.count).filter { inDegree[$0] > 0 }
            let cycleNodeNames = remaining.map { nodes[$0].agent.name }
            throw AgentGraphError.cycleDetected(nodes: cycleNodeNames)
        }

        return sorted
    }

    /// Resolve which upstream node provides a given input for a downstream node.
    /// Returns the output value keyed by output name from the upstream node.
    public func resolveUpstream(for node: any AgentNode, outputValues: [String: [String: String]]) -> [String: String] {
        var resolved: [String: String] = [:]
        for input in node.inputs {
            for (_, outputs) in outputValues {
                if let value = outputs[input.name] {
                    resolved[input.name] = value
                    break
                }
            }
        }
        return resolved
    }
}

// MARK: - AgentGraphError

/// Errors specific to graph structure validation and execution.
public enum AgentGraphError: Error, Sendable {
    /// Two or more nodes share the same name.
    case duplicateNodeNames([String])

    /// A node's input cannot be satisfied by any upstream output.
    case unsatisfiedInput(node: String, input: String)

    /// A node's condition references a non-existent output.
    case unsatisfiedCondition(node: String, reference: String)

    /// A cycle was detected in the node dependencies.
    case cycleDetected(nodes: [String])
}
