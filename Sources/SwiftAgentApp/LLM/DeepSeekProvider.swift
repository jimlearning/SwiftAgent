import Foundation
import SwiftAgentCore

// MARK: - DeepSeek Provider

/// LLM provider that speaks DeepSeek's Anthropic-compatible Messages API.
///
/// Wraps Core's `LLMClient` configured for `https://api.deepseek.com/anthropic`.
/// DeepSeek supports the Anthropic Messages wire format, so we reuse the same
/// `LLMClient` with a different base URL.
///
/// API key is resolved from `DEEPSEEK_API_KEY` env var or macOS Keychain.
public final class DeepSeekProvider: LLMProvider, @unchecked Sendable {

    public let providerID = "deepseek"
    public let displayName = "DeepSeek"

    private let client: LLMClient

    public private(set) var isConfigured: Bool = false

    // MARK: - Models

    public let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 128_000,
            maxOutputTokens: 32_768
        ),
        ModelInfo(
            id: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 128_000,
            maxOutputTokens: 16_384
        ),
        ModelInfo(
            id: "deepseek-r1",
            displayName: "DeepSeek R1 (Reasoning)",
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 128_000,
            maxOutputTokens: 32_768
        ),
    ]

    // MARK: - Init

    /// Create a provider with explicit API key.
    public init(apiKey: String) {
        self.client = LLMClient(
            apiKey: apiKey,
            baseURL: "https://api.deepseek.com/anthropic"
        )
        self.isConfigured = true
    }

    /// Create a provider by resolving the key from standard sources.
    /// Returns `nil` if no DeepSeek API key is found.
    public init?() {
        let key: String
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            key = envKey
        } else if let keychainKey = KeychainStore.load(), !keychainKey.isEmpty {
            key = keychainKey
        } else {
            return nil
        }
        self.client = LLMClient(
            apiKey: key,
            baseURL: "https://api.deepseek.com/anthropic"
        )
        self.isConfigured = true
    }

    // MARK: - LLMProvider

    public func stream(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ToolDefinition]?,
        thinking: ThinkingConfig?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        client.send(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            tools: tools,
            thinking: thinking
        )
    }

    public func supports(_ capability: ProviderCapability) -> Bool {
        switch capability {
        case .extendedThinking: return true
        case .vision: return false
        case .promptCaching: return false
        case .streaming: return true
        case .toolUse: return true
        case .computerUse: return false
        }
    }
}
