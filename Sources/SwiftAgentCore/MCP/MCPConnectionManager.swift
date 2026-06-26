import Foundation

/// MCP tool routing information (moved from old Tool protocol).
public struct MCPToolInfo: Sendable {
    public let serverName: String
    public let toolName: String

    public init(serverName: String, toolName: String) {
        self.serverName = serverName
        self.toolName = toolName
    }
}

/// MCP connection lifecycle manager matching Claude Code's useManageMCPConnections.ts.
///
/// Manages the full lifecycle of MCP server connections:
/// - Connection state machine (pending → connected/failed/needs-auth/disabled)
/// - Auto-reconnect with exponential backoff for remote transports
/// - ListChanged notifications for tools, prompts, and resources
/// - Batched state updates with configurable flush delay

// MARK: - Connection State Machine

/// Manages the MCP server connection lifecycle.
/// CC: useManageMCPConnections React hook — state machine + effects.
public actor MCPConnectionManager {

    // MARK: - Configuration

    /// CC: MAX_RECONNECT_ATTEMPTS = 5
    public static let maxReconnectAttempts = 5

    /// CC: INITIAL_BACKOFF_MS = 1000
    public static let initialBackoffMs: UInt64 = 1_000

    /// CC: MAX_BACKOFF_MS = 30_000
    public static let maxBackoffMs: UInt64 = 30_000

    /// CC: MAX_ERRORS_BEFORE_RECONNECT = 3
    public static let maxErrorsBeforeReconnect = 3

    /// CC: MCP_BATCH_FLUSH_MS = 16
    public static let batchFlushMs: UInt64 = 16

    /// CC: MCP_FETCH_CACHE_SIZE = 20 (LRU)
    public static let fetchCacheSize = 20

    /// CC: Local server batch size = 3, remote = 20
    public static let localServerBatchSize = 3
    public static let remoteServerBatchSize = 20

    // MARK: - State

    /// Current connection states for all known servers.
    public private(set) var serverStates: [String: MCPServerConnection] = [:]

    /// Tools, commands, and resources from connected servers.
    public private(set) var mcpTools: [any Tool] = []
    public private(set) var mcpCommands: [FullCommand] = []
    public private(set) var mcpResources: [String: [SerializedMCPResource]] = [:]

    /// Maps MCP tool name → server info (replaces old Tool.mcpInfo protocol member).
    private var mcpToolInfoMap: [String: MCPToolInfo] = [:]

    /// MCP tool name → qualified permission-check name mapping.
    private var mcpPermissionNames: [String: String] = [:]
    private var pendingUpdates: [String: MCPServerConnection] = [:]
    private var flushTask: Task<Void, Never>?

    /// Active reconnect timers by server name.
    private var reconnectTimers: [String: Task<Void, Never>] = [:]

    /// LRU cache keys for memoized fetch operations.
    private var fetchCacheKeys: Set<String> = []

    /// Called when server state changes (for UI notification).
    public var onStateChanged: (@Sendable () -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - State Transitions

    /// Initialize all discovered servers as pending.
    /// CC: initializeServersAsPending effect — runs on mount and plugin reload.
    public func initializeServersAsPending(serverConfigs: [String: ScopedMCPDiscriminatedServerConfig]) async {
        for (name, _) in serverConfigs {
            if serverStates[name] == nil {
                serverStates[name] = .pending(PendingMCPServerInfo(
                    name: name,
                    config: serverConfigs[name]!,
                    reconnectAttempt: nil,
                    maxReconnectAttempts: Self.maxReconnectAttempts
                ))
            }
        }

        // Remove stale servers not in current config
        for name in serverStates.keys where serverConfigs[name] == nil {
            serverStates.removeValue(forKey: name)
        }

        notifyStateChanged()
    }

    /// Update a server's connection state (batched).
    /// CC: updateServer() — coalesces updates into a single flush.
    public func updateServer(name: String, state: MCPServerConnection) {
        pendingUpdates[name] = state
        scheduleFlush()
    }

    /// Transition a server from connected/failed back to pending for reconnect.
    /// CC: reconnectWithBackoff — exponential backoff with max attempts.
    public func scheduleReconnect(
        serverName: String,
        config: ScopedMCPDiscriminatedServerConfig,
        connect: @escaping @Sendable (String, ScopedMCPDiscriminatedServerConfig) async -> MCPServerConnection
    ) {
        // Cancel any existing reconnect timer
        reconnectTimers[serverName]?.cancel()
        reconnectTimers.removeValue(forKey: serverName)

        let task = Task {
            await performReconnect(serverName: serverName, config: config, connect: connect)
        }
        reconnectTimers[serverName] = task
    }

    /// Cancel reconnection for a server.
    public func cancelReconnect(serverName: String) {
        reconnectTimers[serverName]?.cancel()
        reconnectTimers.removeValue(forKey: serverName)
    }

    /// Cancel all reconnections.
    public func cancelAllReconnects() {
        for (name, timer) in reconnectTimers {
            timer.cancel()
            reconnectTimers.removeValue(forKey: name)
        }
    }

    // MARK: - Reconnect Implementation

    /// CC: reconnectWithBackoff — exponential backoff algorithm.
    /// backoffMs = min(INITIAL_BACKOFF_MS * 2^(attempt-1), MAX_BACKOFF_MS)
    private func performReconnect(
        serverName: String,
        config: ScopedMCPDiscriminatedServerConfig,
        connect: @escaping @Sendable (String, ScopedMCPDiscriminatedServerConfig) async -> MCPServerConnection
    ) async {
        for attempt in 1...Self.maxReconnectAttempts {
            // Check if cancelled
            if Task.isCancelled { return }

            // Set state to pending
            updateServer(name: serverName, state: .pending(PendingMCPServerInfo(
                name: serverName,
                config: config,
                reconnectAttempt: attempt,
                maxReconnectAttempts: Self.maxReconnectAttempts
            )))

            // Attempt connection
            let result = await connect(serverName, config)

            switch result {
            case .connected:
                // Success — update tools/commands/resources and return
                updateServer(name: serverName, state: result)
                return
            case .needsAuth:
                updateServer(name: serverName, state: result)
                return
            default:
                break
            }

            // Check if final attempt
            if attempt == Self.maxReconnectAttempts {
                updateServer(name: serverName, state: result)
                return
            }

            // CC: await new Promise(resolve => setTimeout(resolve, backoffMs))
            let backoffMs = min(
                Self.initialBackoffMs * UInt64(1 << (attempt - 1)),
                Self.maxBackoffMs
            )
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
    }

    // MARK: - Server Disable/Enable

    /// Disable a server (user toggle).
    /// CC: toggleMcpServer → setMcpServerEnabled(false) → clearServerCache
    public func disableServer(name: String, config: ScopedMCPDiscriminatedServerConfig) {
        cancelReconnect(serverName: name)
        clearServerCache(name: name)
        updateServer(name: name, state: .disabled(DisabledMCPServerInfo(
            name: name, config: config
        )))
    }

    /// Re-enable a server (user toggle).
    /// CC: toggleMcpServer → setMcpServerEnabled(true) → reconnectMcpServerImpl
    public func enableServer(name: String, config: ScopedMCPDiscriminatedServerConfig) {
        updateServer(name: name, state: .pending(PendingMCPServerInfo(
            name: name, config: config
        )))
    }

    /// Check if a server is currently disabled.
    public func isServerDisabled(name: String) -> Bool {
        if case .disabled = serverStates[name] { return true }
        return false
    }

    // MARK: - Transport Type Detection

    /// CC: Auto-reconnect only applies to remote transports (SSE, HTTP, WS, claudeai-proxy).
    /// Stdio and SDK servers that disconnect stay failed.
    public static func isRemoteTransport(_ config: MCPDiscriminatedServerConfig) -> Bool {
        switch config {
        case .sse, .http, .ws, .claudeAIProxy:
            return true
        case .stdio, .sseIDE, .wsIDE, .sdk:
            return false
        }
    }

    /// Whether a server is local (stdio or SDK) — limited concurrency when connecting.
    public static func isLocalTransport(_ config: MCPDiscriminatedServerConfig) -> Bool {
        switch config {
        case .stdio, .sdk:
            return true
        default:
            return false
        }
    }

    // MARK: - Cache Management

    /// Clear cached tools/commands/resources for a server.
    /// CC: clearServerCache — called on disable, reconnect, and cleanup.
    public func clearServerCache(name: String) {
        let prefix = "mcp__\(normalizeNameForMCP(name))__"
        fetchCacheKeys = fetchCacheKeys.filter { !$0.hasPrefix(prefix) }
    }

    /// Invalidate all fetch caches.
    public func clearAllCaches() {
        fetchCacheKeys.removeAll()
    }

    // MARK: - ListChanged Notifications

    /// CC: Register notification handler for ToolListChanged.
    /// When a server signals that its tool list changed, re-fetch tools.
    public func handleToolListChanged(
        serverName: String,
        fetchTools: @escaping @Sendable (String) async -> [any Tool]
    ) {
        let prefix = "tools_\(serverName)"
        fetchCacheKeys.remove(prefix)
        Task {
            let tools = await fetchTools(serverName)
            // Remove old tools from this server using internal tracking map
            mcpTools = mcpTools.filter { tool in
                if let info = mcpToolInfoMap[tool.name] {
                    return info.serverName != serverName
                }
                return true
            }
            // Register MCP info for the new tools
            for tool in tools {
                let info = MCPToolInfo(serverName: serverName, toolName: tool.name)
                mcpToolInfoMap[tool.name] = info
                let prefix = getMcpPrefix(serverName)
                mcpPermissionNames[tool.name] = "\(prefix)\(tool.name)"
            }
            mcpTools.append(contentsOf: tools)
            notifyStateChanged()
            // CC logs: tengu_mcp_list_changed analytics
        }
    }

    /// CC: Register notification handler for PromptListChanged.
    public func handlePromptListChanged(
        serverName: String,
        fetchPrompts: @escaping @Sendable (String) async -> [FullCommand]
    ) {
        let prefix = "prompts_\(serverName)"
        fetchCacheKeys.remove(prefix)
        Task {
            let prompts = await fetchPrompts(serverName)
            mcpCommands = mcpCommands.filter { !$0.base.name.hasPrefix("mcp__\(normalizeNameForMCP(serverName))__") }
            mcpCommands.append(contentsOf: prompts)
            notifyStateChanged()
        }
    }

    /// CC: Register notification handler for ResourceListChanged.
    public func handleResourceListChanged(
        serverName: String,
        fetchResources: @escaping @Sendable (String) async -> [SerializedMCPResource]
    ) {
        let prefix = "resources_\(serverName)"
        fetchCacheKeys.remove(prefix)
        Task {
            let resources = await fetchResources(serverName)
            mcpResources[serverName] = resources
            notifyStateChanged()
        }
    }

    // MARK: - Terminal Error Detection

    /// CC: Detects terminal connection errors that should NOT trigger auto-reconnect.
    /// After MAX_ERRORS_BEFORE_RECONNECT consecutive terminal errors, the connection is failed.
    public static func isTerminalConnectionError(_ error: Error?) -> Bool {
        guard let error = error else { return false }
        let message = error.localizedDescription.lowercased()
        let terminalPatterns = [
            "econnreset", "etimedout", "epipe", "ehostunreach",
            "econnrefused", "body timeout error", "terminated",
            "sse stream disconnected", "failed to reconnect sse stream",
        ]
        return terminalPatterns.contains { message.contains($0) }
    }

    // MARK: - Internal Helpers

    /// CC: normalizeNameForMCP — replaces non-alphanumeric chars with underscores.
    private func normalizeNameForMCP(_ name: String) -> String {
        var normalized = ""
        for char in name {
            if char.isLetter || char.isNumber || char == "_" || char == "-" {
                normalized.append(char)
            } else {
                normalized.append("_")
            }
        }
        // Collapse consecutive underscores for claude.ai servers
        if name.hasPrefix("claude.ai ") {
            while normalized.contains("__") {
                normalized = normalized.replacingOccurrences(of: "__", with: "_")
            }
            normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        return normalized
    }

    /// Flush pending state updates (batched, 16ms delay).
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: Self.batchFlushMs * 1_000_000)
            if Task.isCancelled { return }
            applyPendingUpdates()
        }
    }

    private func applyPendingUpdates() {
        for (name, state) in pendingUpdates {
            serverStates[name] = state
        }
        pendingUpdates.removeAll()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }

    // MARK: - Cleanup

    /// Cancel all timers and flush pending updates (called on shutdown).
    public func cleanup() {
        cancelAllReconnects()
        flushTask?.cancel()
    }
}

