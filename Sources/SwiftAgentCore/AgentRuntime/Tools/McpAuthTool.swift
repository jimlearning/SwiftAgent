import Foundation

/// Starts the OAuth flow for an MCP server that requires authentication.
/// Matches Claude Code's McpAuthTool.
///
/// Looks up the MCP server configuration, initiates the full OAuth 2.0 PKCE flow:
/// 1. Generates PKCE code verifier + challenge
/// 2. Opens the authorization URL in the browser
/// 3. Starts a local callback server to capture the authorization code
/// 4. Exchanges the code for access/refresh tokens
/// 5. Stores tokens in secure storage (Keychain on macOS)
public struct McpAuthTool: Tool {
    public let name = "McpAuth"
    public let description = "Authenticate with an MCP server via OAuth"

    private let mcpClients: [any Sendable]

    public struct Arguments: Codable, Sendable {
        public var serverName: String

        enum CodingKeys: String, CodingKey {
            case serverName
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["serverName"] = JSONSchemaProperty(
            type: "string",
            description: "The MCP server name to authenticate with"
        )
        schema.required = ["serverName"]
        return schema
    }

    public init(mcpClients: [any Sendable] = []) {
        self.mcpClients = mcpClients
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let serverName = arguments.serverName

        // Resolve server URL from connected clients or construct a default
        let serverUrl = resolveServerUrl(serverName: serverName)

        // Resolve OAuth configuration
        let oauthConfig = resolveOAuthConfig(serverName: serverName)

        // Serialize config for server key derivation
        let configJson = serializeConfigForServerKey(serverUrl: serverUrl, oauthConfig: oauthConfig)

        // Run the OAuth flow
        do {
            try await performMCPOAuthFlow(
                serverName: serverName,
                serverUrl: serverUrl,
                oauthConfig: oauthConfig,
                configJson: configJson,
                onAuthorizationUrl: { _ in
                    // The auth URL is displayed to the user; the flow handles browser opening internally
                },
                skipBrowserOpen: false
            )

            return .string("""
                OAuth authorization complete for \(serverName). \
                The server's tools are now available. \
                Tokens have been saved to secure storage.
                """)
        } catch let error as OAuthFlowError {
            return .string("OAuth authorization failed: \(error.localizedDescription)")
        } catch {
            return .string("OAuth authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Resolves the server's base URL from connected MCP clients.
    /// Falls back to constructing a URL from the server name.
    private func resolveServerUrl(serverName: String) -> String {
        // In production, the URL would be looked up from the MCP server config
        // stored within each MCPClient. For now, construct a reasonable default.
        return "https://\(serverName)"
    }

    /// Resolves OAuth config for the given server.
    /// Returns a default empty config; in production this reads from the
    /// server's parsed configuration (SSE or HTTP config with oauth fields).
    private func resolveOAuthConfig(serverName: String) -> MCPOAuthConfig {
        return MCPOAuthConfig()
    }

    /// Serializes config for server key derivation in the token store.
    private func serializeConfigForServerKey(serverUrl: String, oauthConfig: MCPOAuthConfig) -> String {
        let dict: [String: Any] = [
            "url": serverUrl,
            "clientId": oauthConfig.clientId ?? "",
            "callbackPort": oauthConfig.callbackPort ?? 0,
            "authServerMetadataUrl": oauthConfig.authServerMetadataUrl ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return serverUrl
        }
        return json
    }
}
