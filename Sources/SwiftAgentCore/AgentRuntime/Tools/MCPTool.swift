import Foundation

/// Invokes an MCP server tool by server name and tool name.
///
/// This is the "meta" tool that the LLM calls when it wants to use a specific
/// MCP server tool. It iterates connected MCP clients, parses the tool
/// arguments, dispatches the call, and returns the result.
///
/// CC analogue: the MCP tool dispatch path in `mcpTool.ts`.
public struct MCPTool: Tool {
    public let name = "MCP"
    public let description = "Invoke a tool on a connected MCP (Model Context Protocol) server"

    private let mcpClients: [any Sendable]

    public struct Arguments: Codable, Sendable {
        public var serverName: String
        public var toolName: String
        public var arguments: String?

        enum CodingKeys: String, CodingKey {
            case serverName
            case toolName
            case arguments
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
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
    }

    public init(mcpClients: [any Sendable] = []) {
        self.mcpClients = mcpClients
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        // Parse arguments from JSON string
        let toolArgs: [String: JSONValue]
        if let argStr = arguments.arguments, !argStr.isEmpty {
            guard let data = argStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return .string("Error: invalid JSON arguments")
            }
            toolArgs = json.compactMapValues { JSONValue.fromAny($0) }
        } else {
            toolArgs = [:]
        }

        guard !mcpClients.isEmpty else {
            return .string("No MCP servers connected. Use /mcp to manage connections.")
        }

        // Try each connected MCP client
        for rawClient in mcpClients {
            guard let mcpClient = rawClient as? MCPClient else { continue }
            do {
                let result = try await mcpClient.callTool(name: arguments.toolName, arguments: toolArgs)
                if result.isError {
                    return .string("Error: \(result.content)")
                }
                return .string(result.content)
            } catch {
                continue
            }
        }

        return .string(
            "MCP server '\(arguments.serverName)' not found or tool '\(arguments.toolName)' failed. Connected servers: \(mcpClients.count)"
        )
    }
}
