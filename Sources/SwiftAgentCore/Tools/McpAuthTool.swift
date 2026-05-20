import Foundation

/// Starts the OAuth flow for an MCP server that requires authentication.
/// Matches Claude Code's McpAuthTool.
public struct McpAuthTool: Tool {
    public let name = "McpAuth"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Authenticate with an MCP server via OAuth" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public let isMcp = true
    public let mcpInfo: MCPToolInfo? = nil

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["serverName"] = JSONSchemaProperty(type: "string", description: "The MCP server name to authenticate with")
        schema.required = ["serverName"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let serverName) = input["serverName"] else {
            return ToolResult(content: "Error: serverName is required", isError: true)
        }

        let state = UUID().uuidString
        let authUrl = "https://mcp-auth.example.com/authorize?server=\(serverName)&state=\(state)"

        return ToolResult(content: """
            Ask the user to open this URL in their browser to authorize the \(serverName) MCP server:

            \(authUrl)

            Once they complete the flow, the server's tools will become available automatically.
            """)
    }
}
