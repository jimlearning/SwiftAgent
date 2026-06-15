import Foundation
import SwiftAgentCore

/// App-level LLM provider that wraps DeepSeekClient.
/// For Phase 2, this provides a simplified streaming interface
/// without Skills/MCP/tools integration.
@MainActor
public final class AppLLMProvider: ObservableObject {
    private let client: DeepSeekClient

    /// The current configuration (model may change via model picker).
    @Published public private(set) var config: DeepSeekConfig

    /// Whether an API key is configured.
    public var hasAPIKey: Bool {
        !config.apiKey.isEmpty
    }

    public init(config: DeepSeekConfig) {
        self.config = config
        self.client = DeepSeekClient(config: config)
    }

    /// Update the configuration (e.g., when model changes).
    public func updateConfig(_ newConfig: DeepSeekConfig) {
        self.config = newConfig
    }

    /// Stream a response for the given messages.
    /// Returns an AsyncThrowingStream of token strings.
    public func stream(
        messages: [Message],
        model: DeepSeekModel? = nil
    ) -> AsyncThrowingStream<String, Error> {
        client.stream(messages: messages, model: model ?? config.defaultModel)
    }

    /// Stream with reasoning support (for R1 model).
    public func streamWithReasoning(
        messages: [Message],
        model: DeepSeekModel? = nil
    ) -> AsyncThrowingStream<DeepSeekStreamEvent, Error> {
        client.streamWithReasoning(messages: messages, model: model ?? config.defaultModel)
    }
}
