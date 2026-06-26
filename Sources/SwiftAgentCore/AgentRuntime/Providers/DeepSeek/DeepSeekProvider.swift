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

    // MARK: - Stored Properties

    public let capabilities: LanguageModelCapabilities
    public let displayName: String
    private let apiKey: String
    private let baseURL: URL
    public let modelID: String
    private let compatibility: APICompatibility
    private let session: URLSession

    // MARK: - Model Capability Lookup

    private static let modelCapabilities: [String: LanguageModelCapabilities] = [
        "deepseek-chat": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: false,
            supportsVision: false,
            contextWindow: 64_000,
            maxOutputTokens: 8_192,
            providerDisplayName: "DeepSeek Chat"
        ),
        "deepseek-reasoner": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 64_000,
            maxOutputTokens: 8_192,
            providerDisplayName: "DeepSeek R1"
        ),
        "deepseek-r1": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 64_000,
            maxOutputTokens: 8_192,
            providerDisplayName: "DeepSeek R1"
        ),
        "deepseek-v4-pro": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 128_000,
            maxOutputTokens: 32_768,
            providerDisplayName: "DeepSeek V4 Pro"
        ),
        "deepseek-v4-flash": LanguageModelCapabilities(
            supportsStreaming: true,
            supportsToolUse: true,
            supportsThinking: true,
            supportsVision: false,
            contextWindow: 128_000,
            maxOutputTokens: 8_192,
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
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws {
        switch compatibility {
        case .anthropicCompatible:
            try await streamAnthropicCompat(
                transcript: transcript,
                tools: tools,
                options: options,
                channel: channel
            )
        case .openAICompatible:
            try await streamOpenAICompat(
                transcript: transcript,
                tools: tools,
                options: options,
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

        // Build request body — DeepSeek Anthropic-compat endpoint does NOT support
        // Anthropic thinking configuration (budget_tokens).
        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": options.maxTokens ?? 8_192,
            "stream": true,
            "messages": messages,
        ]
        if let system {
            body["system"] = system
        }
        if let toolDefs {
            body["tools"] = toolDefs
        }

        // Construct URL: {baseURL}/anthropic/v1/messages
        let url = baseURL.appendingPathComponent("anthropic/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // CRITICAL: NO anthropic-beta header (PITFALLS.md Pitfall 1).
        // DeepSeek's endpoint silently rejects Anthropic beta headers.

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            await channel.fail(with: .invalidResponse(reason: "Failed to encode request body to JSON"))
            return
        }
        request.httpBody = bodyData

        try await streamAndParse(request: request, channel: channel, compatibility: compatibility)
    }

    // MARK: - OpenAI-Compatible Streaming

    private func streamOpenAICompat(
        transcript: Transcript,
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        channel: GenerationChannel
    ) async throws {
        let messages = DeepSeekTranscriptTranslator.translateOpenAICompat(
            transcript,
            systemPrompt: nil
        )
        let toolDefs = tools.isEmpty ? nil : DeepSeekToolTranslator.translateOpenAICompat(tools)

        // Build Chat Completions request body
        var body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": true,
        ]
        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let toolDefs {
            body["tools"] = toolDefs
        }

        // Construct URL: {baseURL}/v1/chat/completions
        let url = baseURL.appendingPathComponent("v1/chat/completions")

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

        try await streamAndParse(request: request, channel: channel, compatibility: compatibility)
    }

    // MARK: - Shared Stream + Parse

    /// Execute the URLRequest, stream SSE lines, and parse through DeepSeekSSEParser.
    private func streamAndParse(
        request: URLRequest,
        channel: GenerationChannel,
        compatibility: APICompatibility
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

            let parser = DeepSeekSSEParser()
            try await parser.parse(lines: lineStream, channel: channel, compatibility: compatibility)
        } catch let error as AgentRuntimeError {
            await channel.fail(with: error)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                await channel.fail(with: .timeout)
            } else {
                await channel.fail(with: .serverError(statusCode: 0, body: error.localizedDescription))
            }
        }
    }
}
