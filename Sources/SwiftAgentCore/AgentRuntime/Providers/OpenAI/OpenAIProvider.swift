import Foundation

/// OpenAI provider implementing the LanguageModel + LanguageModelExecutor contract.
///
/// Supports two API compatibility modes:
/// - `.responses` (default): Uses `/v1/responses` endpoint with Responses API format.
///   Recommended for all new projects (2026+).
/// - `.chatCompletions` (legacy): Uses `/v1/chat/completions` endpoint with Chat
///   Completions format. Kept for backward compatibility.
public struct OpenAIProvider: LanguageModel, LanguageModelExecutor, Sendable {

    // MARK: - API Compatibility

    /// Wire format and endpoint selection.
    public enum APICompatibility: Sendable {
        /// Responses API — `/v1/responses`, `input` array, typed items.
        case responses
        /// Chat Completions (legacy) — `/v1/chat/completions`, `messages` array.
        case chatCompletions
    }

    // MARK: - Configuration

    public struct Configuration: LanguageModelExecutorConfiguration {
        public let apiKey: String
        public let baseURL: URL
        public let modelID: String
        public let compatibility: APICompatibility

        public init(
            apiKey: String,
            baseURL: URL = URL(string: "https://api.openai.com")!,
            modelID: String,
            compatibility: APICompatibility = .responses
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.modelID = modelID
            self.compatibility = compatibility
        }
    }

    // MARK: - Stored Properties

    public let capabilities: LanguageModelCapabilities
    public let displayName: String
    public let executorConfiguration: any LanguageModelExecutorConfiguration
    private let apiKey: String
    private let baseURL: URL
    private let modelID: String
    private let compatibility: APICompatibility
    private let session: URLSession

    // MARK: - Model Capability Lookup

    private static let modelCapabilities: [String: LanguageModelCapabilities] = [
        "gpt-5.2": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: false,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 128_000,
            maximumResponseTokens: 16_384,
            providerDisplayName: "GPT-5.2"
        ),
        "gpt-5.2-mini": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: false,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 128_000,
            maximumResponseTokens: 4_096,
            providerDisplayName: "GPT-5.2 Mini"
        ),
        "o4": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 200_000,
            maximumResponseTokens: 32_768,
            providerDisplayName: "o4"
        ),
    ]

    // MARK: - Initialization

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        modelID: String,
        compatibility: APICompatibility = .responses,
        displayName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelID = modelID
        self.compatibility = compatibility
        self.executorConfiguration = Configuration(
            apiKey: apiKey, baseURL: baseURL, modelID: modelID, compatibility: compatibility
        )

        let caps = Self.modelCapabilities[modelID]
            ?? LanguageModelCapabilities(providerDisplayName: modelID)
        self.capabilities = caps
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
        to request: LanguageModelExecutorGenerationRequest,
        streamingInto channel: GenerationChannel
    ) async throws {
        switch compatibility {
        case .responses:
            try await respondResponses(request: request, channel: channel)
        case .chatCompletions:
            try await respondChatCompletions(request: request, channel: channel)
        }
    }

    // MARK: - Responses API Path

    private func respondResponses(
        request: LanguageModelExecutorGenerationRequest,
        channel: GenerationChannel
    ) async throws {
        let input = OpenAITranscriptTranslator.translateResponses(request.transcript, systemPrompt: nil)
        let toolDefs = OpenAIToolTranslator.translateResponses(request.enabledTools)

        var body: [String: Any] = [
            "model": modelID,
            "input": input,
            "stream": true,
        ]

        if !toolDefs.isEmpty {
            body["tools"] = toolDefs
        }

        if let maxTokens = request.generationOptions.maximumResponseTokens {
            body["max_output_tokens"] = maxTokens
        }

        let isO4 = modelID == "o4"
        if isO4, let budget = request.generationOptions.reasoningBudget {
            body["reasoning_effort"] = mapBudgetToEffort(budget)
        }

        if let temperature = request.generationOptions.temperature, !isO4 {
            body["temperature"] = temperature
        }

        let url = baseURL.appendingPathComponent("v1/responses")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 600
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            await channel.fail(with: .invalidResponse(reason: "Failed to encode request body to JSON"))
            return
        }
        urlRequest.httpBody = bodyData

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await channel.fail(with: .serverError(statusCode: status, body: nil))
                return
            }

            let parser = ResponsesSSEParser()
            try await parser.parse(lines: bytes.lines, channel: channel)
        } catch let error as AgentRuntimeError {
            await channel.fail(with: error)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                await channel.fail(with: .timeout(.init(duration: nil)))
            } else {
                await channel.fail(with: .serverError(statusCode: 0, body: error.localizedDescription))
            }
        }
    }

    // MARK: - Chat Completions Path (Legacy)

    private func respondChatCompletions(
        request: LanguageModelExecutorGenerationRequest,
        channel: GenerationChannel
    ) async throws {
        let messages = OpenAITranscriptTranslator.translateChatCompletions(request.transcript, systemPrompt: nil)
        let toolDefs = OpenAIToolTranslator.translateChatCompletions(request.enabledTools)

        var body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]

        if !toolDefs.isEmpty {
            body["tools"] = toolDefs
            body["tool_choice"] = "auto"
        }

        if let maxTokens = request.generationOptions.maximumResponseTokens {
            body["max_completion_tokens"] = maxTokens
        }

        let isO4 = modelID == "o4"
        if isO4, let budget = request.generationOptions.reasoningBudget {
            body["reasoning_effort"] = mapBudgetToEffort(budget)
        }

        if let temperature = request.generationOptions.temperature, !isO4 {
            body["temperature"] = temperature
        }

        let url = baseURL.appendingPathComponent("v1/chat/completions")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 600
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            await channel.fail(with: .invalidResponse(reason: "Failed to encode request body to JSON"))
            return
        }
        urlRequest.httpBody = bodyData

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await channel.fail(with: .serverError(statusCode: status, body: nil))
                return
            }

            let lineStream = AsyncStream<String> { continuation in
                Task {
                    do {
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish()
                    }
                }
            }

            let parser = OpenAISSEParser()
            try await parser.parse(lines: lineStream, channel: channel)
        } catch let error as AgentRuntimeError {
            await channel.fail(with: error)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                await channel.fail(with: .timeout(.init(duration: nil)))
            } else {
                await channel.fail(with: .serverError(statusCode: 0, body: error.localizedDescription))
            }
        }
    }

    // MARK: - Private Helpers

    private func mapBudgetToEffort(_ budget: Int) -> String {
        switch budget {
        case 0...4096: return "low"
        case 4097...16384: return "medium"
        default: return "high"
        }
    }
}
