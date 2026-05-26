import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// PKCE (Proof Key for Code Exchange) utilities for OAuth 2.0 authorization code flow.
/// Matches Claude Code's PKCE implementation in services/mcp/auth.ts.
///
/// RFC 7636: generates cryptographically random code_verifier (43-128 chars)
/// and SHA-256 code_challenge for the S256 method.

public enum PKCE {

    /// The code challenge method — always S256 matching CC.
    public static let codeChallengeMethod = "S256"

    /// Generates a cryptographically random code verifier.
    /// CC: randomBytes(32).toString('base64url')
    /// Returns a base64url-encoded string of 32 random bytes.
    public static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Generates the S256 code challenge from a verifier.
    /// CC: createHash('sha256').update(verifier).digest('base64url')
    public static func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else {
            return verifier
        }
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
        #else
        // Fallback: return the verifier as-is (non-cryptographic)
        return verifier
        #endif
    }
}

// MARK: - CSRF State

/// OAuth state parameter generation for CSRF protection.
/// CC: randomBytes(32).toString('base64url')
public func generateOAuthState() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64URLEncodedString()
}

// MARK: - Base64URL Encoding

extension Data {
    /// Base64URL encoding (RFC 4648 Section 5) — URL-safe base64 without padding.
    func base64URLEncodedString() -> String {
        var base64 = self.base64EncodedString()
        base64 = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return base64
    }
}

// MARK: - OAuth Metadata Discovery

/// Result of OAuth authorization server metadata discovery.
public struct OAuthServerMetadata: Sendable {
    public let issuer: String?
    public let authorizationEndpoint: String?
    public let tokenEndpoint: String
    public let registrationEndpoint: String?
    public let revocationEndpoint: String?
    public let scopesSupported: [String]?
    public let responseTypesSupported: [String]?
    public let grantTypesSupported: [String]?
    public let tokenEndpointAuthMethodsSupported: [String]?
    public let codeChallengeMethodsSupported: [String]?

    public init(
        issuer: String? = nil,
        authorizationEndpoint: String? = nil,
        tokenEndpoint: String,
        registrationEndpoint: String? = nil,
        revocationEndpoint: String? = nil,
        scopesSupported: [String]? = nil,
        responseTypesSupported: [String]? = nil,
        grantTypesSupported: [String]? = nil,
        tokenEndpointAuthMethodsSupported: [String]? = nil,
        codeChallengeMethodsSupported: [String]? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.scopesSupported = scopesSupported
        self.responseTypesSupported = responseTypesSupported
        self.grantTypesSupported = grantTypesSupported
        self.tokenEndpointAuthMethodsSupported = tokenEndpointAuthMethodsSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
    }
}

// MARK: - RFC 8414 / RFC 9728 Discovery

/// Discovers OAuth authorization server metadata.
///
/// Algorithm (matching CC's fetchAuthServerMetadata):
/// 1. If a direct metadata URL is provided (oauth.authServerMetadataUrl), fetch it.
/// 2. Otherwise, try RFC 9728 Protected Resource Metadata (/.well-known/oauth-protected-resource)
///    to discover the authorization server URL, then its metadata.
/// 3. Fall back to RFC 8414 server metadata (/.well-known/oauth-authorization-server).
public func fetchAuthServerMetadata(
    serverUrl: String,
    directMetadataUrl: String? = nil
) async throws -> OAuthServerMetadata {
    // Path 1: Direct metadata URL
    if let directUrl = directMetadataUrl {
        guard let url = URL(string: directUrl), url.scheme == "https" else {
            throw OAuthFlowError.invalidAuthServerMetadataUrl(directUrl)
        }
        return try await fetchMetadata(from: url)
    }

    guard let baseURL = URL(string: serverUrl) else {
        throw OAuthFlowError.invalidServerUrl(serverUrl)
    }

    // Path 2: RFC 9728 Protected Resource Metadata
    let prmURL = baseURL.appendingPathComponent(".well-known/oauth-protected-resource")
    if let prmData = try? await fetchJSON(from: prmURL),
       let asUrl = prmData["authorization_servers"] as? [String],
       let firstAS = asUrl.first,
       let asURL = URL(string: firstAS) {
        let metaURL = asURL.appendingPathComponent(".well-known/oauth-authorization-server")
        return try await fetchMetadata(from: metaURL)
    }

    // Path 3: RFC 8414 fallback (path-aware)
    let authServerURL = baseURL.appendingPathComponent(".well-known/oauth-authorization-server")
    return try await fetchMetadata(from: authServerURL)
}

/// Fetches and parses RFC 8414 authorization server metadata from a URL.
private func fetchMetadata(from url: URL) async throws -> OAuthServerMetadata {
    let json = try await fetchJSON(from: url)

    guard let tokenEndpoint = json["token_endpoint"] as? String else {
        throw OAuthFlowError.missingTokenEndpoint
    }

    return OAuthServerMetadata(
        issuer: json["issuer"] as? String,
        authorizationEndpoint: json["authorization_endpoint"] as? String,
        tokenEndpoint: tokenEndpoint,
        registrationEndpoint: json["registration_endpoint"] as? String,
        revocationEndpoint: json["revocation_endpoint"] as? String,
        scopesSupported: json["scopes_supported"] as? [String],
        responseTypesSupported: json["response_types_supported"] as? [String],
        grantTypesSupported: json["grant_types_supported"] as? [String],
        tokenEndpointAuthMethodsSupported: json["token_endpoint_auth_methods_supported"] as? [String],
        codeChallengeMethodsSupported: json["code_challenge_methods_supported"] as? [String]
    )
}

/// Fetches JSON from a URL and returns it as a dictionary.
private func fetchJSON(from url: URL) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw OAuthFlowError.httpError(status)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw OAuthFlowError.invalidMetadataResponse
    }

    return json
}

// MARK: - OAuth Flow Errors

public enum OAuthFlowError: Error, LocalizedError {
    case invalidServerUrl(String)
    case invalidAuthServerMetadataUrl(String)
    case missingTokenEndpoint
    case invalidMetadataResponse
    case httpError(Int)
    case tokenExchangeFailed(String)
    case noAuthorizationCode
    case stateMismatch
    case portUnavailable
    case timeout
    case userCancelled
    case providerDenied

    public var errorDescription: String? {
        switch self {
        case .invalidServerUrl(let url):
            return "Invalid MCP server URL: \(url)"
        case .invalidAuthServerMetadataUrl(let url):
            return "authServerMetadataUrl must use HTTPS: \(url)"
        case .missingTokenEndpoint:
            return "Authorization server metadata missing token_endpoint"
        case .invalidMetadataResponse:
            return "Invalid authorization server metadata response"
        case .httpError(let code):
            return "HTTP \(code) from authorization server"
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        case .noAuthorizationCode:
            return "No authorization code received"
        case .stateMismatch:
            return "OAuth state parameter mismatch (CSRF protection)"
        case .portUnavailable:
            return "No available ports for OAuth redirect"
        case .timeout:
            return "OAuth authorization timed out"
        case .userCancelled:
            return "OAuth authorization cancelled"
        case .providerDenied:
            return "Authorization provider denied the request"
        }
    }
}
