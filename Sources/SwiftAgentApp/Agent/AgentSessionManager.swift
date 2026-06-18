import Foundation
import SwiftAgentCore

// MARK: - AgentSessionManager

/// Central bridge between the SwiftUI App and `SwiftAgentCore`'s agent runtime.
///
/// Bootstraps all subsystems (tools, MCP, skills, hooks, permissions) and exposes
/// a `run()` method that delegates to `QueryEngine.run()` for the full agent loop
/// (stream → parse tools → execute → repeat).
///
/// ## Bootstrap order (mirrors CLI's `ChatCommand.run()`)
/// 1. Register 30+ builtin tools into `ToolRegistry`
/// 2. Bootstrap MCP servers → `DynamicMCPTool` per discovered tool
/// 3. Load skill manifests from disk → `SkillTool` + `ListSkillsTool`
/// 4. Initialize `HookSystem` from user/project settings
/// 5. Build `SystemPromptBuilder` with CLAUDE.md + MEMORY.md support
/// 6. Wire up `QueryEngine` with tools, hooks, and permission handler
///
/// ## Permission flow
/// When a tool requests `.ask` permission, the manager publishes a
/// `pendingPermission` request. The SwiftUI layer presents an alert;
/// the user's choice (allow/deny) resumes the tool execution.
@MainActor
public final class AgentSessionManager: ObservableObject {

    // MARK: - Core subsystems

    private let provider: AppAgentProvider
    private let toolRegistry = ToolRegistry()
    private let taskManager = TaskManager()
    private var queryEngine: QueryEngine?
    private var hookSystem: HookSystem?
    private var mcpBootstrapper: MCPBootstrapper?
    private lazy var appState = AppState()

    // MARK: - MCP client storage (for ToolUseContext)

    private var mcpClients: [any Sendable] = []

    // MARK: - Bootstrap state

    /// Whether `bootstrap()` has completed successfully.
    @Published public private(set) var isBootstrapped = false

    /// MCP server names discovered during bootstrap.
    @Published public private(set) var mcpServerNames: [String] = []

    /// Skill names discovered during bootstrap.
    @Published public private(set) var skillNames: [String] = []

    /// Total number of registered tools (builtin + MCP).
    @Published public private(set) var totalToolCount: Int = 0

    /// Error message if bootstrap failed.
    @Published public private(set) var bootstrapError: String?

    // MARK: - Permission

    /// Pending permission request — when non-nil, SwiftUI should present an alert.
    /// The `continuation` must be called with `true` (allow) or `false` (deny).
    @Published public var pendingPermission: PermissionPrompt?

    /// A permission prompt for SwiftUI display.
    public struct PermissionPrompt: Identifiable {
        public let id = UUID()
        public let toolName: String
        public let toolUseID: String
        public let message: String
        public let continuation: (Bool) -> Void
    }

    /// Current permission mode (affects how tools are executed).
    @Published public var permissionMode: SwiftAgentCore.PermissionMode = .default

    /// Whether plan mode is active.
    @Published public var isPlanModeActive: Bool = false

    // MARK: - Init

    public init(provider: AppAgentProvider) {
        self.provider = provider
    }

    // MARK: - Bootstrap

