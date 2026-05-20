import Foundation

// MARK: - Config Scope

/// Where a server config was loaded from.
/// Matches CC's ConfigScope: 'local' | 'user' | 'project' | 'dynamic' | 'enterprise' | 'claudeai' | 'managed'.
public enum ConfigScope: String, Codable, Sendable {
    case local
    case user
    case project
    case dynamic
    case enterprise
    case claudeai
    case managed
}

// MARK: - Transport Type

/// Transport discriminant for MCP server configs (caller-side).
/// Matches CC's Transport: 'stdio' | 'sse' | 'sse-ide' | 'http' | 'ws' | 'sdk'.
/// NOTE: Distinct from MCPTransportType in Config.swift which uses "streamable-http" for HTTP.
/// TODO: Consolidate with legacy MCPTransportType when the old flat config is retired.
public enum MCPServerTransportType: String, Codable, Sendable {
    case stdio
    case sse
    case sseIDE = "sse-ide"
    case http
    case ws
    case sdk
}

// MARK: - OAuth Config

/// OAuth configuration for SSE and HTTP MCP transports.
/// Matches CC's McpOAuthConfig.
public struct MCPOAuthConfig: Codable, Sendable {
    public let clientId: String?
    public let callbackPort: Int?
    public let authServerMetadataUrl: String?
    public let xaa: Bool?

    public init(
        clientId: String? = nil,
        callbackPort: Int? = nil,
        authServerMetadataUrl: String? = nil,
        xaa: Bool? = nil
    ) {
        self.clientId = clientId
        self.callbackPort = callbackPort
        self.authServerMetadataUrl = authServerMetadataUrl
        self.xaa = xaa
    }
}

// MARK: - Server Config Discriminated Union

/// A discriminated union of all 8 MCP server config shapes.
/// Matches CC's McpServerConfig.
/// NOTE: Coexists with legacy flat MCPServerConfig struct in Config.swift.
/// TODO: Replace legacy MCPServerConfig struct with this discriminated union.
public enum MCPDiscriminatedServerConfig: Codable, Sendable {
    case stdio(MCPStdioServerConfig)
    case sse(MCPSSEServerConfig)
    case sseIDE(MCPSSEIDEServerConfig)
    case wsIDE(MCPWebSocketIDEServerConfig)
    case http(MCPHTTPServerConfig)
    case ws(MCPWebSocketServerConfig)
    case sdk(MCPSDKServerConfig)
    case claudeAIProxy(MCPClaudeAIProxyServerConfig)

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "stdio"
        let single = try decoder.singleValueContainer()
        switch type {
        case "stdio":
            self = .stdio(try single.decode(MCPStdioServerConfig.self))
        case "sse":
            self = .sse(try single.decode(MCPSSEServerConfig.self))
        case "sse-ide":
            self = .sseIDE(try single.decode(MCPSSEIDEServerConfig.self))
        case "ws-ide":
            self = .wsIDE(try single.decode(MCPWebSocketIDEServerConfig.self))
        case "http":
            self = .http(try single.decode(MCPHTTPServerConfig.self))
        case "ws":
            self = .ws(try single.decode(MCPWebSocketServerConfig.self))
        case "sdk":
            self = .sdk(try single.decode(MCPSDKServerConfig.self))
        case "claudeai-proxy":
            self = .claudeAIProxy(try single.decode(MCPClaudeAIProxyServerConfig.self))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MCP server type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .stdio(let c): try single.encode(c)
        case .sse(let c): try single.encode(c)
        case .sseIDE(let c): try single.encode(c)
        case .wsIDE(let c): try single.encode(c)
        case .http(let c): try single.encode(c)
        case .ws(let c): try single.encode(c)
        case .sdk(let c): try single.encode(c)
        case .claudeAIProxy(let c): try single.encode(c)
        }
    }
}

// MARK: - Individual Config Types

/// Matches CC's McpStdioServerConfig: { type?: 'stdio', command: string, args: string[], env?: Record<string,string> }.
public struct MCPStdioServerConfig: Codable, Sendable {
    public var type: String? = "stdio"
    public let command: String
    public var args: [String]
    public var env: [String: String]?

    public init(command: String, args: [String] = [], env: [String: String]? = nil) {
        self.command = command
        self.args = args
        self.env = env
    }
}

/// Matches CC's McpSSEServerConfig: { type: 'sse', url, headers?, headersHelper?, oauth? }.
public struct MCPSSEServerConfig: Codable, Sendable {
    public var type = "sse"
    public let url: String
    public var headers: [String: String]?
    public var headersHelper: String?
    public var oauth: MCPOAuthConfig?

    public init(
        url: String,
        headers: [String: String]? = nil,
        headersHelper: String? = nil,
        oauth: MCPOAuthConfig? = nil
    ) {
        self.url = url
        self.headers = headers
        self.headersHelper = headersHelper
        self.oauth = oauth
    }
}

/// Matches CC's McpSSEIDEServerConfig (internal, IDE extensions only): { type: 'sse-ide', url, ideName, ideRunningInWindows? }.
public struct MCPSSEIDEServerConfig: Codable, Sendable {
    public var type = "sse-ide"
    public let url: String
    public let ideName: String
    public var ideRunningInWindows: Bool?

