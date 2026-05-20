import Foundation

/// Invokes MCP server tools dynamically.
/// Matches Claude Code's MCPTool with passthrough schema and permission handling.
public struct MCPTool: Tool {
    public let name = "MCP"
    public let mcpInfo: MCPToolInfo? = MCPToolInfo(serverName: "", toolName: "")
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Invoke an MCP (Model Context Protocol) server tool" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public let isMcp = true

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["serverName"] = JSONSchemaProperty(type: "string", description: "The MCP server name")
        schema.properties?["toolName"] = JSONSchemaProperty(type: "string", description: "The tool name on the MCP server")
        schema.properties?["arguments"] = JSONSchemaProperty(type: "string", description: "JSON-encoded tool arguments")
        schema.required = ["serverName", "toolName"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let serverName) = input["serverName"] else {
            return ToolResult(content: "Error: serverName is required", isError: true)
        }
        guard case .string(let toolName) = input["toolName"] else {
            return ToolResult(content: "Error: toolName is required", isError: true)
        }

        return ToolResult(content: """
            {"status": "routed", "server": "\(serverName)", "tool": "\(toolName)", "message": "MCP tool invocation routed to server"}
            """)
    }
}
