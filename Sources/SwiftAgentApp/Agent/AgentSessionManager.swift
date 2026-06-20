import Foundation
import SwiftAgentCore

// MARK: - Bootstrap Result

/// The outcome of `bootstrap()`, enumerating all failures by subsystem.
public struct BootstrapResult: Sendable {
    /// Whether all critical subsystems bootstrapped successfully.
    public let isBootstrapped: Bool
    /// Non-critical warnings (e.g., one MCP server failed, skills are still loaded).
    public let warnings: [BootstrapDiagnostic]
    /// Critical failures that prevented bootstrap.
    public let errors: [BootstrapDiagnostic]
    /// Statistics gathered during bootstrap.
    public let stats: BootstrapStats

    public struct BootstrapDiagnostic: Identifiable, Sendable {
        public let id = UUID()
        public let subsystem: String
        public let message: String
        public let severity: Severity

        public enum Severity: Sendable {
            case warning
            case error
        }
    }

    public struct BootstrapStats: Sendable {
        public let toolCount: Int
        public let mcpServerCount: Int
        public let skillCount: Int
    }
}

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
///
/// ## Cancellation
/// Uses Swift structured concurrency: `run()` is wrapped in a `Task`
/// that can be cancelled via the returned `AgentRunHandle`. Tool
/// execution checks `Task.isCancelled` cooperatively.
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

    /// The structured bootstrap result. `nil` until `bootstrap()` has been called.
    @Published public private(set) var bootstrapResult: BootstrapResult?

    /// Whether `bootstrap()` has completed successfully.
    @Published public private(set) var isBootstrapped = false

    /// MCP server names discovered during bootstrap.
    @Published public private(set) var mcpServerNames: [String] = []

    /// Skill names discovered during bootstrap.
    @Published public private(set) var skillNames: [String] = []

    /// Total number of registered tools (builtin + MCP).
    @Published public private(set) var totalToolCount: Int = 0

    // MARK: - Run state

    /// The currently running agent task (if any).
    private var currentRunTask: Task<RunResult, Error>?

    /// Whether an agent turn is currently executing.
    @Published public private(set) var isRunning: Bool = false

    // MARK: - Permission

    /// Pending permission request — when non-nil, SwiftUI should present an alert.
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
    ///
    /// - Parameter workingDirectory: The project working directory.
    ///   Defaults to the current process directory.
    /// - Returns: A `BootstrapResult` with per-subsystem diagnostics and stats.
    @discardableResult
    public func bootstrap(workingDirectory: String? = nil) async -> BootstrapResult {
        let debugger = AgentDebugger.shared
        let cwd = workingDirectory ?? NSHomeDirectory()
        debugger.logLifecycle("Bootstrap starting...", metadata: ["cwd": cwd])

        var warnings: [BootstrapResult.BootstrapDiagnostic] = []
        var errors: [BootstrapResult.BootstrapDiagnostic] = []

        // ── 0. Client check (critical) ──
        guard provider.getClient() != nil else {
            let diag = BootstrapResult.BootstrapDiagnostic(
                subsystem: "LLM Client",
                message: "No API key configured. Set one in Settings → General.",
                severity: .error
            )
            errors.append(diag)
            let result = BootstrapResult(
                isBootstrapped: false,
                warnings: warnings,
                errors: errors,
                stats: .init(toolCount: 0, mcpServerCount: 0, skillCount: 0)
            )
            self.bootstrapResult = result
            debugger.logLifecycle("Bootstrap failed: no API key", metadata: [:])
            return result
        }

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
        debugger.logMCP("MCP bootstrap complete", metadata: [
            "toolDefs": "\(mcpToolDefs.count)",
            "servers": "\(clientMap.count)"
        ])

        // Collect MCP failures as warnings
        let failures = await bootstrapper.failures
        for (server, error) in failures {
            let diag = BootstrapResult.BootstrapDiagnostic(
                subsystem: "MCP/\(server)",
                message: error,
                severity: .warning
            )
            warnings.append(diag)
            debugger.logMCP("MCP server '\(server)' failed: \(error)", metadata: [:])
        }

        // ── 3. Load skills ──
        let manifests = SkillFileLoader.loadAllManifests(workingDirectory: cwd)
        self.skillNames = manifests.map(\.name)
        let allSkillNames = SkillFileLoader.allSkillNames(workingDirectory: cwd)
        toolRegistry.register(SkillTool(knownSkills: allSkillNames))
        toolRegistry.register(ListSkillsTool())
        debugger.logSkill("Skills loaded", metadata: ["count": "\(skillNames.count)"])

        // ── 4. Set up hook system ──
        self.hookSystem = HookSystem()
        // TODO: Load hooks from user/project settings files

        // ── 5. Build system prompt builder ──
        let promptBuilder = SystemPromptBuilder(
            workingDirectory: cwd,
            claudeMdLoader: ClaudeMdLoader()
        )

        // ── 6. Build QueryEngine ──
        let toolExecutor = ToolExecutor(registry: toolRegistry)
        self.queryEngine = QueryEngine(
            client: provider.getClient()!,
            toolExecutor: toolExecutor,
            contextManager: ContextManager(),
            promptBuilder: promptBuilder,
            hookSystem: hookSystem
        )

        let toolCount = await toolRegistry.toolDefinitions().count
        self.totalToolCount = toolCount
        self.isBootstrapped = true

        let stats = BootstrapResult.BootstrapStats(
            toolCount: toolCount,
            mcpServerCount: mcpServerNames.count,
            skillCount: skillNames.count
        )

        let result = BootstrapResult(
            isBootstrapped: true,
            warnings: warnings,
            errors: errors,
            stats: stats
        )
        self.bootstrapResult = result

        debugger.logLifecycle("Bootstrap complete", metadata: [
            "tools": "\(stats.toolCount)",
            "mcp": "\(stats.mcpServerCount)",
            "skills": "\(stats.skillCount)",
            "warnings": "\(warnings.count)"
        ])
        debugger.runDiagnostics(agentSession: self, appViewModel: nil)

        return result
    }

    // MARK: - Run

    /// Run the agent loop for a single user turn.
    ///
    /// - Parameters:
    ///   - userInput: The user's message text.
    ///   - conversation: Current conversation state.
    ///   - workingDirectory: The project working directory.
    ///   - onEvent: Streaming event callback for real-time UI updates.
    /// - Returns: The final `RunResult` (text, turns, tool call count, token usage).
    /// - Throws: `AgentSessionError.notBootstrapped` if `bootstrap()` hasn't been called,
    ///   or `CancellationError` if the run is cancelled via `cancelRun()`.
    public func run(
        userInput: String,
        conversation: Conversation,
        workingDirectory: String? = nil,
        onEvent: @escaping @Sendable (StreamingQueryEvent) -> Void
    ) async throws -> RunResult {
        guard let engine = queryEngine else {
            throw AgentSessionError.notBootstrapped
        }

        // Cancel any previous run
        cancelRun()

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

        // Build permission handler
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

        // Wrap in a Task so cancellation can target it
        let runTask = Task { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }
            self.isRunning = true
            defer { self.isRunning = false }

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

        self.currentRunTask = runTask

        do {
            let result = try await runTask.value
            self.currentRunTask = nil
            self.isRunning = false
            return result
        } catch {
            self.currentRunTask = nil
            self.isRunning = false
            if error is CancellationError {
                debugger.logLifecycle("Agent run cancelled", metadata: [:])
            } else {
                debugger.logLifecycle("Agent run failed", metadata: ["error": error.localizedDescription])
            }
            throw error
        }
    }

    /// Cancel the currently running agent turn.
    public func cancelRun() {
        guard let task = currentRunTask, !task.isCancelled else { return }

        // Cancel the Swift Task — this causes `try await runTask.value` to throw CancellationError
        task.cancel()

        // Cancel the active LLM stream so the URLSession connection is released.
        // Prevents subsequent runs from failing with LLMError.httpError(status: 0)
        // because the old SSE connection was still alive.
        queryEngine?.cancelActiveStream()

        // Also signal the app state to stop processing
        Task { await appState.stopProcessing() }

        // Dismiss any pending permission prompt
        if let prompt = pendingPermission {
            prompt.continuation(false)
            pendingPermission = nil
        }

        currentRunTask = nil
        isRunning = false

        AgentDebugger.shared.logLifecycle("Run cancelled by user", metadata: [:])
    }

    /// Cancel the current agent run (legacy name, calls `cancelRun()`).
    @available(*, deprecated, renamed: "cancelRun()")
    public func cancel() {
        cancelRun()
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
        guard let client = provider.getClient() else { return }

        let subAgentEngine = QueryEngine(
            client: client,
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
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .notBootstrapped:
            return "Agent session not bootstrapped — call bootstrap() first"
        case .clientNotConfigured:
            return "LLM client not configured — no API key available"
        case .alreadyRunning:
            return "An agent run is already in progress — cancel it first or wait for completion"
        }
    }
}