    public init(url: String, ideName: String, ideRunningInWindows: Bool? = nil) {
        self.url = url
        self.ideName = ideName
        self.ideRunningInWindows = ideRunningInWindows
    }
}

/// Matches CC's McpWebSocketIDEServerConfig (internal, IDE extensions only): { type: 'ws-ide', url, ideName, authToken?, ideRunningInWindows? }.
public struct MCPWebSocketIDEServerConfig: Codable, Sendable {
    public var type = "ws-ide"
    public let url: String
    public let ideName: String
    public var authToken: String?
    public var ideRunningInWindows: Bool?

    public init(
        url: String,
        ideName: String,
        authToken: String? = nil,
        ideRunningInWindows: Bool? = nil
    ) {
        self.url = url
        self.ideName = ideName
        self.authToken = authToken
        self.ideRunningInWindows = ideRunningInWindows
    }

    enum CodingKeys: String, CodingKey {
        case type, url, ideName, ideRunningInWindows
        case authToken
    }
}

/// Matches CC's McpHTTPServerConfig: { type: 'http', url, headers?, headersHelper?, oauth? }.
public struct MCPHTTPServerConfig: Codable, Sendable {
    public var type = "http"
    public let url: String
    public var headers: [String: String]?
    public var headersHelper: String?
    public var oauth: MCPOAuthConfig?

    public init(
        url: String,
        headers: [String: String]? = nil,
        headersHelper: String? = nil,
        oauth: MCPOAuthConfig? = nil
    ) {
        self.url = url
        self.headers = headers
        self.headersHelper = headersHelper
        self.oauth = oauth
    }
}

/// Matches CC's McpWebSocketServerConfig: { type: 'ws', url, headers?, headersHelper? }.
public struct MCPWebSocketServerConfig: Codable, Sendable {
    public var type = "ws"
    public let url: String
    public var headers: [String: String]?
    public var headersHelper: String?

    public init(url: String, headers: [String: String]? = nil, headersHelper: String? = nil) {
        self.url = url
        self.headers = headers
        self.headersHelper = headersHelper
    }
}

/// Matches CC's McpSdkServerConfig: { type: 'sdk', name: string }.
public struct MCPSDKServerConfig: Codable, Sendable {
    public var type = "sdk"
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Matches CC's McpClaudeAIProxyServerConfig: { type: 'claudeai-proxy', url: string, id: string }.
public struct MCPClaudeAIProxyServerConfig: Codable, Sendable {
    public var type = "claudeai-proxy"
    public let url: String
    public let id: String

    public init(url: String, id: String) {
        self.url = url
        self.id = id
    }
}

// MARK: - Scoped Config

/// A server config with its ConfigScope attached.
/// Matches CC's ScopedMcpServerConfig = McpServerConfig & { scope: ConfigScope, pluginSource?: string }.
public struct ScopedMCPDiscriminatedServerConfig: Codable, Sendable {
    public let config: MCPDiscriminatedServerConfig
    public let scope: ConfigScope
    public let pluginSource: String?

    public init(config: MCPDiscriminatedServerConfig, scope: ConfigScope, pluginSource: String? = nil) {
        self.config = config
        self.scope = scope
        self.pluginSource = pluginSource
    }
}

// MARK: - Server Connection State

/// Discriminated union of MCP server connection states.
/// Matches CC's MCPServerConnection.
public enum MCPServerConnection: Sendable {
    case connected(ConnectedMCPServerInfo)
    case failed(FailedMCPServerInfo)
    case needsAuth(NeedsAuthMCPServerInfo)
    case pending(PendingMCPServerInfo)
    case disabled(DisabledMCPServerInfo)
}

/// Matches CC's ConnectedMCPServer.
public struct ConnectedMCPServerInfo: Sendable {
    public let name: String
    public let type = "connected"
    public let capabilities: MCPServerCapabilities
    public let serverInfo: MCPServerInfo?
    public let instructions: String?
    public let config: ScopedMCPDiscriminatedServerConfig

    public init(
        name: String,
        capabilities: MCPServerCapabilities,
        serverInfo: MCPServerInfo? = nil,
        instructions: String? = nil,
        config: ScopedMCPDiscriminatedServerConfig
    ) {
        self.name = name
        self.capabilities = capabilities
        self.serverInfo = serverInfo
        self.instructions = instructions
        self.config = config
    }
}

public struct MCPServerCapabilities: Codable, Sendable {
    public let experimental: [String: JSONValue]?

    public init(experimental: [String: JSONValue]? = nil) {
        self.experimental = experimental
    }
}

public struct MCPServerInfo: Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Matches CC's FailedMCPServer.
public struct FailedMCPServerInfo: Sendable {
    public let name: String
    public let type = "failed"
    public let config: ScopedMCPDiscriminatedServerConfig
    public let error: String?

    public init(name: String, config: ScopedMCPDiscriminatedServerConfig, error: String? = nil) {
        self.name = name
        self.config = config
        self.error = error
    }
}

/// Matches CC's NeedsAuthMCPServer.
public struct NeedsAuthMCPServerInfo: Sendable {
    public let name: String
    public let type = "needs-auth"
    public let config: ScopedMCPDiscriminatedServerConfig

