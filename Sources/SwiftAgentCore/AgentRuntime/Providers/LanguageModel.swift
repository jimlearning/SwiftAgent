import Foundation

// MARK: - LanguageModelCapabilities

/// Capabilities a language model provides. Aligned with Apple's
/// `LanguageModelCapabilities` struct (FoundationModels, iOS 27+).
///
/// Apple uses an OptionSet-like pattern with `init(_: [Capability])` and
/// `contains(_:) -> Bool`. We use typed Bool properties for simplicity while
/// providing the same inspection surface.
public struct LanguageModelCapabilities: Sendable, Equatable {
    /// Whether the model supports tool/function calling.
    /// Maps to Apple's `.toolCalling` capability.
    public var supportsToolUse: Bool

    /// Whether the model supports guided generation / structured output.
    /// Maps to Apple's `.guidedGeneration` capability.
    public var supportsGuidedGeneration: Bool

    /// Whether the model supports extended thinking/reasoning.
    /// Maps to Apple's `.reasoning` capability.
    public var supportsReasoning: Bool

    /// Whether the model supports streaming responses.
    public var supportsStreaming: Bool

    /// Whether the model supports vision/image inputs.
    public var supportsVision: Bool

    /// Maximum context window size in tokens.
    public var contextWindow: Int

    /// Maximum output tokens per response.
    public var maximumResponseTokens: Int

    /// Human-readable provider name for UI display.
    public var providerDisplayName: String

    public init(
        supportsToolUse: Bool = true,
        supportsGuidedGeneration: Bool = false,
        supportsReasoning: Bool = false,
        supportsStreaming: Bool = true,
        supportsVision: Bool = false,
        contextWindow: Int = 200_000,
        maximumResponseTokens: Int = 8_192,
        providerDisplayName: String
    ) {
        self.supportsToolUse = supportsToolUse
        self.supportsGuidedGeneration = supportsGuidedGeneration
        self.supportsReasoning = supportsReasoning
        self.supportsStreaming = supportsStreaming
        self.supportsVision = supportsVision
        self.contextWindow = contextWindow
        self.maximumResponseTokens = maximumResponseTokens
        self.providerDisplayName = providerDisplayName
    }

    /// Check whether a specific capability is supported.
    /// Mirrors Apple's `LanguageModelCapabilities.contains(_:)`.
    public func contains(_ capability: Capability) -> Bool {
        switch capability {
        case .toolCalling: return supportsToolUse
        case .guidedGeneration: return supportsGuidedGeneration
        case .reasoning: return supportsReasoning
        case .streaming: return supportsStreaming
        case .vision: return supportsVision
        }
    }
}

// MARK: - LanguageModelCapabilities.Capability

extension LanguageModelCapabilities {
    /// Individual capabilities a model may support.
    /// Mirrors Apple's `LanguageModelCapabilities.Capability` enum.
    public enum Capability: String, Sendable, CaseIterable {
        case toolCalling
        case guidedGeneration
        case reasoning
        case streaming
        case vision
    }
}

// MARK: - LanguageModelExecutorConfiguration

/// Configuration for creating a LanguageModelExecutor.
/// Each provider defines its concrete configuration as a Hashable, Sendable struct.
/// Mirrors Apple's `LanguageModelExecutor.Configuration` associated type.
public protocol LanguageModelExecutorConfiguration: Hashable, Sendable {}

// MARK: - LanguageModel

/// Model provider interface. Every inference backend conforms to this.
/// Mirrors Apple's FoundationModels `LanguageModel` protocol (iOS 27+).
///
/// Key design difference from Apple:
/// - Uses `makeExecutor()` factory method instead of `associatedtype Executor`
///   because LanguageModelSession stores providers via `any LanguageModel`
///   existentials, which cannot express associated type constraints.
/// - The functionally-equivalent `executorConfiguration` property returns
///   the configuration used to create executors.
///
/// Model providers hold configuration (API key, base URL, model ID)
/// but not mutable runtime state — hence `Sendable`, not Actor.
public protocol LanguageModel: Sendable {
    /// Declared capabilities of this model.
    var capabilities: LanguageModelCapabilities { get }

    /// Human-readable display name for UI.
    var displayName: String { get }

    /// Configuration for creating an executor. Each invocation of
    /// `makeExecutor()` reads from this configuration.
    /// Mirrors Apple's `executorConfiguration` property.
    var executorConfiguration: any LanguageModelExecutorConfiguration { get }

    /// Create an executor for this model. Called by LanguageModelSession
    /// when a session needs to perform inference.
    func makeExecutor() -> any LanguageModelExecutor
}
