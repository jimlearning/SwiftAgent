import Foundation
import SwiftAgentCore

// MARK: - Anthropic Provider

/// LLM provider that speaks the native Anthropic Messages API.
///
/// Wraps Core's `LLMClient` configured for `https://api.anthropic.com`.
/// API key is resolved from `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
/// or `~/.claude.json` via Core's `APIKeyResolver`.
public final class AnthropicProvider: LLMProvider, @unchecked Sendable {

    public let providerID = "anthropic"
    public let displayName = "Anthropic Claude"

    private let client: LLMClient

    public private(set) var isConfigured: Bool = false

    // MARK: - Models

    public let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 32_768
        ),
        ModelInfo(
            id: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 32_768
        ),
        ModelInfo(
            id: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            supportsThinking: false,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 16_384
        ),
    ]

    // MARK: - Init

    /// Create a provider with explicit API key.
    public init(apiKey: String) {
        self.client = LLMClient(
            apiKey: apiKey,
            baseURL: "https://api.anthropic.com"
        )
        self.isConfigured = true
    }

    /// Create a provider by resolving the key from all standard sources.
    /// Returns `nil` if no Anthropic API key is found.
    public init?() {
        guard let key = APIKeyResolver().resolve() else {
            return nil
        }
        self.client = LLMClient(
            apiKey: key,
            baseURL: "https://api.anthropic.com"
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
            thinking: thinking,
            enablePromptCaching: true
        )
    }

    public func supports(_ capability: ProviderCapability) -> Bool {
        switch capability {
        case .extendedThinking: return true
        case .vision: return true
        case .promptCaching: return true
        case .streaming: return true
        case .toolUse: return true
        case .computerUse: return true
        }
    }
}
