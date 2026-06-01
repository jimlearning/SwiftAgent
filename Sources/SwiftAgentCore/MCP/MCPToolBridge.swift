import Foundation

/// Bridges MCP tools into the agent's Tool system.
public struct MCPToolBridge: Sendable {

    /// Convert MCP tool descriptions into ToolDefinition for use in QueryEngine.
    public static func buildToolDefinitions(from tools: [MCPToolDescription]) -> [ToolDefinition] {
        tools.map { tool in
            ToolDefinition(
                name: tool.name,
                description: tool.description ?? "MCP tool: \(tool.name)",
                inputSchema: tool.inputSchema ?? JSONSchema(type: "object", properties: [:])
            )
        }
    }

    /// Convert MCP tool descriptions into ToolDefinition with server-prefixed names.
    /// E.g. codegraph's `codegraph_search` → `mcp__codegraph__codegraph_search`.
    public static func buildMCPToolDefinitions(from tools: [MCPToolDescription], serverName: String) -> [ToolDefinition] {
        let prefix = getMcpPrefix(serverName)
        return tools.map { tool in
            ToolDefinition(
                name: "\(prefix)\(tool.name)",
                description: tool.description ?? "[\(serverName)] \(tool.name)",
                inputSchema: tool.inputSchema ?? JSONSchema(type: "object", properties: [:])
            )
        }
    }

    /// Convert MCP tool result into the agent's ToolResult.
    public static func buildToolResult(_ result: MCPToolResult) -> ToolResult {
        ToolResult(content: result.content, isError: result.isError)
    }

    /// Load all tools from an MCP server configuration entry.
    public static func loadTools(from config: MCPServerConfig) async throws -> [ToolDefinition] {
        let transport: any MCPTransport

        switch config.transport {
        case .stdio:
            guard let command = config.command, !command.isEmpty else {
                throw MCPError.invalidResponse
            }
            transport = StdioTransport(command: command)
        case .sse:
            guard let url = config.url.flatMap({ URL(string: $0) }) else {
                throw MCPError.invalidResponse
            }
            transport = SSETransport(url: url, headers: config.headers ?? [:])
        case .http:
            guard let url = config.url.flatMap({ URL(string: $0) }) else {
                throw MCPError.invalidResponse
            }
            transport = HTTPTransport(url: url, headers: config.headers ?? [:])
        case .sseIde:
            guard let url = config.url.flatMap({ URL(string: $0) }) else {
                throw MCPError.invalidResponse
            }
            transport = SSETransport(url: url, headers: config.headers ?? [:])
        case .ws, .wsIde:
            guard config.url.flatMap({ URL(string: $0) }) != nil else {
                throw MCPError.invalidResponse
            }
            throw MCPError.transportNotConnected
        case .sdk:
            throw MCPError.transportNotConnected
        case .claudeaiProxy:
            guard config.url.flatMap({ URL(string: $0) }) != nil else {
                throw MCPError.invalidResponse
            }
            throw MCPError.transportNotConnected
        }

        let client = MCPClient(transport: transport)
        try await client.connect()
        let tools = try await client.listTools()
        await client.disconnect()

        return buildToolDefinitions(from: tools)
    }
}
