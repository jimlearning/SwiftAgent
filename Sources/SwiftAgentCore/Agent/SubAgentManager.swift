import Foundation

/// Result of a sub-agent run.
public struct SubAgentResult: Sendable {
    public let agentId: String
    public let taskId: String
    public let output: String
    public let toolCalls: Int
    public let duration: TimeInterval

    public init(agentId: String, taskId: String, output: String, toolCalls: Int, duration: TimeInterval) {
        self.agentId = agentId
        self.taskId = taskId
        self.output = output
        self.toolCalls = toolCalls
        self.duration = duration
    }
}

/// Handle for a launched background sub-agent task.
public struct SubAgentTaskHandle: Sendable {
    public let taskId: String
    public let agentId: String
    public let agentName: String
    public let description: String

    public init(taskId: String, agentId: String, agentName: String, description: String) {
        self.taskId = taskId
        self.agentId = agentId
        self.agentName = agentName
        self.description = description
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
        tools: [ToolDefinition]? = nil,
        onEvent: ((StreamingQueryEvent) -> Void)? = nil
    ) async throws -> SubAgentResult {
        let task = await taskManager.create(
            name: definition.name,
            description: definition.description,
            type: .localAgent,
            prompt: input
        )
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
                tools: effectiveTools,
                querySource: .agent,
                onEvent: onEvent
            )
            let duration = Date().timeIntervalSince(startTime)
            await taskManager.markCompleted(task.id, result: result.text)
            return SubAgentResult(
                agentId: definition.id,
                taskId: task.id,
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

    /// Start a sub-agent in the background and return immediately with its task ID.
    public func startBackground(
        definition: AgentDefinition,
        input: String,
        taskDescription: String,
        context: AgentContext,
        state: AppState,
        tools: [ToolDefinition]? = nil
    ) async -> SubAgentTaskHandle {
        let task = await taskManager.create(
            name: definition.name,
            description: taskDescription,
            type: .localAgent,
            prompt: input
        )
        await taskManager.markRunning(task.id)
        await taskManager.appendOutput(task.id, "Started \(definition.name) sub-agent: \(taskDescription)\n")
        await taskManager.appendProgress(
            task.id,
            phase: .running,
            message: "Started \(definition.name) sub-agent: \(taskDescription)"
        )

        let taskManager = self.taskManager
        let engine = self.engine
        let effectiveTools = filterTools(tools, for: definition)

        let worker = Task {
            let startTime = Date()
            let conversation = Conversation(systemPrompt: definition.systemPrompt)

            do {
                let result = try await engine.run(
                    userInput: input,
                    conversation: conversation,
                    state: state,
                    tools: effectiveTools,
                    querySource: .agent,
                    onEvent: { event in
                        Task {
                            let progress = Self.backgroundProgress(
                                event,
                                agentName: definition.name,
                                taskDescription: taskDescription
                            )
                            await taskManager.appendOutput(task.id, progress.message + "\n")
                            await taskManager.appendProgress(
                                task.id,
                                phase: progress.phase,
                                message: progress.message,
                                toolName: progress.toolName,
                                turnNumber: progress.turnNumber,
                                toolCallCount: progress.toolCallCount
                            )
                        }
                    }
                )
                let duration = Date().timeIntervalSince(startTime)
                let message = "\(definition.name) sub-agent completed in \(String(format: "%.1f", duration))s"
                await taskManager.appendOutput(
                    task.id,
                    message + "\n"
                )
                await taskManager.markCompleted(task.id, result: result.text)
            } catch {
                let message = "\(definition.name) sub-agent failed: \(error.localizedDescription)"
                await taskManager.appendOutput(
                    task.id,
                    message + "\n"
                )
                await taskManager.markFailed(task.id, error: error.localizedDescription)
            }
            await taskManager.clearCancellationHandler(task.id)
        }
        await taskManager.registerCancellationHandler(task.id) {
            worker.cancel()
        }

        return SubAgentTaskHandle(
            taskId: task.id,
            agentId: definition.id,
            agentName: definition.name,
            description: taskDescription
        )
    }

    private func filterTools(_ tools: [ToolDefinition]?, for definition: AgentDefinition) -> [ToolDefinition]? {
        guard let tools else { return nil }
        let allowedNames = definition.effectiveTools(allToolNames: tools.map(\.name))
        return tools.filter { allowedNames.contains($0.name) }
    }

    struct BackgroundProgress: Sendable, Equatable {
        let phase: TaskProgressPhase
        let message: String
        let toolName: String?
        let detail: String?
        let turnNumber: Int?
        let toolCallCount: Int?
    }

    static func backgroundProgress(
        _ event: StreamingQueryEvent,
        agentName: String,
        taskDescription: String? = nil
    ) -> BackgroundProgress {
        let label = agentLabel(agentName: agentName, taskDescription: taskDescription)
        switch event {
        case .modelStreaming:
            return BackgroundProgress(
                phase: .thinking,
                message: "\(label) thinking",
                toolName: nil,
                detail: nil,
                turnNumber: nil,
                toolCallCount: nil
            )
        case .assistantTextStreaming:
            return BackgroundProgress(
                phase: .writingResults,
                message: "\(label) writing results",
                toolName: nil,
                detail: nil,
                turnNumber: nil,
                toolCallCount: nil
            )
        case .toolStarted(_, let toolName, let inputSummary):
            let detail = toolActivity(toolName: toolName, inputSummary: inputSummary)
            return BackgroundProgress(
                phase: .usingTool,
                message: "\(label) \(detail)",
                toolName: toolName,
                detail: detail,
                turnNumber: nil,
                toolCallCount: nil
            )
        case .toolCompleted(_, let toolName, _, let isError):
            let status = isError ? "failed" : "completed"
            return BackgroundProgress(
                phase: .running,
                message: "\(label) \(status) \(toolName)",
                toolName: toolName,
                detail: "\(status) \(toolName)",
                turnNumber: nil,
                toolCallCount: nil
            )
        case .toolProgress(_, let message):
            return BackgroundProgress(
                phase: .running,
                message: "\(label) \(message)",
                toolName: nil,
                detail: message,
                turnNumber: nil,
                toolCallCount: nil
            )
        case .turnComplete(let turnNumber, let toolCallCount):
            return BackgroundProgress(
                phase: .turnComplete,
                message: "\(label) turn \(turnNumber) complete (\(toolCallCount) tool call\(toolCallCount == 1 ? "" : "s"))",
                toolName: nil,
                detail: "turn \(turnNumber) complete",
                turnNumber: turnNumber,
                toolCallCount: toolCallCount
            )
        }
    }

    private static func agentLabel(agentName: String, taskDescription: String?) -> String {
        guard let taskDescription,
              !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return agentName
        }
        return "\(agentName) [\(compact(taskDescription, maxLength: 48))]"
    }

    private static func toolActivity(toolName: String, inputSummary: String?) -> String {
        let verb: String
        switch toolName {
        case "Grep":
            verb = "grepping"
        case "Read":
            verb = "reading"
        case "Glob":
            verb = "globbing"
        case "Bash":
            verb = "running"
        default:
            verb = "using \(toolName)"
        }

        guard let inputSummary, !inputSummary.isEmpty else {
            return verb
        }
        return "\(verb): \(compact(inputSummary, maxLength: 96))"
    }

    private static func compact(_ value: String, maxLength: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.count > maxLength ? String(singleLine.prefix(maxLength - 3)) + "..." : singleLine
    }
}
