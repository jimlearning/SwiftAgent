import Foundation

/// MCP OAuth 2.0 authorization flow orchestrator.
/// Matches Claude Code's performMCPOAuthFlow in services/mcp/auth.ts.
///
/// Implements the complete OAuth 2.0 authorization code + PKCE flow for MCP servers:
/// 1. Discover authorization server metadata (RFC 8414 / RFC 9728)
/// 2. Generate PKCE code verifier and challenge
/// 3. Open browser for user authorization (or manual URL paste)
/// 4. Start local callback server to capture the redirect
/// 5. Exchange authorization code for access/refresh tokens
/// 6. Store tokens in secure storage

// MARK: - OAuth Flow Entry Point

/// Performs the full MCP OAuth 2.0 authorization code + PKCE flow.
///
/// - Parameters:
///   - serverName: MCP server name for credential scoping
///   - serverUrl: The MCP server's base URL
///   - oauthConfig: Per-server OAuth configuration (clientId, callbackPort, etc.)
///   - configJson: Serialized server config JSON for server key derivation
///   - onAuthorizationUrl: Called when the authorization URL is ready (for UI display)
///   - skipBrowserOpen: If true, skips opening the browser (user pastes URL manually)
///   - onWaitingForCallback: Optional — provides a manual submit function for the callback URL
///
/// CC: performMCPOAuthFlow(serverName, serverConfig, onAuthorizationUrl, abortSignal?, options?)
public func performMCPOAuthFlow(
    serverName: String,
    serverUrl: String,
    oauthConfig: MCPOAuthConfig,
    configJson: String,
    onAuthorizationUrl: @escaping (String) -> Void,
    skipBrowserOpen: Bool = false,
    onWaitingForCallback: (@Sendable (_ submit: @escaping @Sendable (String) -> Void) -> Void)? = nil
) async throws {
    let tokenStore = OAuthTokenStore()
    let serverKey = OAuthTokenStore.serverKey(serverName: serverName, configJson: configJson)

    // 1. Clear existing tokens before starting new flow
    try? await tokenStore.clearAllTokens(serverKey: serverKey)

    // 2. Discover authorization server metadata
    let metadata = try await fetchAuthServerMetadata(
        serverUrl: serverUrl,
        directMetadataUrl: oauthConfig.authServerMetadataUrl
    )

    guard let authEndpoint = metadata.authorizationEndpoint else {
        throw OAuthFlowError.tokenExchangeFailed("No authorization endpoint discovered")
    }

    // 3. Generate PKCE parameters
    let codeVerifier = PKCE.generateCodeVerifier()
    let codeChallenge = PKCE.generateCodeChallenge(from: codeVerifier)
    let state = generateOAuthState()

    // 4. Find available redirect port
    let port: UInt16
    if let configuredPort = oauthConfig.callbackPort, configuredPort > 0 {
        port = UInt16(configuredPort)
    } else {
        port = try findAvailablePort()
    }
    let redirectUri = buildRedirectUri(port: port)

    // Get OAuth client ID
    let clientId = oauthConfig.clientId
        ?? ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_CLIENT_ID"]
        ?? getOauthConfig().clientId

    // Get scopes from metadata or defaults
    let scopes: [String]
    if let supported = metadata.scopesSupported, !supported.isEmpty {
        scopes = supported
    } else {
        scopes = ALL_OAUTH_SCOPES
    }

    // 5. Build authorization URL
    var authURLComponents = URLComponents(string: authEndpoint)
    authURLComponents?.queryItems = [
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "client_id", value: clientId),
        URLQueryItem(name: "redirect_uri", value: redirectUri),
        URLQueryItem(name: "code_challenge", value: codeChallenge),
        URLQueryItem(name: "code_challenge_method", value: PKCE.codeChallengeMethod),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
    ]

    guard let authURL = authURLComponents?.url else {
        throw OAuthFlowError.invalidServerUrl(authEndpoint)
    }

    let authURLString = authURL.absoluteString

    // 6. Notify UI of the authorization URL
    onAuthorizationUrl(authURLString)

    // 7. Open browser (unless skipped)
    if !skipBrowserOpen {
        Task { await openBrowser(authURLString) }
    }

    // 8. Start callback server and wait for the authorization code
    let authorizationCode: String
    do {
        authorizationCode = try await OAuthCallbackServer.captureAuthorizationCode(
            port: port,
            expectedState: state,
            timeoutSeconds: 300,
            onWaitingForCallback: onWaitingForCallback
        )
    } catch {
        // Clean up on failure
        try? await tokenStore.clearAllTokens(serverKey: serverKey)
        throw error
    }

    // 9. Exchange authorization code for tokens
    let tokens = try await exchangeCodeForTokens(
        tokenEndpoint: metadata.tokenEndpoint,
        code: authorizationCode,
        codeVerifier: codeVerifier,
        clientId: clientId,
        redirectUri: redirectUri
    )

    // 10. Store tokens
    let tokenData = OAuthTokenData(
        serverName: serverName,
        serverUrl: serverUrl,
        clientId: clientId,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresAt: Date().timeIntervalSince1970 + TimeInterval(tokens.expiresIn),
        scope: tokens.scope,
        discoveryState: DiscoveryState(
            authorizationServerUrl: authEndpoint,
            resourceMetadataUrl: nil
        )
    )
    try await tokenStore.writeTokens(serverKey: serverKey, tokens: tokenData)
}

// MARK: - Token Exchange

