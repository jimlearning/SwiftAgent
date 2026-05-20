import Foundation

/// Result of a sub-agent run.
public struct SubAgentResult: Sendable {
    public let agentId: String
    public let output: String
    public let toolCalls: Int
    public let duration: TimeInterval

    public init(agentId: String, output: String, toolCalls: Int, duration: TimeInterval) {
        self.agentId = agentId
        self.output = output
        self.toolCalls = toolCalls
        self.duration = duration
    }
}

/// Manages sub-agent creation and execution with context isolation.
public struct SubAgentManager: Sendable {
    private let engine: QueryEngine
    private let taskManager: TaskManager

    public init(engine: QueryEngine, taskManager: TaskManager = TaskManager()) {
        self.engine = engine
        self.taskManager = taskManager
    }

    /// Run a sub-agent with an isolated conversation context.
    public func run(
        definition: AgentDefinition,
        input: String,
        context: AgentContext,
        state: AppState,
        tools: [ToolDefinition]? = nil
    ) async throws -> SubAgentResult {
        let task = await taskManager.create(name: definition.name, description: definition.description)
        await taskManager.markRunning(task.id)

        let startTime = Date()
        let conversation = Conversation(
            systemPrompt: definition.systemPrompt
        )

        // Filter tools if agent has restricted tool set
        let effectiveTools: [ToolDefinition]?
        if let tools = tools {
            let allowedNames = definition.effectiveTools(allToolNames: tools.map(\.name))
            effectiveTools = tools.filter { allowedNames.contains($0.name) }
        } else {
            effectiveTools = nil
        }

        do {
            let result = try await engine.run(
                userInput: input,
                conversation: conversation,
                state: state,
                tools: effectiveTools
            )
            let duration = Date().timeIntervalSince(startTime)
            await taskManager.markCompleted(task.id, result: result.text)
            return SubAgentResult(
                agentId: definition.id,
                output: result.text,
                toolCalls: result.totalToolCalls,
                duration: duration
            )
        } catch {
            _ = Date().timeIntervalSince(startTime)
            await taskManager.markFailed(task.id, error: error.localizedDescription)
            throw error
        }
    }
}
