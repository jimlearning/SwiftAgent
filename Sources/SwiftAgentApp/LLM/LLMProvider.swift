import Foundation
import SwiftAgentCore

// MARK: - LLM Provider Protocol

/// A streaming LLM provider that produces `StreamEvent` values.
///
/// Each provider encapsulates a specific API (Anthropic Messages, OpenAI Chat
/// Completions, DeepSeek, local inference server, etc.) and exposes a uniform
/// streaming interface so the agent runtime can be provider-agnostic.
public protocol LLMProvider: Sendable {

    /// A stable identifier for this provider (e.g. `"anthropic"`, `"openai"`, `"deepseek"`).
    var providerID: String { get }

    /// A human-readable display name (e.g. `"Anthropic Claude"`, `"DeepSeek"`).
    var displayName: String { get }

    /// Models supported by this provider, in preference order.
    var availableModels: [ModelInfo] { get }

    /// Whether this provider is currently configured (has valid credentials).
    var isConfigured: Bool { get }

    /// Stream a conversation completion.
    ///
    /// - Parameters:
    ///   - messages: The conversation history (Core `Message` type).
    ///   - model: The model ID to use (must be in `availableModels`).
    ///   - systemPrompt: Optional system prompt override.
    ///   - maxTokens: Maximum output tokens.
    ///   - tools: Tool definitions for function calling.
    ///   - thinking: Thinking/reasoning configuration.
    /// - Returns: An `AsyncThrowingStream` of `StreamEvent` values.
    func stream(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ToolDefinition]?,
        thinking: ThinkingConfig?
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Synchronous capabilities check — does this provider support a given feature?
    func supports(_ capability: ProviderCapability) -> Bool
}

// MARK: - Model Info

/// Metadata about a model available through a provider.
public struct ModelInfo: Identifiable, Sendable, Equatable {
    /// The model ID to pass to the API (e.g. `"claude-sonnet-4-6"`, `"gpt-5.2"`).
    public let id: String
    /// Human-readable display name (e.g. `"Claude Sonnet 4.6"`).
    public let displayName: String
    /// Whether this model supports extended thinking.
    public let supportsThinking: Bool
    /// Whether this model supports vision (image inputs).
    public let supportsVision: Bool
    /// Maximum context window in tokens.
    public let contextWindow: Int
    /// Maximum output tokens.
    public let maxOutputTokens: Int

    public init(
        id: String,
        displayName: String,
        supportsThinking: Bool = false,
        supportsVision: Bool = true,
        contextWindow: Int = 200_000,
        maxOutputTokens: Int = 32_768
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}

// MARK: - Provider Capability

/// Features a provider may or may not support.
public enum ProviderCapability: Sendable, Equatable {
    /// Extended thinking / reasoning.
    case extendedThinking
    /// Vision (image inputs).
    case vision
    /// Prompt caching for reduced cost on repeated prefixes.
    case promptCaching
    /// Computer use (screenshot + action loop).
    case computerUse
    /// Streaming via SSE.
    case streaming
    /// Tool use / function calling.
    case toolUse
}

// MARK: - Default LLMProvider Extensions

extension LLMProvider {
    public func supports(_ capability: ProviderCapability) -> Bool {
        switch capability {
        case .streaming, .toolUse:
            return true
        default:
            return false
        }
    }
}