/// Token response from the authorization server.
public struct OAuthTokenResponse: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let scope: String?
    public let tokenType: String
}

/// Exchanges an authorization code for tokens at the token endpoint.
/// CC: sdkAuth(provider, { serverUrl, authorizationCode, ... })
public func exchangeCodeForTokens(
    tokenEndpoint: String,
    code: String,
    codeVerifier: String,
    clientId: String,
    redirectUri: String
) async throws -> OAuthTokenResponse {
    guard let url = URL(string: tokenEndpoint) else {
        throw OAuthFlowError.invalidServerUrl(tokenEndpoint)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 30

    var bodyComponents = URLComponents()
    bodyComponents.queryItems = [
        URLQueryItem(name: "grant_type", value: "authorization_code"),
        URLQueryItem(name: "code", value: code),
        URLQueryItem(name: "code_verifier", value: codeVerifier),
        URLQueryItem(name: "client_id", value: clientId),
        URLQueryItem(name: "redirect_uri", value: redirectUri),
    ]
    request.httpBody = bodyComponents.query?.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OAuthFlowError.tokenExchangeFailed("Invalid response")
    }

    // CC: normalizeOAuthErrorBody — handles non-compliant servers
    // that return HTTP 200 with error JSON body
    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = errorJson["error"] as? String {
        if error == "invalid_grant" || error == "invalid_refresh_token"
            || error == "expired_refresh_token" || error == "token_expired" {
            throw OAuthFlowError.tokenExchangeFailed(error)
        }
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw OAuthFlowError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let accessToken = json["access_token"] as? String else {
        throw OAuthFlowError.tokenExchangeFailed("Missing access_token in response")
    }

    return OAuthTokenResponse(
        accessToken: accessToken,
        refreshToken: json["refresh_token"] as? String,
        expiresIn: json["expires_in"] as? Int ?? 3600,
        scope: json["scope"] as? String,
        tokenType: json["token_type"] as? String ?? "Bearer"
    )
}

// MARK: - Token Refresh

/// Refreshes an access token using a refresh token.
/// CC: sdkRefreshAuthorization → _doRefresh in auth.ts
public func refreshAccessToken(
    tokenEndpoint: String,
    refreshToken: String,
    clientId: String,
    scope: String? = nil
) async throws -> OAuthTokenResponse {
    guard let url = URL(string: tokenEndpoint) else {
        throw OAuthFlowError.invalidServerUrl(tokenEndpoint)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 30

    var bodyComponents = URLComponents()
    var queryItems = [
        URLQueryItem(name: "grant_type", value: "refresh_token"),
        URLQueryItem(name: "refresh_token", value: refreshToken),
        URLQueryItem(name: "client_id", value: clientId),
    ]
    if let scope = scope {
        queryItems.append(URLQueryItem(name: "scope", value: scope))
    }
    bodyComponents.queryItems = queryItems
    request.httpBody = bodyComponents.query?.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OAuthFlowError.tokenExchangeFailed("Invalid response")
    }

    // Normalize non-compliant error responses
    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = errorJson["error"] as? String {
        if error != "" {
            throw OAuthFlowError.tokenExchangeFailed(error)
        }
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw OAuthFlowError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let accessToken = json["access_token"] as? String else {
        throw OAuthFlowError.tokenExchangeFailed("Missing access_token in response")
    }

    return OAuthTokenResponse(
        accessToken: accessToken,
        refreshToken: json["refresh_token"] as? String ?? refreshToken, // Rotation support
        expiresIn: json["expires_in"] as? Int ?? 3600,
        scope: json["scope"] as? String ?? scope,
        tokenType: json["token_type"] as? String ?? "Bearer"
    )
}

// MARK: - Token Revocation

/// Revokes OAuth tokens at the authorization server (RFC 7009).
/// CC: revokeServerTokens() in auth.ts
public func revokeServerTokens(
    revocationEndpoint: String,
    accessToken: String,
    refreshToken: String?,
    clientId: String,
    clientSecret: String? = nil
) async throws {
    guard let url = URL(string: revocationEndpoint) else {
        throw OAuthFlowError.invalidServerUrl(revocationEndpoint)
    }

    // Revoke refresh token first (CC pattern)
    if let rt = refreshToken {
        try? await sendRevocationRequest(
            url: url, token: rt, tokenTypeHint: "refresh_token",
            clientId: clientId, clientSecret: clientSecret
        )
    }

    // Then revoke access token
    try? await sendRevocationRequest(
        url: url, token: accessToken, tokenTypeHint: "access_token",
        clientId: clientId, clientSecret: clientSecret
    )
}

private func sendRevocationRequest(
    url: URL,
    token: String,
    tokenTypeHint: String,
    clientId: String,
    clientSecret: String?
) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15

    var bodyComponents = URLComponents()
    bodyComponents.queryItems = [
        URLQueryItem(name: "token", value: token),
        URLQueryItem(name: "token_type_hint", value: tokenTypeHint),
        URLQueryItem(name: "client_id", value: clientId),
    ]
    request.httpBody = bodyComponents.query?.data(using: .utf8)

    // Client secret auth (if available)
    if let secret = clientSecret {
        let credentials = "\(clientId):\(secret)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    let (_, response) = try await URLSession.shared.data(for: request)

    // CC: Fallback for non-compliant servers — retry with Bearer auth on 401
    if let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 401 {
        var retryRequest = request
        retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let _ = try? await URLSession.shared.data(for: retryRequest)
    }
}
