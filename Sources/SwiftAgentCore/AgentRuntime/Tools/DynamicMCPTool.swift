import Foundation

/// A dynamically registered MCP tool that dispatches to a connected MCP server.
///
/// Each discovered MCP tool from a server gets one instance, registered by its
/// fully-qualified name (e.g. `mcp__codegraph__codegraph_search`). When called,
/// it forwards arguments to the shared MCPBootstrapper.
public struct DynamicMCPTool: Tool {
    public let name: String
    public let description: String

    private let serverName: String
    private let toolName: String
    private let bootstrapper: MCPBootstrapper

    // MARK: - Arguments

    /// Dynamic MCP tool arguments. Since the schema is determined by the
    /// MCP server at connection time, we use a flexible wrapper that decodes
    /// arbitrary JSON objects into `[String: JSONValue]`.
    public struct Arguments: Codable, Sendable {
        public var rawArguments: [String: JSONValue]

        public init(rawArguments: [String: JSONValue] = [:]) {
            self.rawArguments = rawArguments
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: WrappedJSONValue].self) {
                self.rawArguments = dict.mapValues { $0.value }
            } else {
                self.rawArguments = [:]
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            let wrapped = rawArguments.mapValues { WrappedJSONValue(value: $0) }
            try container.encode(wrapped)
        }
    }

    public var inputSchema: JSONSchema

    // MARK: - Init

    public init(
        serverName: String,
        toolName: String,
        toolDescription: String,
        inputSchema: JSONSchema,
        bootstrapper: MCPBootstrapper
    ) {
        self.serverName = serverName
        self.toolName = toolName
        self.name = buildMcpToolName(serverName: serverName, toolName: toolName)
        self.description = toolDescription
        self.inputSchema = inputSchema
        self.bootstrapper = bootstrapper
    }

    // MARK: - Call

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let result = try await bootstrapper.callTool(
            serverName: serverName,
            toolName: toolName,
            arguments: arguments.rawArguments
        )
        return result
    }
}

// MARK: - WrappedJSONValue

/// Encodes/decodes `JSONValue` as raw JSON instead of enum-tagged format.
/// This allows DynamicMCPTool to accept arbitrary MCP tool argument shapes
/// without requiring a fixed schema at compile time.
private struct WrappedJSONValue: Codable, Sendable {
    let value: JSONValue

    init(value: JSONValue) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self.value = .string(str)
        } else if let num = try? container.decode(Double.self) {
            self.value = .number(num)
        } else if let bool = try? container.decode(Bool.self) {
            self.value = .bool(bool)
        } else if container.decodeNil() {
            self.value = .null
        } else if let arr = try? container.decode([WrappedJSONValue].self) {
            self.value = .array(arr.map { $0.value })
        } else if let dict = try? container.decode([String: WrappedJSONValue].self) {
            self.value = .object(dict.mapValues { $0.value })
        } else {
            self.value = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr.map { WrappedJSONValue(value: $0) })
        case .object(let dict): try container.encode(dict.mapValues { WrappedJSONValue(value: $0) })
        }
    }
}
