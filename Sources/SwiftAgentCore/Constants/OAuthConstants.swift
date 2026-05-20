import Foundation

/// OAuth configuration and constants matching Claude Code's constants/oauth.ts.
/// Provides environment-aware OAuth endpoint selection (prod/staging/local),
/// custom OAuth URL support, and MCP OAuth scope definitions.

// MARK: - Scopes

/// CC: CLAUDE_AI_INFERENCE_SCOPE = 'user:inference'
public let CLAUDE_AI_INFERENCE_SCOPE = "user:inference"

/// CC: CLAUDE_AI_PROFILE_SCOPE = 'user:profile'
public let CLAUDE_AI_PROFILE_SCOPE = "user:profile"

/// CC: CONSOLE_SCOPE = 'org:create_api_key' (not exported in CC)
private let consoleScope = "org:create_api_key"

/// CC: CONSOLE_OAUTH_SCOPES = ['org:create_api_key', 'user:profile']
public let CONSOLE_OAUTH_SCOPES: [String] = [consoleScope, CLAUDE_AI_PROFILE_SCOPE]

/// CC: CLAUDE_AI_OAUTH_SCOPES = ['user:profile', 'user:inference', 'user:sessions:claude_code', 'user:mcp_servers', 'user:file_upload']
public let CLAUDE_AI_OAUTH_SCOPES: [String] = [
    CLAUDE_AI_PROFILE_SCOPE,
    CLAUDE_AI_INFERENCE_SCOPE,
    "user:sessions:claude_code",
    "user:mcp_servers",
    "user:file_upload",
]

/// CC: ALL_OAUTH_SCOPES — deduplicated union of CONSOLE + CLAUDE_AI scopes
public let ALL_OAUTH_SCOPES: [String] = Array(Set(CONSOLE_OAUTH_SCOPES + CLAUDE_AI_OAUTH_SCOPES))

// MARK: - Beta Header

/// CC: OAUTH_BETA_HEADER = 'oauth-2025-04-20'
public let OAUTH_BETA_HEADER = "oauth-2025-04-20"

// MARK: - MCP Client Metadata URL (SEP-991 / CIMD)

/// CC: MCP_CLIENT_METADATA_URL = 'https://claude.ai/oauth/claude-code-client-metadata'
public let MCP_CLIENT_METADATA_URL = "https://claude.ai/oauth/claude-code-client-metadata"

// MARK: - OAuth Config Type

/// CC: OauthConfigType = 'prod' | 'staging' | 'local'
public enum OAuthConfigType: String {
    case prod
    case staging
    case local
}

// MARK: - OAuth Configuration Struct

/// CC: OauthConfig type — all URL fields required.
public struct OAuthConfig: Sendable {
    public let baseApiUrl: String
    public let consoleAuthorizeUrl: String
    public let claudeAIAuthorizeUrl: String
    public let claudeAIOrigin: String
    public let tokenUrl: String
    public let apiKeyUrl: String
    public let rolesUrl: String
    public let consoleSuccessUrl: String
    public let claudeAISuccessUrl: String
    public let manualRedirectUrl: String
    public let clientId: String
    public let oauthFileSuffix: String
    public let mcpProxyUrl: String
    public let mcpProxyPath: String
}

// MARK: - Production Config

/// CC: PROD_OAUTH_CONFIG (as const)
public let PROD_OAUTH_CONFIG = OAuthConfig(
    baseApiUrl: "https://api.anthropic.com",
    consoleAuthorizeUrl: "https://platform.claude.com/oauth/authorize",
    claudeAIAuthorizeUrl: "https://claude.com/cai/oauth/authorize",
    claudeAIOrigin: "https://claude.ai",
    tokenUrl: "https://platform.claude.com/v1/oauth/token",
    apiKeyUrl: "https://api.anthropic.com/api/oauth/claude_cli/create_api_key",
    rolesUrl: "https://api.anthropic.com/api/oauth/claude_cli/roles",
    consoleSuccessUrl: "https://platform.claude.com/buy_credits?returnUrl=/oauth/code/success%3Fapp%3Dclaude-code",
    claudeAISuccessUrl: "https://platform.claude.com/oauth/code/success?app=claude-code",
    manualRedirectUrl: "https://platform.claude.com/oauth/code/callback",
    clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    oauthFileSuffix: "",
    mcpProxyUrl: "https://mcp-proxy.anthropic.com",
    mcpProxyPath: "/v1/mcp/{server_id}"
)

