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

        // Build tool list display
        let toolList: String
        if definition.tools == ["*"] || definition.tools == nil {
            if let disallowed = definition.disallowedTools, !disallowed.isEmpty {
                toolList = "All tools except: \(disallowed.joined(separator: ", "))"
            } else {
                toolList = "All tools"
            }
        } else if let tools = definition.tools {
            toolList = tools.joined(separator: ", ")
        } else {
            toolList = "All tools"
        }
        let modelNote: String
        if let m = input["model"], case .string(let modelName) = m {
            modelNote = " (model override: \(modelName))"
        } else { modelNote = "" }

        if runInBackground {
            return ToolResult(content: """
                Launched agent \"\(definition.name)\" in background\(modelNote).
                Agent ID: \(definition.id)
                Description: \(taskDesc)
                Prompt: \(prompt)
                Tools: \(toolList)

                The agent will work autonomously on this task.
                """)
        }

        // If we have a sub-agent manager, run the agent
        if let manager = subAgentManager {
            let agentContext = AgentContext(
                parentSessionId: context.sessionID,
                workingDirectory: context.workingDirectory,
                permissionMode: context.mode
            )

            // Build AppState from context
            let state = AppState(settings: Settings())

            do {
                let result = try await manager.run(
                    definition: definition,
                    input: prompt,
                    context: agentContext,
                    state: state,
                    tools: nil
                )
                return ToolResult(content: """
                    Agent \"\(definition.name)\" completed (ID: \(result.agentId))
                    Tool calls: \(result.toolCalls)
                    Duration: \(String(format: "%.1f", result.duration))s

                    Result:
                    \(result.output)
                    """)
            } catch {
                return ToolResult(content: "Agent error: \(error.localizedDescription)", isError: true)
            }
        } else {
            // No sub-agent manager — format the agent dispatch as structured output
            return ToolResult(content: """
                ## Agent Dispatch: \(definition.name)\(modelNote)

                **Task**: \(taskDesc)
                **Prompt**: \(prompt)
                **Type**: \(subagentType)
                **Tools**: \(toolList)

                ### System Prompt
                \(definition.systemPrompt)

                The agent should now execute the task using the tools available. When complete, respond with a concise report covering what was done and any key findings.
                """)
        }
    }
}
