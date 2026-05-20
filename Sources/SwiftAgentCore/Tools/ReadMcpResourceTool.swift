import Foundation

/// Reads a specific MCP resource by URI.
/// Matches Claude Code's ReadMcpResourceTool.
public struct ReadMcpResourceTool: Tool {
    public let name = "ReadMcpResource"
    public var searchHint: String? { "read a specific MCP resource by URI" }
    public let isMcp = true
    public let mcpInfo: MCPToolInfo? = MCPToolInfo(serverName: "", toolName: "ReadMcpResource")
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Read a specific MCP resource by URI" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["server"] = JSONSchemaProperty(type: "string", description: "The MCP server name")
        schema.properties?["uri"] = JSONSchemaProperty(type: "string", description: "The resource URI to read")
        schema.required = ["server", "uri"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let uriVal = input["uri"], case .string(let uri) = uriVal else {
            return ToolResult(content: "Error: uri is required", isError: true)
        }

        guard let mcpClients = context.mcpClients, !mcpClients.isEmpty else {
            return ToolResult(content: "No MCP servers connected. Connect MCP servers first via settings.", isError: true)
        }

        for client in mcpClients {
            guard let mcpClient = client as? MCPClient else { continue }
            if let readResult = try? await mcpClient.readResource(uri: uri) {
                if !readResult.contents.isEmpty {
                    let contents = readResult.contents.map { content -> [String: Any] in
                        var c: [String: Any] = ["uri": content.uri]
                        if let text = content.text { c["text"] = text }
                        if let blob = content.blob { c["blob"] = blob }
                        if let mime = content.mimeType { c["mimeType"] = mime }
                        return c
                    }
                    let result: [String: Any] = ["contents": contents]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                       let jsonStr = String(data: jsonData, encoding: .utf8) {
                        return ToolResult(content: jsonStr)
                    }
                }
            }
        }

        return ToolResult(content: "Resource \"\(uri)\" not found on any connected MCP server.", isError: true)
    }
}
