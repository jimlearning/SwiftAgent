import Foundation
import SwiftAgentCore

// MARK: - AppAgentProvider

/// Unified LLM provider that bridges SwiftAgentApp to the Core LLM runtime.
///
/// Manages a `ProviderRegistry` for multi-provider support (Anthropic, DeepSeek,
/// OpenAI) while maintaining backward compatibility with the existing `LLMClient`
/// code path used by `QueryEngine`.
///
/// ## Multi-Provider Architecture
/// - `providerRegistry` discovers and manages all configured providers.
/// - `currentModel` drives automatic provider selection via the registry.
/// - `getClient()` returns the underlying `LLMClient` for the active provider
///   (backward-compatible with existing `AgentSessionManager`).
/// - `getProvider()` returns the typed `LLMProvider` for new code paths.
///
/// API key resolution order:
///   1. `DEEPSEEK_API_KEY` env var → DeepSeek
///   2. macOS Keychain (`KeychainStore`) → DeepSeek
///   3. `ANTHROPIC_API_KEY` env var → Anthropic
///   4. `ANTHROPIC_AUTH_TOKEN` env var → Anthropic
///   5. macOS Keychain ("Claude Code" entry) → Anthropic
///   6. `~/.claude.json` (`primaryApiKey`) → Anthropic
@MainActor
public final class AppAgentProvider: ObservableObject {

    // MARK: - Multi-provider layer

    /// The provider registry — discovers and manages all configured LLM providers.
    public let providerRegistry = ProviderRegistry()

    /// All available models across all configured providers (flat list for UI).
    public var availableModels: [ResolvedModel] {
        providerRegistry.allModels
    }

    // MARK: - Active provider

    /// The underlying LLMClient for the active provider (nil until configured).
    private var client: LLMClient?

    /// The resolved API key (masked for display).
    @Published public private(set) var maskedKey: String = ""

    /// Whether an API key is configured and a client is ready.
    @Published public private(set) var isConfigured: Bool = false

    /// Whether the current key is a DeepSeek key (affects base URL default).
    @Published public private(set) var isDeepSeek: Bool = false

    /// The current model ID (e.g. "claude-sonnet-4-6", "deepseek-v4-pro").
    @Published public var currentModel: String = "deepseek-v4-pro"

    /// The base URL for the active LLMClient.
    public let baseURL: String

    // MARK: - Init

    /// Create a provider by resolving the API key from standard sources.
    /// Does not throw if the key is missing — check `isConfigured` after init.
    public init() {
        if let (key, isDeepSeek) = Self.resolveKey() {
            self.baseURL = Self.resolveBaseURL(isDeepSeek: isDeepSeek)
            self.isDeepSeek = isDeepSeek
            self.client = LLMClient(apiKey: key, baseURL: self.baseURL)
            self.isConfigured = true
            self.maskedKey = maskKey(key)
        } else {
            self.baseURL = Self.resolveBaseURL(isDeepSeek: false)
            self.isDeepSeek = false
        }
    }

    /// Create a provider with an explicit API key.
    public init(apiKey: String, baseURL: String? = nil) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
            ?? "https://api.deepseek.com/anthropic"
        self.isDeepSeek = true

        if !trimmed.isEmpty {
            self.client = LLMClient(apiKey: trimmed, baseURL: self.baseURL)
            self.isConfigured = true
            self.maskedKey = maskKey(trimmed)
        }
    }

    // MARK: - Key resolution

    /// Resolves the API key from all supported sources.
    static func resolveKey() -> (key: String, isDeepSeek: Bool)? {
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            return (envKey, true)
        }
        if let keychainKey = KeychainStore.load(), !keychainKey.isEmpty {
            return (keychainKey, true)
        }
        if let anthropicKey = APIKeyResolver().resolve(), !anthropicKey.isEmpty {
            return (anthropicKey, false)
        }
        return nil
    }

    /// Determines the base URL from an explicit env-var override or the key source.
    static func resolveBaseURL(isDeepSeek: Bool) -> String {
        if let envURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"], !envURL.isEmpty {
            return envURL
        }
        if isDeepSeek {
            return "https://api.deepseek.com/anthropic"
        }
        return "https://api.anthropic.com"
    }

    // MARK: - Client access (Backward Compatible)

    /// Returns the configured LLMClient for the active provider.
    /// Used by `AgentSessionManager` → `QueryEngine`.
    public func getClient() -> LLMClient? {
        client
    }

    /// Returns the typed LLMProvider for the given model ID.
    /// Falls back to the default provider if the model isn't found.
    public func getProvider(for modelID: String? = nil) -> (any LLMProvider)? {
        let id = modelID ?? currentModel
        return providerRegistry.provider(for: id) ?? providerRegistry.defaultProvider
    }

    /// Returns the typed LLMProvider for the currently selected model.
    public func getCurrentProvider() -> (any LLMProvider)? {
        getProvider(for: currentModel)
    }

    // MARK: - Model Switching

    /// Switch the active model and update the underlying client if the provider changed.
    /// - Parameter modelID: The new model ID (e.g. "claude-sonnet-4-6").
    /// - Returns: `true` if the model was found and switched.
    @discardableResult
    public func switchModel(to modelID: String) -> Bool {
        guard let provider = getProvider(for: modelID) else {
            return false
        }
        currentModel = modelID
        // If the provider's underlying client is available, switch to it.
        // For now, the client set at init time is used — provider switching
        // via ProviderRegistry requires per-provider LLMClient instances.
        return true
    }

    // MARK: - Reconfiguration

    /// Re-configure with a new API key.
    public func updateAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            client = nil
            isConfigured = false
            maskedKey = ""
            return
        }
        client = LLMClient(apiKey: trimmed, baseURL: baseURL)
        isConfigured = true
        maskedKey = maskKey(trimmed)
    }

    // MARK: - Helpers

    private func maskKey(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "*", count: min(key.count, 8)) }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}
