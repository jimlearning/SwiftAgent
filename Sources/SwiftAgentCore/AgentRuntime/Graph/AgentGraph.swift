import Foundation

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
/// TYPE-SLOT ONLY — not implemented. Protocol surface reserved for
/// WWDC27 AgentGraph / WorkflowGraph. No execution logic.
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

/// Input to an agent graph node.
/// TYPE-SLOT ONLY — not implemented. Protocol surface reserved for
/// WWDC27 AgentGraph / WorkflowGraph. No execution logic.
public struct NodeInput: Sendable {
    public let name: String
    public let type: NodeIOType

    public init(name: String, type: NodeIOType) {
        self.name = name
        self.type = type
    }
}

/// Output from an agent graph node.
/// TYPE-SLOT ONLY — not implemented. Protocol surface reserved for
/// WWDC27 AgentGraph / WorkflowGraph. No execution logic.
public struct NodeOutput: Sendable {
    public let name: String
    public let type: NodeIOType

    public init(name: String, type: NodeIOType) {
        self.name = name
        self.type = type
    }
}

/// Type of a node input/output.
/// TYPE-SLOT ONLY — not implemented. Protocol surface reserved for
/// WWDC27 AgentGraph / WorkflowGraph. No execution logic.
public enum NodeIOType: Sendable {
    case string
    case json
    case transcript
    case toolOutput
}

/// Condition for node execution.
/// TYPE-SLOT ONLY — not implemented. Protocol surface reserved for
/// WWDC27 AgentGraph / WorkflowGraph. No execution logic.
public enum NodeCondition: Sendable {
    /// Always execute this node.
    case always

    /// Execute only if the named output is non-nil.
    case whenPresent(String)

    /// Execute only if the expression evaluates to true.
    case expression(String)
}
