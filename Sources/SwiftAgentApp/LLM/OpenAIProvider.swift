import Foundation
import SwiftAgentCore

// MARK: - OpenAI Provider

/// LLM provider for the OpenAI Chat Completions API.
///
/// - Note: This is a stub implementation. The OpenAI API uses a different
///   wire format than Anthropic Messages. A full implementation would need
///   an SSE parser that converts OpenAI's `chat.completion.chunk` events
///   into Core's `StreamEvent` format.
public final class OpenAIProvider: LLMProvider, @unchecked Sendable {

    public let providerID = "openai"
    public let displayName = "OpenAI"

    private let apiKey: String

    public private(set) var isConfigured: Bool = false

    // MARK: - Models

    public let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 256_000,
            maxOutputTokens: 32_768
        ),
        ModelInfo(
            id: "gpt-5.2-mini",
            displayName: "GPT-5.2 Mini",
            supportsThinking: false,
            supportsVision: true,
            contextWindow: 256_000,
            maxOutputTokens: 16_384
        ),
        ModelInfo(
            id: "o4",
            displayName: "o4 (Reasoning)",
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 100_000
        ),
    ]

    // MARK: - Init

    /// Create a provider with explicit API key.
    public init(apiKey: String) {
        self.apiKey = apiKey
        self.isConfigured = true
    }

    /// Create a provider by resolving `OPENAI_API_KEY` from the environment.
    /// Returns `nil` if no key is found.
    public init?() {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            return nil
        }
        self.apiKey = key
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
        // TODO: Implement OpenAI Chat Completions SSE → StreamEvent conversion.
        // The OpenAI streaming format differs from Anthropic's:
        // - Events are `data: {"choices": [{"delta": {"content": "..."}}]}`
        // - Tool calls come as `delta.tool_calls` chunks
        // - No direct equivalent of thinking blocks (o-series uses `reasoning_tokens`)
        //
        // For now, return an error stream.
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: OpenAIError.notImplemented
            )
        }
    }

    public func supports(_ capability: ProviderCapability) -> Bool {
        switch capability {
        case .extendedThinking: return true
        case .vision: return true
        case .promptCaching: return false
        case .streaming: return true
        case .toolUse: return true
        case .computerUse: return false
        }
    }
}

// MARK: - OpenAI Errors

enum OpenAIError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "OpenAI provider is not yet implemented. Use Anthropic or DeepSeek."
        }
    }
}
