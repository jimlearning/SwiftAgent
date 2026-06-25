import Foundation

// MARK: - RuntimeToolDefinition

/// Normalized tool definition sent from AgentRuntime to executor.
/// Provider-agnostic; each executor maps to its own wire format.
///
/// Named RuntimeToolDefinition to avoid collision with the existing
/// `ToolDefinition` in LLM/LLMClient.swift. The existing type will be
/// deprecated when AgentRuntime replaces QueryEngine in Phase 3.
public struct RuntimeToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema
}

// MARK: - GenerationOptions

/// Generation parameters sent to the executor.
public struct GenerationOptions: Sendable {
    public var maxTokens: Int?
    public var temperature: Double?
    public var reasoningBudget: Int?
    public var stream: Bool

    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        reasoningBudget: Int? = nil,
        stream: Bool = true
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.reasoningBudget = reasoningBudget
        self.stream = stream
    }
}

// MARK: - LanguageModelExecutor

/// Internal protocol for per-provider inference backends.
/// NOT exposed to CLI/App — used only by AgentRuntime.
///
/// Each executor owns its wire format translation, SSE parsing,
/// and model-specific behavior entirely.
public protocol LanguageModelExecutor: Sendable {
    /// The model this executor serves.
    var model: any LanguageModel { get }

    /// Send a generation request to the model, streaming results
    /// through the provided channel.
    ///
    /// - Parameters:
    ///   - transcript: The conversation history to include.
    ///   - tools: Available tool definitions.
    ///   - options: Generation configuration.
    ///   - channel: Streaming channel for results.
    func respond(
        to transcript: Transcript,
        tools: [RuntimeToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws
}
