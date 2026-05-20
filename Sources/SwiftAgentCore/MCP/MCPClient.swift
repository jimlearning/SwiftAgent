import Foundation

/// High-level MCP client. Connects to an MCP server via a transport,
/// handles the initialize handshake, and exposes tool operations.
public actor MCPClient {
    private let transport: MCPTransport
    private var nextID = 1
    private var isInitialized = false

    public init(transport: MCPTransport) {
        self.transport = transport
    }

    /// Connect and perform the MCP initialize handshake.
    public func connect() async throws {
        try await transport.connect()

        _ = try await sendRequest(method: "initialize", params: [
            "protocolVersion": JSONValue.string("2024-11-05"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("SwiftAgent"),
                "version": .string("0.1.0")
            ])
        ])

        _ = try? await sendRequest(method: "notifications/initialized", params: nil)
        isInitialized = true
    }

    /// List tools available on the MCP server.
    public func listTools() async throws -> [MCPToolDescription] {
        let result = try await sendRequest(method: "tools/list", params: nil)
        guard let tools = result?["tools"] else { return [] }
        guard case .array(let items) = tools else { return [] }

        return items.compactMap { item in
            guard case .object(let obj) = item,
                  let name = obj["name"],
                  case .string(let nameStr) = name else { return nil }

            let desc = obj["description"].flatMap { v -> String? in
                if case .string(let s) = v { return s }
                return nil
            }

            return MCPToolDescription(name: nameStr, description: desc, inputSchema: JSONSchema(type: "object", properties: [:]))
        }
    }

    /// Call a tool on the MCP server by name.
    public func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        let result = try await sendRequest(method: "tools/call", params: [
            "name": .string(name),
            "arguments": .object(arguments)
        ])

        guard let content = result?["content"] else {
            throw MCPError.toolNotFound(name)
        }

        switch content {
        case .array(let blocks):
            let text = blocks.compactMap { block -> String? in
                guard case .object(let obj) = block,
                      let type = obj["type"], case .string("text") = type,
                      let textVal = obj["text"], case .string(let t) = textVal else { return nil }
                return t
            }.joined(separator: "\n")
            return MCPToolResult(content: text, isError: false)
        case .string(let s):
            return MCPToolResult(content: s, isError: false)
        default:
            return MCPToolResult(content: "", isError: false)
        }
    }

    // MARK: - Resources

    /// List resources from the MCP server.
    public func listResources() async throws -> [MCPResourceDescription] {
        let result = try await sendRequest(method: "resources/list", params: nil)
        guard let resources = result?["resources"],
              case .array(let items) = resources else { return [] }

        return items.compactMap { item in
            guard case .object(let obj) = item,
                  let uri = obj["uri"], case .string(let uriStr) = uri,
                  let name = obj["name"], case .string(let nameStr) = name else { return nil }

            let desc = obj["description"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            let mime = obj["mimeType"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            return MCPResourceDescription(uri: uriStr, name: nameStr, description: desc, mimeType: mime)
        }
    }

    /// Read a specific resource from the MCP server.
    public func readResource(uri: String) async throws -> MCPResourceReadResult {
        let result = try await sendRequest(method: "resources/read", params: [
            "uri": .string(uri)
        ])
        guard let contents = result?["contents"],
              case .array(let items) = contents else {
            return MCPResourceReadResult(contents: [])
        }

        let parsed = items.compactMap { item -> MCPResourceContent? in
            guard case .object(let obj) = item,
                  let itemUri = obj["uri"], case .string(let uriStr) = itemUri else { return nil }

            let mime = obj["mimeType"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            let text = obj["text"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            let blob = obj["blob"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            return MCPResourceContent(uri: uriStr, mimeType: mime, text: text, blob: blob)
        }
        return MCPResourceReadResult(contents: parsed)
    }

    // MARK: - Prompts

    /// List prompts from the MCP server.
    public func listPrompts() async throws -> [MCPPromptDescription] {
        let result = try await sendRequest(method: "prompts/list", params: nil)
        guard let prompts = result?["prompts"],
              case .array(let items) = prompts else { return [] }

        return items.compactMap { item in
            guard case .object(let obj) = item,
                  let name = obj["name"], case .string(let nameStr) = name else { return nil }

            let desc = obj["description"].flatMap { v -> String? in
                if case .string(let s) = v { return s } else { return nil }
            }
            let args: [MCPPromptArgument]? = obj["arguments"].flatMap { v -> [MCPPromptArgument]? in
                guard case .array(let argItems) = v else { return nil }
                return argItems.compactMap { arg -> MCPPromptArgument? in
                    guard case .object(let argObj) = arg,
                          let argName = argObj["name"], case .string(let argNameStr) = argName else { return nil }
                    let argDesc = argObj["description"].flatMap { a -> String? in
                        if case .string(let s) = a { return s } else { return nil }
                    }
                    let required = argObj["required"].flatMap { r -> Bool? in
                        if case .bool(let b) = r { return b } else { return nil }
                    } ?? false
                    return MCPPromptArgument(name: argNameStr, description: argDesc, required: required)
                }
            }
            return MCPPromptDescription(name: nameStr, description: desc, arguments: args)
        }
    }

    /// Get a specific prompt from the MCP server with arguments.
    public func getPrompt(name: String, arguments: [String: String]? = nil) async throws -> MCPPromptResult {
        var params: [String: JSONValue] = ["name": .string(name)]
        if let args = arguments, !args.isEmpty {
            params["arguments"] = .object(args.mapValues { .string($0) })
        }
        let result = try await sendRequest(method: "prompts/get", params: params)
        guard let messages = result?["messages"],
              case .array(let items) = messages else {
            return MCPPromptResult(messages: [])
        }

        let desc = result?["description"].flatMap { v -> String? in
            if case .string(let s) = v { return s } else { return nil }
        }

        let parsed = items.compactMap { item -> MCPPromptMessage? in
            guard case .object(let obj) = item,
                  let role = obj["role"], case .string(let roleStr) = role,
                  let content = obj["content"] else { return nil }

            let parsedContent: MCPPromptContent
            if case .object(let contentObj) = content {
                if let type = contentObj["type"], case .string("text") = type,
                   let text = contentObj["text"], case .string(let textStr) = text {
                    parsedContent = .text(textStr)
                } else if let type = contentObj["type"], case .string("image") = type,
                          let data = contentObj["data"], case .string(let dataStr) = data,
                          let mime = contentObj["mimeType"], case .string(let mimeStr) = mime {
                    parsedContent = .image(type: "image", data: dataStr, mimeType: mimeStr)
                } else {
                    return nil
                }
            } else if case .string(let textStr) = content {
                parsedContent = .text(textStr)
            } else {
                return nil
            }
            return MCPPromptMessage(role: roleStr, content: parsedContent)
        }

        return MCPPromptResult(description: desc, messages: parsed)
    }

    /// Disconnect from the server.
    public func disconnect() async {
        await transport.disconnect()
        isInitialized = false
    }

    private func sendRequest(method: String, params: [String: JSONValue]?) async throws -> [String: JSONValue]? {
        let id = nextID
        nextID += 1

        let response = try await transport.send(.request(id: id, method: method, params: params))
        switch response {
        case .response(_, let result):
            return result
        case .error(_, let code, let message):
            throw MCPError.serverError(code: code, message: message)
        default:
            throw MCPError.invalidResponse
        }
    }
}

/// Description of an MCP tool (from tools/list response).
public struct MCPToolDescription: Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema?

    public init(name: String, description: String? = nil, inputSchema: JSONSchema? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Result of calling an MCP tool (from tools/call response).
public struct MCPToolResult: Sendable {
    public let content: String
    public let isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}
