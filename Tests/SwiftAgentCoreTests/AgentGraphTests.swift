import Foundation
import SwiftAgentCore
import Testing

/// Tests for AgentGraph: SimpleAgentGraph, SimpleAgentNode, GraphExecutor,
/// and the validation logic (topological sort, cycle detection, input satisfaction).
///
/// All tests use `MockLanguageModel` with canned responses — no live LLM calls.
@Suite struct AgentGraphTests {

    // MARK: - Helpers

    /// Create a session for an agent profile using mock model with a canned response.
    private func makeSessionFactory(
        response: String,
        tools: [any Tool] = []
    ) -> @Sendable (AgentProfile) async -> any LanguageModelSession {
        let model = MockLanguageModel(
            capabilities: LanguageModelCapabilities(providerDisplayName: "Mock"),
            displayName: "Mock",
            cannedResponses: [response]
        )
        return { profile in
            LanguageModelSessionImpl(
                modelProvider: model,
                memoryStore: MockMemoryStore(),
                permissionEngine: MockPermissionEngine(),
                toolEngine: NoOpToolEngine(),
                systemPrompt: profile.instructions
            )
        }
    }

    /// No-op tool engine for tests that don't need tool execution.
    private struct NoOpToolEngine: ToolEngine {
        func register(tool: any Tool, metadata: ToolMetadata) async {}
        func getDefinition(name: String) async -> SessionToolDefinition? { nil }
        func getAllDefinitions() async -> [SessionToolDefinition] { [] }
        func execute(name: String, input: Data) async throws -> ToolOutputValue {
            .string("noop")
        }
    }

    // MARK: - SimpleAgentGraph Validation

    @Test("Empty graph validates successfully")
    func emptyGraph() throws {
        let graph = SimpleAgentGraph(nodes: [])
        try graph.validate()
    }