    public init(name: String, config: ScopedMCPDiscriminatedServerConfig) {
        self.name = name
        self.config = config
    }
}

/// Matches CC's PendingMCPServer.
public struct PendingMCPServerInfo: Sendable {
    public let name: String
    public let type = "pending"
    public let config: ScopedMCPDiscriminatedServerConfig
    public var reconnectAttempt: Int?
    public var maxReconnectAttempts: Int?

    public init(
        name: String,
        config: ScopedMCPDiscriminatedServerConfig,
        reconnectAttempt: Int? = nil,
        maxReconnectAttempts: Int? = nil
    ) {
        self.name = name
        self.config = config
        self.reconnectAttempt = reconnectAttempt
        self.maxReconnectAttempts = maxReconnectAttempts
    }
}

/// Matches CC's DisabledMCPServer.
public struct DisabledMCPServerInfo: Sendable {
    public let name: String
    public let type = "disabled"
    public let config: ScopedMCPDiscriminatedServerConfig

    public init(name: String, config: ScopedMCPDiscriminatedServerConfig) {
        self.name = name
        self.config = config
    }
}

// MARK: - CLI State

/// MCP CLI state for persistence and display.
/// Matches CC's MCPCliState.
public struct MCPCLIState: Codable, Sendable {
    public let clients: [SerializedMCPClient]
    public let configs: [String: ScopedMCPDiscriminatedServerConfig]
    public let tools: [SerializedMCPTool]
    public let resources: [String: [SerializedMCPResource]]
    public let normalizedNames: [String: String]?

    public init(
        clients: [SerializedMCPClient] = [],
        configs: [String: ScopedMCPDiscriminatedServerConfig] = [:],
        tools: [SerializedMCPTool] = [],
        resources: [String: [SerializedMCPResource]] = [:],
        normalizedNames: [String: String]? = nil
    ) {
        self.clients = clients
        self.configs = configs
        self.tools = tools
        self.resources = resources
        self.normalizedNames = normalizedNames
    }
}

/// Matches CC's SerializedClient.
public struct SerializedMCPClient: Codable, Sendable {
    public let name: String
    public let type: String  // 'connected' | 'failed' | 'needs-auth' | 'pending' | 'disabled'
    public let capabilities: MCPServerCapabilities?

    public init(name: String, type: String, capabilities: MCPServerCapabilities? = nil) {
        self.name = name
        self.type = type
        self.capabilities = capabilities
    }
}

/// Matches CC's SerializedTool.
public struct SerializedMCPTool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputJSONSchema: [String: JSONValue]?
    public let isMcp: Bool?
    public let originalToolName: String?

    public init(
        name: String,
        description: String,
        inputJSONSchema: [String: JSONValue]? = nil,
        isMcp: Bool? = nil,
        originalToolName: String? = nil
    ) {
        self.name = name
        self.description = description
        self.inputJSONSchema = inputJSONSchema
        self.isMcp = isMcp
        self.originalToolName = originalToolName
    }

    enum CodingKeys: String, CodingKey {
        case name, description, isMcp, originalToolName
        case inputJSONSchema
    }
}

/// Matches CC's ServerResource = Resource & { server: string }.
public struct SerializedMCPResource: Codable, Sendable {
    public let server: String
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(
        server: String,
        uri: String,
        name: String,
        description: String? = nil,
        mimeType: String? = nil
    ) {
        self.server = server
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }

    enum CodingKeys: String, CodingKey {
        case server, uri, name, description
        case mimeType
    }
}

// MARK: - MCP JSON Config (.mcp.json shape)

/// Matches CC's McpJsonConfig: { mcpServers: Record<string, McpServerConfig> }.
public struct MCPJSONConfig: Codable, Sendable {
    public let mcpServers: [String: MCPDiscriminatedServerConfig]

    public init(mcpServers: [String: MCPDiscriminatedServerConfig] = [:]) {
        self.mcpServers = mcpServers
    }
}

// MARK: - Enterprise Policy Types

/// Matches CC's AllowedMcpServerEntry: { serverName? | serverCommand? | serverUrl? }.
public struct AllowedMCPServerEntry: Codable, Sendable {
    public let serverName: String?
    public let serverCommand: [String]?
    public let serverUrl: String?

    public init(
        serverName: String? = nil,
        serverCommand: [String]? = nil,
        serverUrl: String? = nil
    ) {
        self.serverName = serverName
        self.serverCommand = serverCommand
        self.serverUrl = serverUrl
    }
}

/// Matches CC's DeniedMcpServerEntry.
public struct DeniedMCPServerEntry: Codable, Sendable {
    public let serverName: String?
    public let serverCommand: [String]?
    public let serverUrl: String?

    public init(
        serverName: String? = nil,
        serverCommand: [String]? = nil,
        serverUrl: String? = nil
    ) {
        self.serverName = serverName
        self.serverCommand = serverCommand
        self.serverUrl = serverUrl
    }
}
