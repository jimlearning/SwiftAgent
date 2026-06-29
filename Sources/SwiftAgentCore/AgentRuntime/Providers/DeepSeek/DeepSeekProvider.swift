import Foundation

/// DeepSeek API provider implementing both LanguageModel and LanguageModelExecutor.
///
/// Handles both of DeepSeek's wire formats through an internal `APICompatibility` switch:
/// - `.anthropicCompatible`: Targets `/anthropic/v1/messages` (same shape as Anthropic Messages API).
///   Strips anthropogenic headers and cache_control markers that DeepSeek rejects (PITFALLS.md Pitfall 1).
/// - `.openAICompatible`: Targets `/v1/chat/completions` (Chat Completions format).
///   Handles R1 reasoning_content as thinkingDelta snapshots.
///
/// Both paths produce identical SessionEvent sequences for equivalent inputs.
///
/// This is the post-migration provider. The legacy LLMClient/LLMProvider path is
/// deprecated and will be removed in Phase 4.
public struct DeepSeekProvider: LanguageModel, LanguageModelExecutor, Sendable {

    // MARK: - Configuration

    public struct Configuration: LanguageModelExecutorConfiguration {
        public let apiKey: String
        public let baseURL: URL
        public let modelID: String
        public let compatibility: APICompatibility

        public init(apiKey: String, baseURL: URL, modelID: String, compatibility: APICompatibility = .anthropicCompatible) {
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
    public let modelID: String

    /// Public accessors for services that need direct API access (e.g. SessionTitleGenerator).
    public var apiKeyValue: String { apiKey }
    public var baseURLValue: URL { baseURL }
    private let compatibility: APICompatibility
    private let session: URLSession

    // MARK: - Model Capability Lookup

    private static let modelCapabilities: [String: LanguageModelCapabilities] = [
        "deepseek-chat": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: false,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 64_000,
            maximumResponseTokens: 8_192,
            providerDisplayName: "DeepSeek Chat"
        ),
        "deepseek-reasoner": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 64_000,
            maximumResponseTokens: 8_192,
            providerDisplayName: "DeepSeek R1"
        ),
        "deepseek-r1": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 64_000,
            maximumResponseTokens: 8_192,
            providerDisplayName: "DeepSeek R1"
        ),
        "deepseek-v4-pro": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 128_000,
            maximumResponseTokens: 32_768,
            providerDisplayName: "DeepSeek V4 Pro"
        ),
        "deepseek-v4-flash": LanguageModelCapabilities(
            supportsToolUse: true,
            supportsGuidedGeneration: false,
            supportsReasoning: true,
            supportsStreaming: true,
            supportsVision: false,
            contextWindow: 128_000,
            maximumResponseTokens: 8_192,
            providerDisplayName: "DeepSeek V4 Flash"
        ),
    ]

    // MARK: - Initialization

    public init(
        apiKey: String,
        baseURL: URL? = nil,
        modelID: String,
        compatibility: APICompatibility = .anthropicCompatible,
        displayName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? compatibility.defaultBaseURL
        self.modelID = modelID
        self.compatibility = compatibility
        self.executorConfiguration = Configuration(apiKey: apiKey, baseURL: self.baseURL, modelID: modelID, compatibility: compatibility)

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
        case .anthropicCompatible:
            try await streamAnthropicCompat(
                transcript: request.transcript,
                tools: request.enabledTools,
                options: request.generationOptions,
                channel: channel
            )
        case .openAICompatible:
            try await streamOpenAICompat(
                transcript: request.transcript,
                tools: request.enabledTools,
                options: request.generationOptions,
                channel: channel
            )
        }
    }

    // MARK: - Anthropic-Compatible Streaming

    private func streamAnthropicCompat(
        transcript: Transcript,
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        channel: GenerationChannel
    ) async throws {
        let (messages, system) = DeepSeekTranscriptTranslator.translateAnthropicCompat(
            transcript,
            systemPrompt: nil
        )
        let toolDefs = tools.isEmpty ? nil : DeepSeekToolTranslator.translateAnthropicCompat(tools)

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": options.maximumResponseTokens ?? 8_192,
            "stream": true,
            "messages": messages,
        ]
        if let system {
            body["system"] = system
        }
        if let toolDefs {
            body["tools"] = toolDefs
        }
        // Do NOT send thinking config for DeepSeek reasoning models — the model
        // returns thinking blocks with valid signatures (via signature_delta)
        // regardless of config, and including thinking config triggers stricter
        // server-side validation that blocks re-prompt with thinking blocks.

        // Construct URL: {baseURL}/anthropic/v1/messages
        let url = baseURL.appendingPathComponent("anthropic/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-06-01", forHTTPHeaderField: "anthropic-version")
        // CRITICAL: NO anthropic-beta header (PITFALLS.md Pitfall 1).
        // DeepSeek's endpoint silently rejects Anthropic beta headers.

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            await channel.fail(with: .invalidResponse(reason: "Failed to encode request body to JSON"))
            return
        }
        request.httpBody = bodyData

        // Debug: print request body
        if let bodyStr = String(data: bodyData, encoding: .utf8) {
            // Print full body for requests containing assistant messages (re-prompts)
            if bodyStr.contains("\"assistant\"") {
                print("[DeepSeekProvider] anthropic RE-PROMPT:\n\(bodyStr)")
            } else {
                print("[DeepSeekProvider] anthropic FIRST request: \(bodyStr.prefix(500))")
            }
        }

        try await streamAndParse(request: request, channel: channel)
    }

    // MARK: - OpenAI-Compatible Streaming

    private func streamOpenAICompat(
        transcript: Transcript,
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        channel: GenerationChannel
    ) async throws {
        let messages = DeepSeekTranscriptTranslator.translateChatCompletions(transcript, systemPrompt: nil)
        let toolDefs = DeepSeekToolTranslator.translateChatCompletions(tools)

        // Build Chat Completions request body
        var body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": true,
        ]
        if let maxTokens = options.maximumResponseTokens {
            body["max_tokens"] = maxTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if !toolDefs.isEmpty {
            body["tools"] = toolDefs
        }

        // Construct URL via endpoint path (currently /v1/chat/completions)
        let url = baseURL.appendingPathComponent(compatibility.endpointPath)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            await channel.fail(with: .invalidResponse(reason: "Failed to encode request body to JSON"))
            return
        }
        request.httpBody = bodyData

        // Debug: print request body
        if let bodyStr = String(data: bodyData, encoding: .utf8) {
            print("[DeepSeekProvider] openAI request: \(bodyStr.prefix(3000))")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)

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
                print("[DeepSeekProvider] HTTP \(status): \(errorBody ?? "no body")")
                await channel.fail(with: .serverError(statusCode: status, body: errorBody))
                return
            }

            let parser = ChatCompletionsSSEParser()
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

    // MARK: - Shared Stream + Parse

    /// Execute the URLRequest, stream SSE lines, and parse through DeepSeekSSEParser.
    private func streamAndParse(
        request: URLRequest,
        channel: GenerationChannel
    ) async throws {
        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // Read error body for diagnostics
                var errorBody: String? = nil
                var errorData = Data()
                do {
                    for try await byte in bytes.prefix(4096) {
                        errorData.append(byte)
                    }
                    errorBody = String(data: errorData, encoding: .utf8)
                } catch {}
                print("[DeepSeekProvider] HTTP \(status): \(errorBody ?? "no body")")
                await channel.fail(with: .serverError(statusCode: status, body: errorBody))
                return
            }

            let parser = DeepSeekSSEParser()
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
}
