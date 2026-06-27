import Foundation

/// OpenAI Chat Completions API provider implementing the LanguageModel + LanguageModelExecutor
/// contract. Both model metadata and inference live in one Sendable struct.
///
/// This is the post-migration provider. The legacy LLMClient/LLMProvider path is
/// deprecated and will be removed in Phase 4.
public struct OpenAIProvider: LanguageModel, LanguageModelExecutor, Sendable {

    // MARK: - Configuration

    public struct Configuration: LanguageModelExecutorConfiguration {
        public let apiKey: String
        public let baseURL: URL
        public let modelID: String

        public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com")!, modelID: String) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.modelID = modelID
        }
    }

    // MARK: - Stored Properties

    public let capabilities: LanguageModelCapabilities
    public let displayName: String
    public let executorConfiguration: any LanguageModelExecutorConfiguration
    private let apiKey: String
    private let baseURL: URL
    private let modelID: String
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
        displayName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelID = modelID
        self.executorConfiguration = Configuration(apiKey: apiKey, baseURL: baseURL, modelID: modelID)

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
        let messages = OpenAITranscriptTranslator.translateChatCompletions(request.transcript, systemPrompt: nil)
        let toolDefs = OpenAIToolTranslator.translate(request.enabledTools)

        // Build request body
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

        // o4 model: reasoning_effort mapping, no temperature
        let isO4 = modelID == "o4"
        if isO4, let budget = request.generationOptions.reasoningBudget {
            body["reasoning_effort"] = mapBudgetToEffort(budget)
        }

        if let temperature = request.generationOptions.temperature, !isO4 {
            body["temperature"] = temperature
        }

        // Construct URL
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

            // Convert URLSession.AsyncBytes.lines to AsyncStream<String> for the parser
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

    /// Map a reasoning budget in tokens to an OpenAI reasoning_effort string.
    /// - 0...4096 → "low"
    /// - 4097...16384 → "medium"
    /// - 16385+ → "high"
    private func mapBudgetToEffort(_ budget: Int) -> String {
        switch budget {
        case 0...4096: return "low"
        case 4097...16384: return "medium"
        default: return "high"
        }
    }
}
