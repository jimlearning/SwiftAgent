import Foundation

/// A dynamically registered MCP tool that dispatches to a connected MCP server.
///
/// Each discovered MCP tool from a server gets one instance, registered by its
/// fully-qualified name (e.g. `mcp__codegraph__codegraph_search`). When called,
/// it parses the server/tool name from the prefix and dispatches through the
/// shared MCPBootstrapper.
public struct DynamicMCPTool: Tool {
    public let name: String
    public let inputSchema: JSONSchema
    public let isMcp: Bool = true
    public let shouldDefer: Bool = true
    public let mcpInfo: MCPToolInfo?

    private let serverName: String
    private let toolName: String
    private let toolDescription: String
    private let bootstrapper: MCPBootstrapper

    public init(
        serverName: String,
        toolName: String,
        toolDescription: String,
        inputSchema: JSONSchema,
        bootstrapper: MCPBootstrapper
    ) {
        self.serverName = serverName
        self.toolName = toolName
        self.toolDescription = toolDescription
        self.name = buildMcpToolName(serverName: serverName, toolName: toolName)
        self.inputSchema = inputSchema
        self.bootstrapper = bootstrapper
        self.mcpInfo = MCPToolInfo(serverName: serverName, toolName: toolName)
    }

    public func description(
        input: [String: JSONValue],
        options: ToolDescriptionOptions
    ) async -> String {
        toolDescription
    }

    public func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn? = nil,
        parentMessage: Message? = nil,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
        return try await bootstrapper.callTool(
            serverName: serverName,
            toolName: toolName,
            arguments: input
        )
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "\(serverName):\(toolName)"
    }
}