// MARK: - Staging Config

/// CC: STAGING_OAUTH_CONFIG — only defined when USER_TYPE == 'ant'
public let STAGING_OAUTH_CONFIG: OAuthConfig? = {
    guard ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" else { return nil }
    return OAuthConfig(
        baseApiUrl: "https://api-staging.anthropic.com",
        consoleAuthorizeUrl: "https://platform.staging.ant.dev/oauth/authorize",
        claudeAIAuthorizeUrl: "https://claude-ai.staging.ant.dev/oauth/authorize",
        claudeAIOrigin: "https://claude-ai.staging.ant.dev",
        tokenUrl: "https://platform.staging.ant.dev/v1/oauth/token",
        apiKeyUrl: "https://api-staging.anthropic.com/api/oauth/claude_cli/create_api_key",
        rolesUrl: "https://api-staging.anthropic.com/api/oauth/claude_cli/roles",
        consoleSuccessUrl: "https://platform.staging.ant.dev/buy_credits?returnUrl=/oauth/code/success%3Fapp%3Dclaude-code",
        claudeAISuccessUrl: "https://platform.staging.ant.dev/oauth/code/success?app=claude-code",
        manualRedirectUrl: "https://platform.staging.ant.dev/oauth/code/callback",
        clientId: "22422756-60c9-4084-8eb7-27705fd5cf9a",
        oauthFileSuffix: "-staging-oauth",
        mcpProxyUrl: "https://mcp-proxy-staging.anthropic.com",
        mcpProxyPath: "/v1/mcp/{server_id}"
    )
}()

// MARK: - Allowed Custom OAuth Base URLs

/// CC: ALLOWED_OAUTH_BASE_URLS — only FedStart/PubSec deployments
private let ALLOWED_OAUTH_BASE_URLS: Set<String> = [
    "https://beacon.claude-ai.staging.ant.dev",
    "https://claude.fedstart.com",
    "https://claude-staging.fedstart.com",
]

// MARK: - Config Resolution Helpers

/// CC: isEnvTruthy() — matches FeatureFlags.isEnvTruthy() in SA.
private func envTruthy(_ key: String) -> Bool {
    guard let v = ProcessInfo.processInfo.environment[key] else { return false }
    let lower = v.lowercased()
    return lower == "1" || lower == "true" || lower == "yes" || lower == "on"
}

/// CC: getOauthConfigType()
private func getOauthConfigType() -> OAuthConfigType {
    if ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" {
        if envTruthy("USE_LOCAL_OAUTH") { return .local }
        if envTruthy("USE_STAGING_OAUTH") { return .staging }
    }
    return .prod
}

/// CC: fileSuffixForOauthConfig()
public func fileSuffixForOauthConfig() -> String {
    if ProcessInfo.processInfo.environment["CLAUDE_CODE_CUSTOM_OAUTH_URL"]?.isEmpty == false {
        return "-custom-oauth"
    }
    switch getOauthConfigType() {
    case .local: return "-local-oauth"
    case .staging: return "-staging-oauth"
    case .prod: return ""
    }
}