// MARK: - Dynamic MCP Tool Naming

/// CC: buildMcpToolName(serverName, toolName) → "mcp__{normalized_server}__{normalized_tool}"
public func buildMcpToolName(serverName: String, toolName: String) -> String {
    "\(getMcpPrefix(serverName))\(normalizeNameForMCP(toolName))"
}

/// CC: getMcpPrefix(serverName) → "mcp__{normalized_server}__"
public func getMcpPrefix(_ serverName: String) -> String {
    "mcp__\(normalizeNameForMCP(serverName))__"
}

/// Normalizes a name for use in MCP tool/command identifiers.
/// CC: normalizeNameForMCP in normalization.ts
public func normalizeNameForMCP(_ name: String) -> String {
    var normalized = ""
    for char in name {
        if char.isLetter || char.isNumber || char == "_" || char == "-" {
            normalized.append(char)
        } else {
            normalized.append("_")
        }
    }
    if name.hasPrefix("claude.ai ") {
        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
    return normalized
}

/// CC: getToolNameForPermissionCheck — uses the fully qualified name for MCP tools.
/// MCP tool identification is now tracked internally via mcpPermissionNames map.
public func getToolNameForPermissionCheck(tool: any Tool, mcpPermissionNames: [String: String] = [:]) -> String {
    if let qualified = mcpPermissionNames[tool.name] {
        return qualified
    }
    return tool.name
}
