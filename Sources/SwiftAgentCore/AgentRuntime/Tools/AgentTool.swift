import Foundation

/// Dispatches work to specialized sub-agents.
/// Matches Claude Code's AgentTool.
///
/// Captures at init: modelProvider, memoryStore, permissionEngine,
/// toolEngine, workingDirectory, mainLoopModel. In call(), creates a
/// child LanguageModelSession to handle the delegated task.
public struct AgentTool: Tool {
    public let name = "Agent"
    public let description = """
        Launch a new agent to handle complex, multi-step tasks autonomously. \
        Each agent type has specific capabilities and tools available to it. \
        Available agent types: general-purpose (catch-all), Explore (codebase \
        search), Plan (architecture planning), verification (check completed work).
        """

    // MARK: - Captured Providers

    private let modelProvider: any LanguageModel
    private let memoryStore: any SessionMemoryStore
    private let permissionEngine: any SessionPermissionEngine
    private let toolEngine: any ToolEngine
    private let workingDirectory: String
    private let mainLoopModel: String

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var description: String
        public var prompt: String
        public var subagentType: String?
        public var model: String?
        public var runInBackground: Bool?
        public var name: String?
        public var teamName: String?
        public var mode: String?
        public var isolation: String?
        public var cwd: String?

        enum CodingKeys: String, CodingKey {
            case description
            case prompt
            case subagentType = "subagent_type"
            case model
            case runInBackground = "run_in_background"
            case name
            case teamName = "team_name"
            case mode
            case isolation
            case cwd
        }
    }

    // MARK: - Input Schema

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "A short (3-5 word) description of the task")
        schema.properties?["prompt"] = JSONSchemaProperty(type: "string", description: "The task for the agent to perform")
        schema.properties?["subagent_type"] = JSONSchemaProperty(type: "string", description: "The type of specialized agent to use for this task. Available types: general-purpose, Explore, Plan, verification. Defaults to general-purpose if omitted.")
        schema.properties?["model"] = JSONSchemaProperty(type: "string", description: "Optional model override for this agent.", enum: ["sonnet", "opus", "haiku"])
        schema.properties?["run_in_background"] = JSONSchemaProperty(type: "boolean", description: "Set to true to run this agent in the background. You will be notified when it completes.")
        schema.properties?["name"] = JSONSchemaProperty(type: "string", description: "Optional display name for the agent (multi-agent mode).")
        schema.properties?["team_name"] = JSONSchemaProperty(type: "string", description: "Optional team name for routing (multi-team mode).")
        schema.properties?["mode"] = JSONSchemaProperty(type: "string", description: "Optional permission mode override for this agent.", enum: ["default", "acceptEdits", "plan"])
        schema.properties?["isolation"] = JSONSchemaProperty(type: "string", description: "Isolation mode for the agent: \"worktree\" creates a temporary git worktree.", enum: ["worktree"])
        schema.properties?["cwd"] = JSONSchemaProperty(type: "string", description: "Optional working directory override for the agent.")
        schema.required = ["description", "prompt"]
        return schema
    }

    // MARK: - Init

    public init(
        modelProvider: any LanguageModel,
        memoryStore: any SessionMemoryStore,
        permissionEngine: any SessionPermissionEngine,
        toolEngine: any ToolEngine,
        workingDirectory: String,
        mainLoopModel: String
    ) {
        self.modelProvider = modelProvider
        self.memoryStore = memoryStore
        self.permissionEngine = permissionEngine
        self.toolEngine = toolEngine
        self.workingDirectory = workingDirectory
        self.mainLoopModel = mainLoopModel
    }

    // MARK: - Call

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let taskDesc = arguments.description
        let prompt = arguments.prompt
        let subagentType = arguments.subagentType ?? "general-purpose"
        let runInBackground = arguments.runInBackground ?? false

        // Validate agent type
        let validTypes: Set<String> = ["general-purpose", "Explore", "Plan", "verification"]
        guard validTypes.contains(subagentType) else {
            let available = validTypes.sorted().joined(separator: ", ")
            return .string("Unknown agent type \"\(subagentType)\". Available types: \(available)")
        }

        let cwd = arguments.cwd ?? workingDirectory

        if runInBackground {
            // Background execution: return immediately with a handle
            let taskId = UUID().uuidString
            let agentId = "\(subagentType)-\(UUID().uuidString.prefix(8))"

            // Fire-and-forget the sub-agent task
            Task.detached { [modelProvider, memoryStore, permissionEngine, toolEngine, cwd, mainLoopModel] in
                _ = try? await Self.runChildAgent(
                    modelProvider: modelProvider,
                    memoryStore: memoryStore,
                    permissionEngine: permissionEngine,
                    toolEngine: toolEngine,
                    workingDirectory: cwd,
                    mainLoopModel: mainLoopModel,
                    agentType: subagentType,
                    prompt: prompt
                )
            }

            let payload: [String: Any] = [
                "status": "async_launched",
                "taskId": taskId,
                "agentId": agentId,
                "agentType": subagentType,
                "description": taskDesc,
                "next": "Use TaskOutput with this taskId to read progress and the final result.",
            ]
            if JSONSerialization.isValidJSONObject(payload),
               let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return .string(string)
            }
            return .string("Started background sub-agent task \(taskId). Use TaskOutput with this taskId to read progress and the final result.")
        }

        // Foreground execution
        do {
            let result = try await Self.runChildAgent(
                modelProvider: modelProvider,
                memoryStore: memoryStore,
                permissionEngine: permissionEngine,
                toolEngine: toolEngine,
                workingDirectory: cwd,
                mainLoopModel: mainLoopModel,
                agentType: subagentType,
                prompt: prompt
            )
            return .string("""
                Agent \"\(subagentType)\" completed.

                Result:
                \(result)
                """)
        } catch {
            return .string("Agent error: \(error.localizedDescription)")
        }
    }

    // MARK: - Child Agent Runner

    /// Creates a child LanguageModelSessionImpl with the captured providers,
    /// registers tools, and runs the prompt. This removes the old
    /// SubAgentManager dependency.
    private static func runChildAgent(
        modelProvider: any LanguageModel,
        memoryStore: any SessionMemoryStore,
        permissionEngine: any SessionPermissionEngine,
        toolEngine: any ToolEngine,
        workingDirectory: String,
        mainLoopModel: String,
        agentType: String,
        prompt: String
    ) async throws -> String {
        // Create a child LanguageModelSessionImpl with the captured providers.
        let childSession = LanguageModelSessionImpl(
            modelProvider: modelProvider,
            memoryStore: memoryStore,
            permissionEngine: permissionEngine,
            toolEngine: toolEngine,
            contextManager: NoOpSessionContextManager(),
            profileManager: NoOpProfileManager(),
            hookSystem: NoOpSessionHookSystem()
        )

        // Run the prompt through the child session
        let response = try await childSession.respond(to: prompt)

        // Extract response text from transcript entries
        let responseText = response.transcript.entries
            .compactMap { entry -> String? in
                switch entry {
                case .response(let text): return text
                default: return nil
                }
            }
            .joined(separator: "\n")
        return responseText.isEmpty ? "(Agent completed with no output)" : responseText
    }
}
