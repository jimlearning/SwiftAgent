import Foundation

/// Anthropic Messages API provider implementing the LanguageModel + LanguageModelExecutor
/// contract. Both model metadata and inference live in one Sendable struct.
///
/// This is the post-migration provider. The legacy LLMClient/LLMProvider path is
/// deprecated and will be removed in Phase 4.
public struct AnthropicProvider: LanguageModel, LanguageModelExecutor, Sendable {

    // MARK: - Stored Properties

    public let capabilities: LanguageModelCapabilities
    public let displayName: String
    private let apiKey: String
    private let baseURL: URL
    private let modelID: String
    private let session: URLSession

    // MARK: - Model Capability Lookup

    private static let modelCapabilities: [String: LanguageModelCapabilities] = [
        "claude-sonnet-4-6": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 8_192,
            providerDisplayName: "Claude Sonnet 4"
        ),
        "claude-opus-4-6": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 32_768,
            providerDisplayName: "Claude Opus 4"
        ),
        "claude-haiku-4-6": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: false,
            supportsVision: true,
            contextWindow: 200_000,
            maxOutputTokens: 4_096,
            providerDisplayName: "Claude Haiku 4"
        ),
    ]

    // MARK: - Initialization

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        modelID: String,
        displayName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelID = modelID

        let caps = Self.modelCapabilities[modelID]
            ?? LanguageModelCapabilities(providerDisplayName: modelID)
        self.capabilities = LanguageModelCapabilities(
            supportsStreaming: caps.supportsStreaming,
            supportsToolUse: caps.supportsToolUse,
            supportsThinking: caps.supportsThinking,
            supportsVision: caps.supportsVision,
            contextWindow: caps.contextWindow,
            maxOutputTokens: caps.maxOutputTokens,
            providerDisplayName: caps.providerDisplayName
        )
        self.displayName = displayName ?? modelID

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - LanguageModel Conformance

    public func makeExecutor() -> any LanguageModelExecutor { self }

    // MARK: - LanguageModelExecutor Conformance

    public var model: any LanguageModel { self }

    public func respond(
        to transcript: Transcript,
        tools: [RuntimeToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws {
        // Stub — wired in Task 2
        await channel.fail(with: .invalidResponse(reason: "Not yet implemented"))
    }
}
