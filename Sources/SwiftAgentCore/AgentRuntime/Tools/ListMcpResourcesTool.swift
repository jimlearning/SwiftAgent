import Foundation

/// Lists resources from connected MCP servers.
/// Matches Claude Code's ListMcpResourcesTool.
public struct ListMcpResourcesTool: Tool {
    public let name = "ListMcpResourcesTool"
    public let description = "List resources from connected MCP servers"

    private let mcpClients: [any Sendable]

    public struct Arguments: Codable, Sendable {
        public var server: String?

        enum CodingKeys: String, CodingKey {
            case server
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["server"] = JSONSchemaProperty(type: "string", description: "Optional server name to filter resources by")
        return schema
    }

    public init(mcpClients: [any Sendable] = []) {
        self.mcpClients = mcpClients
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard !mcpClients.isEmpty else {
            return .string("No MCP servers connected. Connect MCP servers first via settings.")
        }

        var allResources: [MCPResourceDescription] = []
        for client in mcpClients {
            guard let mcpClient = client as? MCPClient else { continue }
            let resources = (try? await mcpClient.listResources()) ?? []
            allResources.append(contentsOf: resources)
        }

        if allResources.isEmpty {
            return .string("No resources found. Connected MCP servers may provide tools even if they have no resources to list.")
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
        return .string("[\n\(lines.joined(separator: ",\n"))\n]")
    }
}
