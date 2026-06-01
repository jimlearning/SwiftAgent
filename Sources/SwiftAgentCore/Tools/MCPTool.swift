import Foundation

/// Invokes an MCP server tool by server name and tool name.
///
/// This is the "meta" tool that the LLM calls when it wants to use a specific
/// MCP server tool. It looks up the connected MCP client by server name,
/// parses the tool arguments, dispatches the call, and returns the result.
///
/// CC analogue: the MCP tool dispatch path in `mcpTool.ts`.
public struct MCPTool: Tool {
    public let name = "MCP"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Invoke a tool on a connected MCP (Model Context Protocol) server"
    }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public let isMcp = true
    public let mcpInfo: MCPToolInfo? = nil

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["serverName"] = JSONSchemaProperty(
            type: "string",
            description: "The MCP server name (e.g. 'codegraph')"
        )
        schema.properties?["toolName"] = JSONSchemaProperty(
            type: "string",
            description: "The tool name on the MCP server (e.g. 'codegraph_search')"
        )
        schema.properties?["arguments"] = JSONSchemaProperty(
            type: "string",
            description: "JSON-encoded tool arguments"
        )
        schema.required = ["serverName", "toolName"]
        return schema
    }()

    public init() {}

    public func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn? = nil,
        parentMessage: Message? = nil,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
        guard case .string(let serverName) = input["serverName"] else {
            return ToolResult(content: "Error: serverName is required", isError: true)
        }
        guard case .string(let toolName) = input["toolName"] else {
            return ToolResult(content: "Error: toolName is required", isError: true)
        }

        // Parse arguments from JSON string
        let arguments: [String: JSONValue]
        if case .string(let argStr) = input["arguments"], !argStr.isEmpty {
            guard let data = argStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ToolResult(content: "Error: invalid JSON arguments", isError: true)
            }
            arguments = json.compactMapValues { JSONValue.fromAny($0) }
        } else {
            arguments = [:]
        }

        // Try to find the MCP client from context
        guard let mcpClients = context.mcpClients, !mcpClients.isEmpty else {
            return ToolResult(content: "No MCP servers connected. Use /mcp to manage connections.", isError: true)
        }

        // Find the client for this server
        for rawClient in mcpClients {
            guard let mcpClient = rawClient as? MCPClient else { continue }
            do {
                let result = try await mcpClient.callTool(name: toolName, arguments: arguments)
                return ToolResult(content: result.content, isError: result.isError)
            } catch {
                // Try next client (in case multiple clients match)
                continue
            }
        }

        return ToolResult(
            content: "MCP server '\(serverName)' not found or tool '\(toolName)' failed. Connected servers: \(mcpClients.count)",
            isError: true
        )
    }
}