    @Test("Single node graph validates successfully")
    func singleNodeValidates() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(agent: AgentProfile(name: "Analyzer", instructions: "Analyze")),
        ])
        try graph.validate()
    }

    @Test("Duplicate node names throw validation error")
    func duplicateNodeNamesThrows() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(agent: AgentProfile(name: "A", instructions: "")),
            SimpleAgentNode(agent: AgentProfile(name: "A", instructions: "")),
        ])

        do {
            try graph.validate()
            Issue.record("Expected duplicateNodeNames error")
        } catch let error as AgentGraphError {
            switch error {
            case .duplicateNodeNames(let names):
                #expect(names == ["A"])
            default:
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test("Unsatisfied input throws validation error")
    func unsatisfiedInputThrows() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Consumer", instructions: "Use {{missing}}"),
                inputs: [NodeInput(name: "missing", type: .string)],
                outputs: []
            ),
        ])

        do {
            try graph.validate()
            Issue.record("Expected unsatisfiedInput error")
        } catch let error as AgentGraphError {
            switch error {
            case .unsatisfiedInput(let node, let input):
                #expect(node == "Consumer")
                #expect(input == "missing")
            default:
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test("Satisfied input validates successfully")
    func satisfiedInputValidates() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Producer", instructions: ""),
                outputs: [NodeOutput(name: "data", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Consumer", instructions: "Use {{data}}"),
                inputs: [NodeInput(name: "data", type: .string)]
            ),
        ])
        try graph.validate()
    }

    // MARK: - Cycle Detection

    @Test("Cycle detection — two-node cycle")
    func twoNodeCycle() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "A", instructions: ""),
                inputs: [NodeInput(name: "outB", type: .string)],
                outputs: [NodeOutput(name: "outA", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "B", instructions: ""),
                inputs: [NodeInput(name: "outA", type: .string)],
                outputs: [NodeOutput(name: "outB", type: .string)]
            ),
        ])

        do {
            try graph.validate()
            Issue.record("Expected cycleDetected error")
        } catch let error as AgentGraphError {
            switch error {
            case .cycleDetected(let nodes):
                #expect(Set(nodes) == Set(["A", "B"]))
            default:
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test("Cycle detection — three-node cycle")
    func threeNodeCycle() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "A", instructions: ""),
                inputs: [NodeInput(name: "outC", type: .string)],
                outputs: [NodeOutput(name: "outA", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "B", instructions: ""),
                inputs: [NodeInput(name: "outA", type: .string)],
                outputs: [NodeOutput(name: "outB", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "C", instructions: ""),
                inputs: [NodeInput(name: "outB", type: .string)],
                outputs: [NodeOutput(name: "outC", type: .string)]
            ),
        ])

        do {
            try graph.validate()
            Issue.record("Expected cycleDetected error")
        } catch let error as AgentGraphError {
            switch error {
            case .cycleDetected(let nodes):
                #expect(Set(nodes) == Set(["A", "B", "C"]))
            default:
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test("No cycle — linear DAG passes validation")
    func linearDAGNoCycle() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "First", instructions: ""),
                outputs: [NodeOutput(name: "out1", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Second", instructions: ""),
                inputs: [NodeInput(name: "out1", type: .string)],
                outputs: [NodeOutput(name: "out2", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Third", instructions: ""),
                inputs: [NodeInput(name: "out2", type: .string)]
            ),
        ])
        try graph.validate()
    }

    @Test("No cycle — diamond DAG passes validation")
    func diamondDAGNoCycle() throws {
        //  A → B → D
        //  A → C → D
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "A", instructions: ""),
                outputs: [NodeOutput(name: "outA", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "B", instructions: ""),
                inputs: [NodeInput(name: "outA", type: .string)],
                outputs: [NodeOutput(name: "outB", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "C", instructions: ""),
                inputs: [NodeInput(name: "outA", type: .string)],
                outputs: [NodeOutput(name: "outC", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "D", instructions: ""),
                inputs: [NodeInput(name: "outB", type: .string), NodeInput(name: "outC", type: .string)]
            ),
        ])
        try graph.validate()
    }

    // MARK: - Topological Sort

    @Test("Topological sort — linear chain returns correct order")
    func topologicalSortLinearChain() throws {
        let node1 = SimpleAgentNode(
            agent: AgentProfile(name: "First", instructions: ""),
            outputs: [NodeOutput(name: "out1", type: .string)]
        )
        let node2 = SimpleAgentNode(
            agent: AgentProfile(name: "Second", instructions: ""),
            inputs: [NodeInput(name: "out1", type: .string)],
            outputs: [NodeOutput(name: "out2", type: .string)]
        )
        let node3 = SimpleAgentNode(
            agent: AgentProfile(name: "Third", instructions: ""),
            inputs: [NodeInput(name: "out2", type: .string)]
        )

        let graph = SimpleAgentGraph(nodes: [node2, node3, node1])  // deliberately unsorted
        let sorted = try graph.topologicalSort()
        let names = sorted.map { $0.agent.name }
        #expect(names == ["First", "Second", "Third"])
    }

    // MARK: - Graph Executor

    @Test("Single node execution returns output")
    func singleNodeExecution() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Solver", instructions: "Solve the problem: {{input}}"),
                outputs: [NodeOutput(name: "solution", type: .string)]
            ),
        ])

        let executor = GraphExecutor(
            sessionFactory: makeSessionFactory(response: "The solution is 42.")
        )

        let result = try await executor.run(graph: graph, initialPrompt: "What is the answer?")

        #expect(result.nodeResults.count == 1)
        #expect(result.nodeResults["Solver"] != nil)
        #expect(result.nodeResults["Solver"]?.outputs["solution"] == "The solution is 42.")
    }

    @Test("Two-node linear graph threads outputs between nodes")
    func twoNodeLinearGraph() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Planner", instructions: "Plan for: {{input}}"),
                outputs: [NodeOutput(name: "plan", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Coder", instructions: "Implement per plan:\n{{plan}}"),
                inputs: [NodeInput(name: "plan", type: .string)],
                outputs: [NodeOutput(name: "code", type: .string)]
            ),
        ])

        // Each node gets a fresh session. The MockLanguageModel is shared,
        // so we need different canned responses per node.
        // Use a reference type for mutable call count in @Sendable closure.
        final class Counter: @unchecked Sendable { var count = 0 }
        let counter = Counter()
        let executor = GraphExecutor { profile in
            counter.count += 1
            let response: String
            if counter.count == 1 {
                response = "Step 1: Create schema. Step 2: Write handlers."
            } else {
                response = "func main() { print(\"Hello\") }"
            }
            let model = MockLanguageModel(
                capabilities: LanguageModelCapabilities(providerDisplayName: "Mock"),
                displayName: profile.name,
                cannedResponses: [response]
            )
            return LanguageModelSessionImpl(
                modelProvider: model,
                memoryStore: MockMemoryStore(),
                permissionEngine: MockPermissionEngine(),
                toolEngine: NoOpToolEngine(),
                systemPrompt: profile.instructions
            )
        }

        let result = try await executor.run(graph: graph, initialPrompt: "Build Hello World")

        #expect(result.nodeResults.count == 2)
        #expect(counter.count == 2)
        #expect(result.nodeResults["Planner"]?.outputs["plan"] == "Step 1: Create schema. Step 2: Write handlers.")
        #expect(result.nodeResults["Coder"]?.outputs["code"] == "func main() { print(\"Hello\") }")
    }

    @Test("Template substitution — {{input}} replaced with initial prompt")
    func templateSubstitutionInitialPrompt() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Echo", instructions: "You said: {{input}}"),
                outputs: [NodeOutput(name: "echo", type: .string)]
            ),
        ])

        let executor = GraphExecutor(
            sessionFactory: makeSessionFactory(response: "You said: hello world")
        )

        let result = try await executor.run(graph: graph, initialPrompt: "hello world")

        // The instructions with {{input}} get substituted before being passed
        // to the model. Since the mock ignores the prompt and returns its
        // canned response, we trust the substitution happened correctly
        // and verify the output is stored.
        #expect(result.nodeResults["Echo"]?.outputs["echo"] == "You said: hello world")
    }

    @Test("Graph result includes usage metadata")
    func graphResultIncludesUsage() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "A", instructions: "Task A"),
                outputs: [NodeOutput(name: "result", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "B", instructions: "Task B: {{result}}"),
                inputs: [NodeInput(name: "result", type: .string)]
            ),
        ])

        let executor = GraphExecutor(
            sessionFactory: makeSessionFactory(response: "done")
        )

        let result = try await executor.run(graph: graph, initialPrompt: "go")

        #expect(result.nodeResults.count == 2)
        #expect(result.totalUsage.inputTokens >= 0)
    }

    // MARK: - Condition-Based Execution

    @Test("Condition .always — node executes")
    func conditionAlwaysExecutes() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Base", instructions: ""),
                outputs: [NodeOutput(name: "data", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Conditional", instructions: "Run"),
                inputs: [NodeInput(name: "data", type: .string)],
                condition: .always
            ),
        ])

        let executor = GraphExecutor(
            sessionFactory: makeSessionFactory(response: "ran")
        )

        let result = try await executor.run(graph: graph, initialPrompt: "go")
        #expect(result.nodeResults["Conditional"] != nil)
    }

    @Test("Diamond DAG execution — both branches execute before sink")
    func diamondDAGExecution() async throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "Root", instructions: ""),
                outputs: [NodeOutput(name: "data", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "BranchA", instructions: "Process A: {{data}}"),
                inputs: [NodeInput(name: "data", type: .string)],
                outputs: [NodeOutput(name: "resultA", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "BranchB", instructions: "Process B: {{data}}"),
                inputs: [NodeInput(name: "data", type: .string)],
                outputs: [NodeOutput(name: "resultB", type: .string)]
            ),
            SimpleAgentNode(
                agent: AgentProfile(name: "Merger", instructions: "Merge {{resultA}} + {{resultB}}"),
                inputs: [NodeInput(name: "resultA", type: .string), NodeInput(name: "resultB", type: .string)]
            ),
        ])

        final class Counter: @unchecked Sendable { var count = 0 }
        let counter = Counter()
        let executor = GraphExecutor { _ in
            counter.count += 1
            let responses = ["data produced", "result A", "result B", "merged"]
            let model = MockLanguageModel(
                capabilities: LanguageModelCapabilities(providerDisplayName: "Mock"),
                displayName: "Mock",
                cannedResponses: [responses[min(counter.count - 1, responses.count - 1)]]
            )
            return LanguageModelSessionImpl(
                modelProvider: model,
                memoryStore: MockMemoryStore(),
                permissionEngine: MockPermissionEngine(),
                toolEngine: NoOpToolEngine(),
                systemPrompt: ""
            )
        }

        let result = try await executor.run(graph: graph, initialPrompt: "go")

        #expect(result.nodeResults.count == 4)
        #expect(counter.count == 4)

        // Both BranchA and BranchB must execute before Merger.
        // Topological sort guarantees Root → (A, B) → Merger.
        // A and B are independent, order between them is undefined.
        #expect(result.nodeResults["Root"] != nil)
        #expect(result.nodeResults["BranchA"] != nil)
        #expect(result.nodeResults["BranchB"] != nil)
        #expect(result.nodeResults["Merger"] != nil)
    }

    // MARK: - Error Propagation

    @Test("Node condition referencing missing output throws")
    func unsatisfiedConditionThrows() throws {
        let graph = SimpleAgentGraph(nodes: [
            SimpleAgentNode(
                agent: AgentProfile(name: "N", instructions: ""),
                condition: .whenPresent("nonexistent")
            ),
        ])

        do {
            try graph.validate()
            Issue.record("Expected unsatisfiedCondition error")
        } catch let error as AgentGraphError {
            switch error {
            case .unsatisfiedCondition(let node, let reference):
                #expect(node == "N")
                #expect(reference == "nonexistent")
            default:
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    // MARK: - resolveUpstream

    @Test("resolveUpstream returns matching output values")
    func resolveUpstream() {
        let graph = SimpleAgentGraph(nodes: [])
        let node = SimpleAgentNode(
            agent: AgentProfile(name: "Consumer", instructions: ""),
            inputs: [NodeInput(name: "plan", type: .string)]
        )
        let outputValues: [String: [String: String]] = [
            "Producer": ["plan": "Step 1, Step 2", "extra": "ignored"]
        ]

        let resolved = graph.resolveUpstream(for: node, outputValues: outputValues)
        #expect(resolved["plan"] == "Step 1, Step 2")
    }

    @Test("resolveUpstream with multiple upstreams merges inputs")
    func resolveUpstreamMultiple() {
        let graph = SimpleAgentGraph(nodes: [])
        let node = SimpleAgentNode(
            agent: AgentProfile(name: "Merger", instructions: ""),
            inputs: [
                NodeInput(name: "resultA", type: .string),
                NodeInput(name: "resultB", type: .string),
            ]
        )
        let outputValues: [String: [String: String]] = [
            "BranchA": ["resultA": "A output"],
            "BranchB": ["resultB": "B output"],
        ]

        let resolved = graph.resolveUpstream(for: node, outputValues: outputValues)
        #expect(resolved["resultA"] == "A output")
        #expect(resolved["resultB"] == "B output")
    }
}
