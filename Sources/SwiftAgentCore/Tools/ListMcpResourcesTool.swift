import Foundation

/// Lists resources from connected MCP servers.
/// Matches Claude Code's ListMcpResourcesTool.
public struct ListMcpResourcesTool: Tool {
    public let name = "ListMcpResources"
    public var searchHint: String? { "list resources from connected MCP servers" }
    public let isMcp = true
    public let mcpInfo: MCPToolInfo? = MCPToolInfo(serverName: "", toolName: "ListMcpResources")
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "List resources from connected MCP servers" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["server"] = JSONSchemaProperty(type: "string", description: "Optional server name to filter resources by")
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let mcpClients = context.mcpClients, !mcpClients.isEmpty else {
            return ToolResult(content: "No MCP servers connected. Connect MCP servers first via settings.", isError: true)
        }

        var allResources: [MCPResourceDescription] = []
        for client in mcpClients {
            guard let mcpClient = client as? MCPClient else { continue }
            let resources = (try? await mcpClient.listResources()) ?? []
            allResources.append(contentsOf: resources)
        }

        if allResources.isEmpty {
            return ToolResult(content: "No resources found. Connected MCP servers may provide tools even if they have no resources to list.")
        }

        var lines: [String] = []
        for res in allResources {
            var parts: [String] = ["  {"]
            parts.append("    \"uri\": \"\(res.uri)\"")
            parts.append("    \"name\": \"\(res.name)\"")
            if let desc = res.description { parts.append("    \"description\": \"\(desc)\"") }
            if let mime = res.mimeType { parts.append("    \"mimeType\": \"\(mime)\"") }
            parts.append("  }")
            lines.append(parts.joined(separator: ",\n"))
        }
        return ToolResult(content: "[\n\(lines.joined(separator: ",\n"))\n]")
    }
}
