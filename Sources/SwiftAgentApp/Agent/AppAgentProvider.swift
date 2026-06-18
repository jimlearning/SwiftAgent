import Foundation
import SwiftAgentCore

// MARK: - AppAgentProvider

/// Unified LLM provider that wraps `SwiftAgentCore.LLMClient` (Anthropic Messages API).
///
/// Replaces the old `AppLLMProvider` + `DeepSeekClient` with the full-featured
/// Core LLM client — supporting tool definitions, thinking, prompt caching,
/// retry with fallback models, and beta features.
///
/// API key resolution order:
///   1. `DEEPSEEK_API_KEY` env var → DeepSeek
///   2. macOS Keychain (`KeychainStore`, written by Settings → General) → DeepSeek
///   3. `ANTHROPIC_API_KEY` env var → Anthropic
///   4. `ANTHROPIC_AUTH_TOKEN` env var → Anthropic
///   5. macOS Keychain ("Claude Code" entry) → Anthropic
///   6. `~/.claude.json` (`primaryApiKey`) → Anthropic
///
/// The base URL defaults to `https://api.deepseek.com/anthropic` for DeepSeek keys,
/// or `ANTHROPIC_BASE_URL` / `https://api.anthropic.com` for Anthropic keys.
@MainActor
public final class AppAgentProvider: ObservableObject {
    /// The underlying Anthropic Messages API client (nil until configured).
    private var client: LLMClient?

    /// The resolved API key (masked for display).
    @Published public private(set) var maskedKey: String = ""

    /// Whether an API key is configured and the client is ready.
    @Published public private(set) var isConfigured: Bool = false

    /// Whether the current key is a DeepSeek key (affects base URL default).
    @Published public private(set) var isDeepSeek: Bool = false

    /// The current model ID (e.g. "claude-sonnet-4-6", "deepseek-v4-pro").
    @Published public var currentModel: String = "deepseek-v4-pro"

    /// The base URL for the Anthropic-compatible API.
    public let baseURL: String

    // MARK: - Init

    /// Create a provider by resolving the API key from standard sources.
    /// Does not throw if the key is missing — check `isConfigured` after init.
    public init() {
        // Resolve the API key first (single Keychain access).
        // Base URL is derived from the key source to avoid reading
        // Keychain again inside resolveBaseURL().
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
        self.isDeepSeek = true  // Explicit key → assume DeepSeek (matches old behavior)

        if !trimmed.isEmpty {
            self.client = LLMClient(apiKey: trimmed, baseURL: self.baseURL)
            self.isConfigured = true
            self.maskedKey = maskKey(trimmed)
        }
    }

    // MARK: - Key resolution

    /// Resolves the API key from all supported sources.
    /// Returns `(key, isDeepSeek)` — `isDeepSeek = true` when the key came from
    /// DeepSeek-specific sources (`DEEPSEEK_API_KEY` or `KeychainStore`).
    static func resolveKey() -> (key: String, isDeepSeek: Bool)? {
        // 1. DeepSeek API key env var
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            return (envKey, true)
        }

        // 2. Keychain (stored by Settings → General "Save" button via KeychainStore)
        if let keychainKey = KeychainStore.load(), !keychainKey.isEmpty {
            return (keychainKey, true)
        }

        // 3–6. Anthropic sources via Core's APIKeyResolver
        if let anthropicKey = APIKeyResolver().resolve(), !anthropicKey.isEmpty {
            return (anthropicKey, false)
        }

        return nil
    }

    /// Determines the base URL from an explicit env-var override or the key source.
    /// `isDeepSeek` should come from `resolveKey()` — true when the key was resolved
    /// from DEEPSEEK_API_KEY or KeychainStore, false for Anthropic sources.
    static func resolveBaseURL(isDeepSeek: Bool) -> String {
        // Explicit override always wins
        if let envURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"], !envURL.isEmpty {
            return envURL
        }

        if isDeepSeek {
            return "https://api.deepseek.com/anthropic"
        }

        return "https://api.anthropic.com"
    }

    // MARK: - Client access

    /// Returns the configured LLMClient (nil if not configured).
    public func getClient() -> LLMClient? {
        client
    }

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
