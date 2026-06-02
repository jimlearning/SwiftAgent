import Foundation

/// Bootstraps MCP servers from config files and keeps them connected.
///
/// Reads `.mcp.json` from project root and user config (`~/.claude/mcp.json`),
/// creates MCP clients for each stdio server, performs the initialize handshake,
/// lists tools, and surfaces them for registration into the agent's ToolRegistry.
///
/// CC analogue: MCP server discovery + connection logic in
/// `useManageMCPConnections.ts` and `mcp-json.ts`.
public actor MCPBootstrapper {

    public init() {}

    /// Connected MCP clients keyed by server name.
    public private(set) var clients: [String: MCPClient] = [:]

    /// Tool definitions discovered from all connected servers.
    public private(set) var toolDefinitions: [ToolDefinition] = []

    /// Resource collections keyed by server name.
    public private(set) var resources: [String: [SerializedMCPResource]] = [:]

    /// Server-level instructions keyed by server name (from tools/list response).
    public private(set) var serverInstructions: [String: String] = [:]

    /// Server names that failed to connect (with error messages).
    public private(set) var failures: [(server: String, error: String)] = []

    // MARK: - Config Discovery

    /// Search paths for MCP configuration files.
    /// Priority order: project-local wins over user-global.
    private struct ConfigPath: Sendable {
        let path: String
        let scope: ConfigScope
    }

    /// Discover all MCP config files.
    private func discoverConfigPaths(cwd: String, home: String) -> [ConfigPath] {
        var paths: [ConfigPath] = []

        // Project-local (highest priority)
        let projectPaths = [
            "\(cwd)/.mcp.json",
            "\(cwd)/mcp.json",
            "\(cwd)/.omp/mcp.json"
        ]
        for p in projectPaths {
            if FileManager.default.fileExists(atPath: p) {
                paths.append(ConfigPath(path: p, scope: .project))
            }
        }

        // User-global (lower priority)
        let userPaths = [
            "\(home)/.claude/mcp.json",
            "\(home)/.omp/agent/mcp.json"
        ]
        for p in userPaths {
            if FileManager.default.fileExists(atPath: p) {
                paths.append(ConfigPath(path: p, scope: .user))
            }
        }

        return paths
    }

    /// Parse a single MCP config file.
    private func parseConfigFile(at path: String) -> [String: MCPDiscriminatedServerConfig] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: [String: Any]]
        else { return [:] }

        var result: [String: MCPDiscriminatedServerConfig] = [:]
        for (name, raw) in servers {
            guard let type = raw["type"] as? String else {
                // Default to stdio
                guard let command = raw["command"] as? String else { continue }
                let args = raw["args"] as? [String] ?? []
                let env = raw["env"] as? [String: String]
                result[name] = .stdio(MCPStdioServerConfig(command: command, args: args, env: env))
                continue
            }

            switch type {
            case "stdio":
                guard let command = raw["command"] as? String else { continue }
                let args = raw["args"] as? [String] ?? []
                let env = raw["env"] as? [String: String]
                result[name] = .stdio(MCPStdioServerConfig(command: command, args: args, env: env))
            case "sse":
                guard let url = raw["url"] as? String else { continue }
                let headers = raw["headers"] as? [String: String]
                result[name] = .sse(MCPSSEServerConfig(url: url, headers: headers))
            case "http", "streamable-http":
                guard let url = raw["url"] as? String else { continue }
                let headers = raw["headers"] as? [String: String]
                result[name] = .http(MCPHTTPServerConfig(url: url, headers: headers))
            default:
                continue
            }
        }

        return result
    }

    // MARK: - Bootstrap

    /// Load all MCP configs, connect to servers, and discover tools.
    ///
    /// - Parameters:
    ///   - cwd: Current working directory (project root)
    ///   - home: User home directory
    /// - Returns: The set of discovered `ToolDefinition`s ready for registration.
    public func bootstrap(cwd: String, home: String) async -> [ToolDefinition] {
        let configPaths = discoverConfigPaths(cwd: cwd, home: home)

        // Collect all server configs. First-seen wins (project over user).
        var allConfigs: [String: (config: MCPDiscriminatedServerConfig, scope: ConfigScope)] = [:]
        for cp in configPaths {
            let parsed = parseConfigFile(at: cp.path)
            for (name, config) in parsed where allConfigs[name] == nil {
                allConfigs[name] = (config, cp.scope)
            }
        }

        // Connect to each server (limited local concurrency: 3 at a time)
        let localConfigs = allConfigs.filter { _, v in
            switch v.config {
            case .stdio: return true
            default: return false
            }
        }

        // Connect stdio servers with limited concurrency
        let localBatchSize = 3
        let sortedLocal = Array(localConfigs)
        var collectedInstructions: [String: String] = [:]
        for batch in stride(from: 0, to: sortedLocal.count, by: localBatchSize) {
            let end = min(batch + localBatchSize, sortedLocal.count)
            await withTaskGroup(of: (String, MCPClient?, [ToolDefinition], [SerializedMCPResource]?, String?, String?).self) { group in
                for i in batch..<end {
                    let (name, entry) = sortedLocal[i]
                    group.addTask {
                        await self.connectAndDiscover(name: name, config: entry.config, scope: entry.scope)
                    }
                }
                for await (name, client, tools, resources, instructions, error) in group {
                    if let client {
                        clients[name] = client
                        collectedInstructions[name] = instructions
                    }
                    toolDefinitions.append(contentsOf: tools)
                    if let resources { self.resources[name] = resources }
                    if let error { failures.append((name, error)) }
                }
            }
        }

        // Connect remote servers (batch of 20)
        let remoteConfigs = allConfigs.filter { _, v in
            switch v.config {
            case .stdio: return false
            default: return true
            }
        }

        if !remoteConfigs.isEmpty {
            await withTaskGroup(of: (String, MCPClient?, [ToolDefinition], [SerializedMCPResource]?, String?, String?).self) { group in
                for (name, entry) in remoteConfigs {
                    group.addTask {
                        await self.connectAndDiscover(name: name, config: entry.config, scope: entry.scope)
                    }
                }
                for await (name, client, tools, resources, instructions, error) in group {
                    if let client {
                        clients[name] = client
                        collectedInstructions[name] = instructions
                    }
                    toolDefinitions.append(contentsOf: tools)
                    if let resources { self.resources[name] = resources }
                    if let error { failures.append((name, error)) }
                }
            }
        }

        serverInstructions = collectedInstructions.compactMapValues { $0 }
        return toolDefinitions
    }

    /// Connect to one server and discover its tools/resources.
    private func connectAndDiscover(
        name: String,
        config: MCPDiscriminatedServerConfig,
        scope: ConfigScope
    ) async -> (String, MCPClient?, [ToolDefinition], [SerializedMCPResource]?, String?, String?) {
        // 10-second timeout per server — MCP is a startup optimization, not a hard dependency
        let result = await withTimeout(seconds: 10) {
            await self.doConnectAndDiscover(name: name, config: config)
        }
        return result ?? (name, nil, [], nil, nil, "Connection timed out after 10s")
    }

    /// Runs a block with a timeout. Returns nil if the timeout fires first.
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            // Return the first completed result
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    /// Actually connect and discover (called within a timeout).
    private func doConnectAndDiscover(
        name: String,
        config: MCPDiscriminatedServerConfig
    ) async -> (String, MCPClient?, [ToolDefinition], [SerializedMCPResource]?, String?, String?) {
        let transport: any MCPTransport

        switch config {
        case .stdio(let stdioConfig):
            var cmd = [stdioConfig.command]
            cmd.append(contentsOf: stdioConfig.args)
            transport = StdioTransport(command: cmd)

        case .sse(let sseConfig):
            guard let url = URL(string: sseConfig.url) else {
                return (name, nil, [], nil, nil, "Invalid URL: \(sseConfig.url)")
            }
            transport = SSETransport(url: url, headers: sseConfig.headers ?? [:])

        case .http(let httpConfig):
            guard let url = URL(string: httpConfig.url) else {
                return (name, nil, [], nil, nil, "Invalid URL: \(httpConfig.url)")
            }
            transport = HTTPTransport(url: url, headers: httpConfig.headers ?? [:])

        case .ws(let wsConfig):
            guard let url = URL(string: wsConfig.url) else {
                return (name, nil, [], nil, nil, "Invalid URL: \(wsConfig.url)")
            }
            let wsTransport = MCPWebSocketTransport(url: url, headers: wsConfig.headers ?? [:])
            transport = wsTransport

        case .sseIDE, .wsIDE, .sdk, .claudeAIProxy:
            return (name, nil, [], nil, nil, "Transport type not yet supported: \(config)")
        }

        let client = MCPClient(transport: transport)

        do {
            try await client.connect()

            let (mcpTools, toolsListInstructions) = try await client.listTools()
            // Prefer InitializeResult.instructions (canonical per MCP spec),
            // falling back to tools/list instructions.
            let instructions = await client.initializeInstructions ?? toolsListInstructions
            let defs = MCPToolBridge.buildMCPToolDefinitions(from: mcpTools, serverName: name)

            let mcpResources = (try? await client.listResources()) ?? []
            let serialized = mcpResources.map { res in
                SerializedMCPResource(
                    server: name,
                    uri: res.uri,
                    name: res.name,
                    description: res.description,
                    mimeType: res.mimeType
                )
            }

            return (name, client, defs, serialized, instructions, nil)
        } catch {
            await client.disconnect()
            return (name, nil, [], nil, nil, error.localizedDescription)
        }
    }

    // MARK: - Tool Invocation

    /// Invoke a tool on one of the connected MCP servers.
    public func callTool(serverName: String, toolName: String, arguments: [String: JSONValue]) async throws -> ToolResult {
        guard let rawClient = clients[serverName] else {
            return ToolResult(content: "MCP server '\(serverName)' is not connected.", isError: true)
        }

        let result = try await rawClient.callTool(name: toolName, arguments: arguments)
        return MCPToolBridge.buildToolResult(result)
    }

    /// Disconnect all clients.
    public func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
        toolDefinitions.removeAll()
        resources.removeAll()
        failures.removeAll()
    }
}
