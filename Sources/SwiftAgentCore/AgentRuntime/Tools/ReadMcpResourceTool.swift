import Foundation

/// Reads a specific MCP resource by URI.
/// Matches Claude Code's ReadMcpResourceTool.
public struct ReadMcpResourceTool: Tool {
    public let name = "ReadMcpResourceTool"
    public let description = "Read a specific MCP resource by URI"

    private let mcpClients: [any Sendable]

    public struct Arguments: Codable, Sendable {
        public var server: String?
        public var uri: String

        enum CodingKeys: String, CodingKey {
            case server
            case uri
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["server"] = JSONSchemaProperty(type: "string", description: "The MCP server name")
        schema.properties?["uri"] = JSONSchemaProperty(type: "string", description: "The resource URI to read")
        schema.required = ["server", "uri"]
        return schema
    }

    public init(mcpClients: [any Sendable] = []) {
        self.mcpClients = mcpClients
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard !mcpClients.isEmpty else {
            return .string("No MCP servers connected. Connect MCP servers first via settings.")
        }

        for client in mcpClients {
            guard let mcpClient = client as? MCPClient else { continue }
            if let readResult = try? await mcpClient.readResource(uri: arguments.uri) {
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
                        return .string(jsonStr)
                    }
                }
            }
        }

        return .string("Resource \"\(arguments.uri)\" not found on any connected MCP server.")
    }
}
