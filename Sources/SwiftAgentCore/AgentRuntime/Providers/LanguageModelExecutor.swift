import Foundation

// MARK: - SessionToolDefinition

/// Normalized tool definition sent from LanguageModelSession to executor.
/// Provider-agnostic; each executor maps to its own wire format.
/// Aligned with Apple's `Transcript.ToolDefinition` — uses `parameters`
/// (not `inputSchema`), matching `init(name:description:parameters:)`.
///
/// Named SessionToolDefinition to avoid collision with the existing
/// `ToolDefinition` in LLM/LLMClient.swift.
public struct SessionToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the tool's parameters. Aligned with Apple's `parameters` property.
    public let parameters: JSONSchema
    /// Whether the tool should defer loading. SwiftAgent extension beyond Apple's ToolDefinition.
    public let deferLoading: Bool

    public init(name: String, description: String, parameters: JSONSchema, deferLoading: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.deferLoading = deferLoading
    }
}

/// Backward-compatible alias. Prefer SessionToolDefinition in new code.
public typealias ToolDefinition = SessionToolDefinition

// MARK: - GenerationOptions

/// Options that control how the model generates its response to a prompt.
/// Aligned with Apple's `GenerationOptions` struct (FoundationModels, iOS 26+).
public struct GenerationOptions: Sendable {
    /// Sampling strategy for token selection. Apple-aligned.
    public enum SamplingMode: String, Sendable {
        case greedy
        case temperature
    }

    /// Controls how the model uses tools. Apple-aligned (iOS 27 beta).
    public enum ToolCallingMode: String, Sendable {
        case auto
        case required
        case none
    }

    /// Sampling strategy for token selection. Mirrors Apple's `samplingMode`.
    public var samplingMode: SamplingMode

    /// Temperature influences model response confidence. Mirrors Apple's `temperature`.
    /// Higher values = more creative. Range typically 0.0–2.0.
    public var temperature: Double?

    /// Maximum tokens the model may produce. Mirrors Apple's `maximumResponseTokens`.
    public var maximumResponseTokens: Int?

    /// Tool calling behavior. Mirrors Apple's `toolCallingMode` (iOS 27 beta).
    public var toolCallingMode: ToolCallingMode

    /// Reasoning budget (thinking tokens). SwiftAgent extension — Apple uses
    /// `ContextOptions.ReasoningLevel` for this.
    public var reasoningBudget: Int?

    /// Whether to stream the response. SwiftAgent extension — Apple infers
    /// this from whether `streamResponse` or `respond` is called.
    public var stream: Bool

    public init(
        samplingMode: SamplingMode = .temperature,
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil,
        toolCallingMode: ToolCallingMode = .auto,
        reasoningBudget: Int? = nil,
        stream: Bool = true
    ) {
        self.samplingMode = samplingMode
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
        self.toolCallingMode = toolCallingMode
        self.reasoningBudget = reasoningBudget
        self.stream = stream
    }
}

// MARK: - ContextOptions

/// Options that configure details appearing in the prompt.
/// Aligned with Apple's `ContextOptions` struct (FoundationModels, iOS 27+).
public struct ContextOptions: Sendable {
    /// Controls the amount of thinking the model produces before responding.
    /// Mirrors Apple's `ContextOptions.ReasoningLevel`.
    public enum ReasoningLevel: String, Sendable {
        case low
        case medium
        case high
    }

    /// Inject the schema into the prompt to bias the model.
    public var includeSchemaInPrompt: Bool

    /// Thinking effort level for reasoning models.
    public var reasoningLevel: ReasoningLevel

    public init(
        includeSchemaInPrompt: Bool = false,
        reasoningLevel: ReasoningLevel = .medium
    ) {
        self.includeSchemaInPrompt = includeSchemaInPrompt
        self.reasoningLevel = reasoningLevel
    }
}

// MARK: - LanguageModelExecutorGenerationRequest

/// Bundles everything an executor needs to handle a generation call.
/// Aligned with Apple's `LanguageModelExecutorGenerationRequest` struct
/// (FoundationModels, iOS 27+).
public struct LanguageModelExecutorGenerationRequest: Sendable {
    /// Request identifier for logging and tracing.
    public var id: UUID
    /// Conversation history to include.
    public var transcript: Transcript
    /// Tools the model is allowed to call.
    public var enabledTools: [SessionToolDefinition]
    /// Optional schema dictating required output format.
    public var schema: JSONSchema?
    /// Generation options controlling sampling behavior.
    public var generationOptions: GenerationOptions
    /// Settings configuring how the model is prompted.
    public var contextOptions: ContextOptions
    /// Metadata to attach to the request.
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        transcript: Transcript,
        enabledTools: [SessionToolDefinition] = [],
        schema: JSONSchema? = nil,
        generationOptions: GenerationOptions = GenerationOptions(),
        contextOptions: ContextOptions = ContextOptions(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.transcript = transcript
        self.enabledTools = enabledTools
        self.schema = schema
        self.generationOptions = generationOptions
        self.contextOptions = contextOptions
        self.metadata = metadata
    }
}

// MARK: - LanguageModelExecutor

/// Internal protocol for per-provider inference backends.
/// Aligned with Apple's `LanguageModelExecutor` protocol (FoundationModels, iOS 27+).
///
/// Key differences from Apple:
/// - Uses `any LanguageModel` for `model` instead of `associatedtype Model` —
///   required because LanguageModelSession stores providers via existential.
/// - Uses `GenerationChannel` instead of `LanguageModelExecutorGenerationChannel` —
///   same role, renamed for brevity.
///
/// Each executor owns its wire format translation, SSE parsing,
/// and model-specific behavior entirely.
public protocol LanguageModelExecutor: Sendable {
    /// The model this executor serves.
    var model: any LanguageModel { get }

    /// Send a generation request to the model, streaming results through the channel.
    /// Aligned with Apple's `respond(to:model:streamingInto:)`.
    ///
    /// - Parameters:
    ///   - request: Bundled generation request (transcript, tools, options, schema, context, metadata).
    ///   - channel: Streaming channel for incremental results.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        streamingInto channel: GenerationChannel
    ) async throws

    /// Preload model assets or pre-fill caches. Called by the framework
    /// in response to session prewarming. Aligned with Apple's `prewarm(model:transcript:)`.
    /// Default is no-op.
    func prewarm(transcript: Transcript)
}

public extension LanguageModelExecutor {
    func prewarm(transcript: Transcript) { }
}

// MARK: - Deprecated API (backward compatibility)

extension LanguageModelExecutor {
    @available(*, deprecated, message: "Use respond(to:streamingInto:) with LanguageModelExecutorGenerationRequest")
    public func respond(
        to transcript: Transcript,
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws {
        let request = LanguageModelExecutorGenerationRequest(
            transcript: transcript,
            enabledTools: tools,
            generationOptions: options
        )
        try await respond(to: request, streamingInto: channel)
    }
}