    /// Bootstrap all agent subsystems.
    /// - Parameter workingDirectory: The project working directory.
    ///   Defaults to the current process directory; callers should pass
    ///   the active project path when available.
    @discardableResult
    public func bootstrap(workingDirectory: String? = nil) async -> Bool {
        let debugger = AgentDebugger.shared
        debugger.logLifecycle("Bootstrap starting...", metadata: ["cwd": workingDirectory ?? FileManager.default.currentDirectoryPath])
        guard let client = provider.getClient() else {
            bootstrapError = "LLM client not configured — no API key"
            return false
        }

        let cwd = workingDirectory ?? NSHomeDirectory()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // ── 1. Register builtin tools ──
        registerBuiltinTools()
        debugger.logTool("Builtin tools registered", metadata: ["count": "30+"])

        // ── 2. Bootstrap MCP servers ──
        let bootstrapper = MCPBootstrapper()
        self.mcpBootstrapper = bootstrapper
        let mcpToolDefs = await bootstrapper.bootstrap(cwd: cwd, home: homeDir)

        for def in mcpToolDefs {
            let parts = def.name.split(separator: "__", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 3, parts[0] == "mcp" {
                let serverName = String(parts[1])
                let toolName = String(parts[2])
                let dynamicTool = DynamicMCPTool(
                    serverName: serverName,
                    toolName: toolName,
                    toolDescription: def.description,
                    inputSchema: def.inputSchema,
                    bootstrapper: bootstrapper
                )
                toolRegistry.register(dynamicTool)
            }
        }

        let clientMap = await bootstrapper.clients
        self.mcpClients = Array(clientMap.values)
        self.mcpServerNames = Array(clientMap.keys).sorted()
        debugger.logMCP("MCP bootstrap complete", metadata: ["toolDefs": "\(mcpToolDefs.count)", "servers": "\(clientMap.count)"])

        // Log MCP failures
        let failures = await bootstrapper.failures
        for (server, error) in failures {
            print("[AgentSessionManager] MCP \(server): \(error)")
        }

        // ── 3. Load skills ──
        let manifests = SkillFileLoader.loadAllManifests(workingDirectory: cwd)
        self.skillNames = manifests.map(\.name)
        let allSkillNames = SkillFileLoader.allSkillNames(workingDirectory: cwd)
        toolRegistry.register(SkillTool(knownSkills: allSkillNames))
        toolRegistry.register(ListSkillsTool())
        debugger.logSkill("Skills loaded", metadata: ["count": "\(skillNames.count)"])

        // ── 4. Set up hook system ──
        // TODO: Load hooks from user/project settings files
        self.hookSystem = HookSystem()

        // ── 5. Build system prompt builder ──
        let promptBuilder = SystemPromptBuilder(
            workingDirectory: cwd,
            claudeMdLoader: ClaudeMdLoader()
        )

        // ── 6. Build QueryEngine ──
        let toolExecutor = ToolExecutor(registry: toolRegistry)
        self.queryEngine = QueryEngine(
            client: client,
            toolExecutor: toolExecutor,
            contextManager: ContextManager(),
            promptBuilder: promptBuilder,
            hookSystem: hookSystem
        )

        self.totalToolCount = await toolRegistry.toolDefinitions().count
        self.isBootstrapped = true
        self.bootstrapError = nil

        debugger.logLifecycle("Bootstrap complete", metadata: [
            "tools": "\(totalToolCount)",
            "mcp": "\(mcpServerNames.count)",
            "skills": "\(skillNames.count)"
        ])
        debugger.runDiagnostics(agentSession: self, appViewModel: nil)

        print("[AgentSessionManager] Bootstrapped: \(totalToolCount) tools, \(mcpServerNames.count) MCP servers, \(skillNames.count) skills")
        return true
    }

    // MARK: - Run

    /// Run the agent loop for a single user turn.
    ///
    /// - Parameters:
    ///   - userInput: The user's message text.
    ///   - conversation: Current conversation state (messages, turns, system prompt).
    ///   - onEvent: Streaming event callback for real-time UI updates.
    /// - Returns: The final `RunResult` containing text, turns, tool call count, and token usage.
    /// - Throws: `AgentSessionError.notBootstrapped` if `bootstrap()` hasn't been called.
    public func run(
        userInput: String,
        conversation: Conversation,
        workingDirectory: String? = nil,
        onEvent: @escaping @Sendable (StreamingQueryEvent) -> Void
    ) async throws -> RunResult {
        guard let engine = queryEngine else {
            throw AgentSessionError.notBootstrapped
        }

        // Sync permission mode into app state
        await appState.updateSettings(Settings(
            model: ModelConfig(provider: .firstParty, modelID: provider.currentModel),
            permissionMode: permissionMode
        ))
        if isPlanModeActive {
            await appState.setPlanMode(true)
        }

        let toolDefs = await toolRegistry.toolDefinitions()
        let debugger = AgentDebugger.shared
        let wd = workingDirectory ?? NSHomeDirectory()
        debugger.logLLM("Agent run starting", metadata: [
            "model": provider.currentModel,
            "tools": "\(toolDefs.count)",
            "inputLen": "\(userInput.count)",
            "cwd": wd
        ])

        // Build permission handler — bridges Core's permission flow
        // to SwiftUI alerts via `pendingPermission`.
        let permissionHandler: PermissionPromptHandler = { [weak self] toolName, toolUseID, decision in
            guard let self else { return .deny(reason: "Session terminated") }
            let mode = await MainActor.run { self.permissionMode }
            guard mode != .bypassPermissions else { return .allow }
            guard mode != .dontAsk else { return .deny(reason: "Permission mode is dontAsk") }

            return await withCheckedContinuation { continuation in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: .deny(reason: "Session terminated"))
                        return
                    }
                    self.pendingPermission = PermissionPrompt(
                        toolName: toolName,
                        toolUseID: toolUseID,
                        message: decision.message,
                        continuation: { allowed in
                            continuation.resume(
                                returning: allowed
                                    ? .allow
                                    : .deny(reason: "User denied permission")
                            )
                        }
                    )
                }
            }
        }

        return try await engine.run(
            userInput: userInput,
            conversation: conversation,
            state: appState,
            tools: toolDefs,
            onEvent: onEvent,
            permissionPromptHandler: permissionHandler,
            workingDirectory: wd
        )
    }

    /// Cancel the current agent run.
    public func cancel() {
        Task { await appState.stopProcessing() }
    }

    /// Get a snapshot of the current app state (token usage, etc.).
    public func getStateSnapshot() async -> AppStateSnapshot {
        await appState.getSnapshot()
    }

    /// Resolve the pending permission with the given choice.
    /// Called by SwiftUI when the user taps Allow or Deny in the permission alert.
    public func resolvePermission(allowed: Bool) {
        guard let prompt = pendingPermission else { return }
        prompt.continuation(allowed)
        pendingPermission = nil
    }

    // MARK: - Private: Tool Registration

    /// Register all 30+ builtin tools into the ToolRegistry.
    /// Mirrors `ChatCommand.registerBuiltinTools()` exactly.
    private func registerBuiltinTools() {
        let subAgentEngine = QueryEngine(
            client: provider.getClient()!,
            toolExecutor: ToolExecutor(registry: toolRegistry),
            contextManager: ContextManager(),
            promptBuilder: SystemPromptBuilder()
        )
        let subAgentManager = SubAgentManager(engine: subAgentEngine, taskManager: taskManager)

        toolRegistry.register(FileReadTool())
        toolRegistry.register(FileWriteTool())
        toolRegistry.register(FileEditTool())
        toolRegistry.register(BashTool())
        toolRegistry.register(GlobTool())
        toolRegistry.register(GrepTool())
        toolRegistry.register(WebFetchTool())
        toolRegistry.register(WebSearchTool())
        toolRegistry.register(TodoWriteTool())
        toolRegistry.register(NotebookEditTool())
        toolRegistry.register(ConfigTool())
        toolRegistry.register(EnterWorktreeTool())
        toolRegistry.register(ExitWorktreeTool())
        toolRegistry.register(McpAuthTool())
        toolRegistry.register(ListMcpResourcesTool())
        toolRegistry.register(ReadMcpResourceTool())
        toolRegistry.register(BriefTool())
        toolRegistry.register(TaskCreateTool(taskManager: taskManager))
        toolRegistry.register(TaskGetTool(taskManager: taskManager))
        toolRegistry.register(TaskListTool(taskManager: taskManager))
        toolRegistry.register(TaskOutputTool(taskManager: taskManager))
        toolRegistry.register(TaskUpdateTool(taskManager: taskManager))
        toolRegistry.register(TaskStopTool(taskManager: taskManager))
        toolRegistry.register(AgentTool(subAgentManager: subAgentManager))
        // SkillTool + ListSkillsTool are registered after skill manifests load
        toolRegistry.register(SendMessageTool())
        toolRegistry.register(AskUserQuestionTool())
        toolRegistry.register(LSPTool())
        toolRegistry.register(EnterPlanModeTool())
        toolRegistry.register(ExitPlanModeV2Tool())
        toolRegistry.register(CronCreateTool())
        toolRegistry.register(CronDeleteTool())
        toolRegistry.register(CronListTool())
        toolRegistry.register(PowerShellTool())
        toolRegistry.register(ToolSearchTool(toolRegistry: toolRegistry))
        toolRegistry.register(SleepTool())
        toolRegistry.register(SyntheticOutputTool())
        toolRegistry.register(RemoteTriggerTool())
        toolRegistry.register(TeamCreateTool())
        toolRegistry.register(TeamDeleteTool())
    }
}

// MARK: - Errors

public enum AgentSessionError: Error, LocalizedError {
    case notBootstrapped
    case clientNotConfigured

    public var errorDescription: String? {
        switch self {
        case .notBootstrapped:
            return "Agent session not bootstrapped — call bootstrap() first"
        case .clientNotConfigured:
            return "LLM client not configured — no API key available"
        }
    }
}