/// CC: getLocalOauthConfig()
private func getLocalOauthConfig() -> OAuthConfig {
    let api = (ProcessInfo.processInfo.environment["CLAUDE_LOCAL_OAUTH_API_BASE"] ?? "http://localhost:8000")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let apps = (ProcessInfo.processInfo.environment["CLAUDE_LOCAL_OAUTH_APPS_BASE"] ?? "http://localhost:4000")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let consoleBase = (ProcessInfo.processInfo.environment["CLAUDE_LOCAL_OAUTH_CONSOLE_BASE"] ?? "http://localhost:3000")
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    return OAuthConfig(
        baseApiUrl: api,
        consoleAuthorizeUrl: "\(consoleBase)/oauth/authorize",
        claudeAIAuthorizeUrl: "\(apps)/oauth/authorize",
        claudeAIOrigin: apps,
        tokenUrl: "\(api)/v1/oauth/token",
        apiKeyUrl: "\(api)/api/oauth/claude_cli/create_api_key",
        rolesUrl: "\(api)/api/oauth/claude_cli/roles",
        consoleSuccessUrl: "\(consoleBase)/buy_credits?returnUrl=/oauth/code/success%3Fapp%3Dclaude-code",
        claudeAISuccessUrl: "\(consoleBase)/oauth/code/success?app=claude-code",
        manualRedirectUrl: "\(consoleBase)/oauth/code/callback",
        clientId: "22422756-60c9-4084-8eb7-27705fd5cf9a",
        oauthFileSuffix: "-local-oauth",
        mcpProxyUrl: "http://localhost:8205",
        mcpProxyPath: "/v1/toolbox/shttp/mcp/{server_id}"
    )
}

// MARK: - Main Config Accessor

/// CC: getOauthConfig() — returns the active OAuth config, with optional
/// custom-OAuth URL and client ID overrides.
public func getOauthConfig() -> OAuthConfig {
    let configType = getOauthConfigType()

    var config: OAuthConfig
    switch configType {
    case .local:
        config = getLocalOauthConfig()
    case .staging:
        config = STAGING_OAUTH_CONFIG ?? PROD_OAUTH_CONFIG
    case .prod:
        config = PROD_OAUTH_CONFIG
    }

    // Custom OAuth URL override (FedStart/PubSec only)
    if let customUrl = ProcessInfo.processInfo.environment["CLAUDE_CODE_CUSTOM_OAUTH_URL"], !customUrl.isEmpty {
        guard ALLOWED_OAUTH_BASE_URLS.contains(customUrl) else {
            // In CC this throws. Here we log and fall through to default config.
            print("[OAuth] WARNING: CLAUDE_CODE_CUSTOM_OAUTH_URL is not an approved endpoint.")
            return config
        }
        let base = customUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        config = OAuthConfig(
            baseApiUrl: base,
            consoleAuthorizeUrl: "\(base)/oauth/authorize",
            claudeAIAuthorizeUrl: "\(base)/oauth/authorize",
            claudeAIOrigin: base,
            tokenUrl: "\(base)/v1/oauth/token",
            apiKeyUrl: "\(base)/api/oauth/claude_cli/create_api_key",
            rolesUrl: "\(base)/api/oauth/claude_cli/roles",
            consoleSuccessUrl: "\(base)/buy_credits?returnUrl=/oauth/code/success%3Fapp%3Dclaude-code",
            claudeAISuccessUrl: "\(base)/oauth/code/success?app=claude-code",
            manualRedirectUrl: "\(base)/oauth/code/callback",
            clientId: config.clientId,
            oauthFileSuffix: "-custom-oauth",
            mcpProxyUrl: config.mcpProxyUrl,
            mcpProxyPath: config.mcpProxyPath
        )
    }

    // Client ID override
    if let clientIdOverride = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_CLIENT_ID"], !clientIdOverride.isEmpty {
        config = OAuthConfig(
            baseApiUrl: config.baseApiUrl,
            consoleAuthorizeUrl: config.consoleAuthorizeUrl,
            claudeAIAuthorizeUrl: config.claudeAIAuthorizeUrl,
            claudeAIOrigin: config.claudeAIOrigin,
            tokenUrl: config.tokenUrl,
            apiKeyUrl: config.apiKeyUrl,
            rolesUrl: config.rolesUrl,
            consoleSuccessUrl: config.consoleSuccessUrl,
            claudeAISuccessUrl: config.claudeAISuccessUrl,
            manualRedirectUrl: config.manualRedirectUrl,
            clientId: clientIdOverride,
            oauthFileSuffix: config.oauthFileSuffix,
            mcpProxyUrl: config.mcpProxyUrl,
            mcpProxyPath: config.mcpProxyPath
        )
    }

    return config
}
