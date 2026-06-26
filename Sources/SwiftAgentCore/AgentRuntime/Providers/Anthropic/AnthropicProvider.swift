import Foundation

/// Anthropic Messages API provider implementing the LanguageModel + LanguageModelExecutor
/// contract. Both model metadata and inference live in one Sendable struct.
///
/// This is the post-migration provider. The legacy LLMClient/LLMProvider path is
/// deprecated and will be removed in Phase 4.
public struct AnthropicProvider: LanguageModel, LanguageModelExecutor, Sendable {

    // MARK: - Configuration

    public struct Configuration: LanguageModelExecutorConfiguration {
        public let apiKey: String
        public let baseURL: URL
        public let modelID: String

        public init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!, modelID: String) {
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
        "claude-sonnet-4-6": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: true,
            contextWindow: 200_000,
            maximumResponseTokens: 8_192,
            providerDisplayName: "Claude Sonnet 4"
        ),
        "claude-opus-4-6": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: true,
            contextWindow: 200_000,
            maximumResponseTokens: 32_768,
            providerDisplayName: "Claude Opus 4"
        ),
        "claude-haiku-4-6": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: false,
            supportsStreaming: true,
            supportsVision: true,
            contextWindow: 200_000,
            maximumResponseTokens: 4_096,
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
        let urlRequest: URLRequest
        do {
            urlRequest = try AnthropicRequestBuilder.build(
                transcript: request.transcript,
                tools: request.enabledTools,
                options: request.generationOptions,
                systemPrompt: nil,
                apiKey: apiKey,
                baseURL: baseURL,
                modelID: modelID
            )
        } catch {
            await channel.fail(with: .invalidResponse(reason: "Failed to build request: \(error.localizedDescription)"))
            return
        }

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                var errorBody: String? = nil
                var errorData = Data()
                do {
                    for try await byte in bytes.prefix(4096) {
                        errorData.append(byte)
                    }
                    errorBody = String(data: errorData, encoding: .utf8)
                } catch {}
                await channel.fail(with: .serverError(statusCode: status, body: errorBody))
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

            let parser = AnthropicSSEParser()
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
}
