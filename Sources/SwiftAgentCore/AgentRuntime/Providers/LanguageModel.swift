import Foundation

// MARK: - LanguageModelCapabilities

/// Single struct describing model capabilities. Replaces dual ModelInfo types.
/// Mirrors Apple's FoundationModels `LanguageModelCapabilities`.
public struct LanguageModelCapabilities: Sendable, Equatable {
    /// Whether the model supports streaming responses.
    public var supportsStreaming: Bool

    /// Whether the model supports tool/function calling.
    public var supportsToolUse: Bool

    /// Whether the model supports extended thinking/reasoning.
    public var supportsThinking: Bool

    /// Whether the model supports vision/image inputs.
    public var supportsVision: Bool

    /// Maximum context window size in tokens.
    public var contextWindow: Int

    /// Maximum output tokens per response.
    public var maxOutputTokens: Int

    /// Human-readable provider name for UI display.
    public var providerDisplayName: String

    public init(
        supportsStreaming: Bool = true,
        supportsToolUse: Bool = true,
        supportsThinking: Bool = false,
        supportsVision: Bool = false,
        contextWindow: Int = 200_000,
        maxOutputTokens: Int = 8_192,
        providerDisplayName: String
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolUse = supportsToolUse
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.providerDisplayName = providerDisplayName
    }
}
