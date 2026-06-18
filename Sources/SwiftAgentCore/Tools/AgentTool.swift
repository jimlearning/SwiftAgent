import Foundation

// MARK: - AgentTool

/// Dispatches work to specialized sub-agents.
/// Matches Claude Code's AgentTool.
public struct AgentTool: Tool {
    public let name = "Agent"
    public var aliases: [String] { ["Task"] }
    public var searchHint: String? { "delegate work to a subagent" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Launch a new agent to handle complex, multi-step tasks autonomously. Each agent type has specific capabilities and tools available to it. Available agent types: general-purpose (catch-all), Explore (codebase search), Plan (architecture planning), verification (check completed work)." }

    /// Dynamic prompt matching CC's AgentTool.prompt() — lists available agents,
    /// filters by MCP server availability and permission rules, and handles
    /// coordinator mode detection.
    public func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String {
        let agentDefinitions = agents.compactMap { $0 as? AgentDefinition }
        let availableAgents = agentDefinitions.isEmpty ? BuiltInAgents.all.values.map { $0 } : agentDefinitions

        // Filter by allowedAgentTypes if specified
        let filtered: [AgentDefinition]
        if let allowed = allowedAgentTypes {
            filtered = availableAgents.filter { allowed.contains($0.name) }
        } else {
            filtered = availableAgents
        }

        // Build agent descriptions
        let agentDescriptions = filtered.map { agent in
            var parts: [String] = ["- **\(agent.name)**"]
            if let tools = agent.tools, tools != ["*"] {
                parts.append(": Tools: \(tools.joined(separator: ", "))")
            } else if let disallowed = agent.disallowedTools, !disallowed.isEmpty {
                parts.append(": All tools except \(disallowed.joined(separator: ", "))")
            } else {
                parts.append(": All tools")
            }
            return parts.joined()
        }.joined(separator: "\n")

        let agentSection = agentDescriptions.isEmpty
            ? ""
            : "\n\nAvailable agent types and the tools they have access to:\n\(agentDescriptions)"

        return "Launch a new agent to handle complex, multi-step tasks. Each agent type has specific capabilities and tools available to it.\(agentSection)"
    }

    public let isReadOnly = false
    public let isConcurrencySafe = true
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "A short (3-5 word) description of the task")
        schema.properties?["prompt"] = JSONSchemaProperty(type: "string", description: "The task for the agent to perform")
        schema.properties?["subagentType"] = JSONSchemaProperty(type: "string", description: "The type of specialized agent to use for this task. Available types: general-purpose, Explore, Plan, verification. Defaults to general-purpose if omitted.")
        schema.properties?["model"] = JSONSchemaProperty(type: "string", description: "Optional model override for this agent.", enum: ["sonnet", "opus", "haiku"])
        schema.properties?["runInBackground"] = JSONSchemaProperty(type: "boolean", description: "Set to true to run this agent in the background. You will be notified when it completes.")
        schema.properties?["name"] = JSONSchemaProperty(type: "string", description: "Optional display name for the agent (multi-agent mode).")
        schema.properties?["teamName"] = JSONSchemaProperty(type: "string", description: "Optional team name for routing (multi-team mode).")
        schema.properties?["mode"] = JSONSchemaProperty(type: "string", description: "Optional permission mode override for this agent.", enum: ["default", "acceptEdits", "plan"])
        schema.properties?["isolation"] = JSONSchemaProperty(type: "string", description: "Isolation mode for the agent: \"worktree\" creates a temporary git worktree.", enum: ["worktree"])
        schema.properties?["cwd"] = JSONSchemaProperty(type: "string", description: "Optional working directory override for the agent.")
        schema.required = ["description", "prompt"]
        return schema
    }()

    private let subAgentManager: SubAgentManager?

    public init(subAgentManager: SubAgentManager? = nil) {
        self.subAgentManager = subAgentManager
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let descVal = input["description"], case .string(let taskDesc) = descVal else {
            return ToolResult(content: "Error: description is required", isError: true)
        }
        guard let promptVal = input["prompt"], case .string(let prompt) = promptVal else {
            return ToolResult(content: "Error: prompt is required", isError: true)
        }

        let subagentType: String
        if let t = input["subagentType"], case .string(let s) = t { subagentType = s }
        else { subagentType = "general-purpose" }

        let runInBackground: Bool
        if let b = input["runInBackground"] {
            if case .bool(let v) = b { runInBackground = v }
            else if case .string(let s) = b { runInBackground = s.lowercased() == "true" }
            else { runInBackground = false }
        } else { runInBackground = false }

        // Resolve agent definition
        guard let definition = BuiltInAgents.resolve(subagentType) else {
            let available = BuiltInAgents.all.keys.sorted().joined(separator: ", ")
            return ToolResult(content: "Unknown agent type \"\(subagentType)\". Available types: \(available)", isError: true)
        }

        guard let manager = subAgentManager else {
            return ToolResult(
                content: "Error: sub-agent execution is not configured. The Agent tool must be registered with a SubAgentManager before it can run \(definition.name).",
                isError: true
            )
        }

        let agentContext = AgentContext(
            parentSessionId: context.sessionID,
            workingDirectory: context.workingDirectory,
            permissionMode: definition.permissionMode ?? context.mode,
            settings: subAgentSettings(definition: definition, input: input, context: context)
        )

        let state = AppState(settings: agentContext.settings, permissionMode: agentContext.permissionMode)
        let toolDefinitions = await buildToolDefinitions(from: context, allowedAgentTypes: nil)
        let progressID = context.toolUseID ?? "Agent"

        if runInBackground {
            let handle = await manager.startBackground(
                definition: definition,
                input: prompt,
                taskDescription: taskDesc,
                context: agentContext,
                state: state,
                tools: toolDefinitions
            )
            emitProgress(
                onProgress,
                toolUseID: progressID,
                message: "Started \(definition.name) sub-agent in background: \(taskDesc)"
            )
            return ToolResult(
                content: backgroundLaunchJSON(handle)
            )
        }

        emitProgress(
            onProgress,
            toolUseID: progressID,
            message: "Starting \(definition.name) sub-agent: \(taskDesc)"
        )

        do {
            let result = try await manager.run(
                definition: definition,
                input: prompt,
                context: agentContext,
                state: state,
                tools: toolDefinitions,
                onEvent: { event in
                    forwardSubAgentEvent(event, agentName: definition.name, toolUseID: progressID, onProgress: onProgress)
                }
            )
            emitProgress(
                onProgress,
                toolUseID: progressID,
                message: "\(definition.name) sub-agent completed in \(String(format: "%.1f", result.duration))s"
            )
            return ToolResult(content: """
                Agent \"\(definition.name)\" completed (ID: \(result.agentId), task: \(result.taskId))
                Tool calls: \(result.toolCalls)
                Duration: \(String(format: "%.1f", result.duration))s

                Result:
                \(result.output)
                """)
        } catch {
            emitProgress(
                onProgress,
                toolUseID: progressID,
                message: "\(definition.name) sub-agent failed: \(error.localizedDescription)"
            )
            return ToolResult(content: "Agent error: \(error.localizedDescription)", isError: true)
        }
    }

    private func subAgentSettings(
        definition: AgentDefinition,
        input: [String: JSONValue],
        context: ToolUseContext
    ) -> Settings {
        let mainModel = context.mainLoopModel ?? ModelRegistry.shared.defaultModel
        var modelID = definition.model?.modelID ?? mainModel
        if let modelValue = input["model"], case .string(let requestedModel) = modelValue {
            modelID = ModelRegistry.shared.resolveModel(requestedModel)
        }

        return Settings(
            model: ModelConfig(modelID: modelID),
            permissionMode: definition.permissionMode ?? context.mode,
            maxTokens: 8192,
            thinking: context.thinkingConfig
        )
    }

    private func buildToolDefinitions(
        from context: ToolUseContext,
        allowedAgentTypes: [String]?
    ) async -> [ToolDefinition]? {
        guard let tools = context.tools else { return nil }

        let permissionContext = ToolPermissionContext()
        let agents = context.agentDefinitions ?? BuiltInAgents.all.values.map { $0 }
        var definitions: [ToolDefinition] = []
        definitions.reserveCapacity(tools.count)

        for tool in tools {
            let description = await tool.prompt(
                getToolPermissionContext: { permissionContext },
                tools: tools,
                agents: agents,
                allowedAgentTypes: allowedAgentTypes
            )
            definitions.append(ToolDefinition(name: tool.name, description: description, inputSchema: tool.inputSchema))
        }

        return definitions
    }

    private func forwardSubAgentEvent(
        _ event: StreamingQueryEvent,
        agentName: String,
        toolUseID: String,
        onProgress: ToolCallProgress?
    ) {
        switch event {
        case .textDelta, .thinkingDelta:
            break // Text/thinking deltas don't need progress reporting
        case .modelStreaming:
            emitProgress(onProgress, toolUseID: toolUseID, message: "\(agentName) is thinking")
        case .assistantTextStreaming:
            emitProgress(onProgress, toolUseID: toolUseID, message: "\(agentName) is writing results")
        case .toolStarted:
            let detail = SubAgentManager.backgroundProgress(
                event,
                agentName: agentName
            ).detail ?? "using tool"
            emitProgress(onProgress, toolUseID: toolUseID, message: "\(agentName) \(detail)")
        case .toolCompleted(_, let toolName, _, let isError):
            let status = isError ? "failed" : "completed"
            emitProgress(onProgress, toolUseID: toolUseID, message: "\(agentName) \(status) \(toolName)")
        case .toolProgress(_, let message):
            emitProgress(onProgress, toolUseID: toolUseID, message: "\(agentName): \(message)")
        case .turnComplete(let turnNumber, let toolCallCount):
            emitProgress(
                onProgress,
                toolUseID: toolUseID,
                message: "\(agentName) turn \(turnNumber) complete (\(toolCallCount) tool call\(toolCallCount == 1 ? "" : "s"))"
            )
        }
    }

    private func emitProgress(
        _ onProgress: ToolCallProgress?,
        toolUseID: String,
        message: String
    ) {
        onProgress?(ToolProgress(toolUseID: toolUseID, data: AgentToolProgressData(message: message)))
    }

    private func backgroundLaunchJSON(_ handle: SubAgentTaskHandle) -> String {
        let payload: [String: Any] = [
            "status": "async_launched",
            "taskId": handle.taskId,
            "agentId": handle.agentId,
            "agentType": handle.agentName,
            "description": handle.description,
            "next": "Use TaskOutput with this taskId to read progress and the final result.",
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "Started background sub-agent task \(handle.taskId). Use TaskOutput with this taskId to read progress and the final result."
        }
        return string
    }
}

public struct AgentToolProgressData: ToolProgressData {
    public let type = "agent"
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
