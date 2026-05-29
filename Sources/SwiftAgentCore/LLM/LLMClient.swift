import Foundation

/// Protocol for debug logging of LLM API interactions.
/// Implementations receive raw request/response data for diagnostics.
public protocol LLMDebugLogger: Sendable {
    func logRequest(url: String, method: String, headers: [String: String], body: String)
    func logResponse(status: Int, headers: [String: String])
    func logStreamEvent(_ rawJSON: String)
    func logError(_ error: Error)
    func logResponseBody(_ body: String)
}

/// Anthropic Messages API client with streaming, thinking, caching, and beta support.
/// Mirrors Claude Code's `claude.ts` (~3300 lines).
public final class LLMClient: Sendable {
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let parser: LLMStreamParser
    private let sessionID: String
    private let provider: APIProvider
    private let debugLogger: (any LLMDebugLogger)?

    public init(
        apiKey: String,
        baseURL: String = "https://api.anthropic.com",
        model: String = "claude-sonnet-4-6",
        sessionID: String = UUID().uuidString,
        provider: APIProvider = .firstParty,
        debugLogger: (any LLMDebugLogger)? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.parser = LLMStreamParser()
        self.sessionID = sessionID
        self.provider = provider
        self.debugLogger = debugLogger

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Send messages with streaming response, optional thinking, beta features, and prompt caching.
    public func send(
        messages: [Message],
        model: String = "claude-sonnet-4-6",
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        tools: [ToolDefinition]? = nil,
        thinking: ThinkingConfig? = nil,
        betas: [String]? = nil,
        enablePromptCaching: Bool = true,
        toolChoice: String? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.streamRequest(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: tools,
                        thinking: thinking,
                        betas: betas,
                        enablePromptCaching: enablePromptCaching,
                        toolChoice: toolChoice,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Retry & Fallback

    /// Send messages with retry logic, exponential backoff, 529 overload detection,
    /// and automatic model fallback. Matches CC's withRetry() + queryModel() in claude.ts.
    public func sendWithRetry(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        tools: [ToolDefinition]? = nil,
        thinking: ThinkingConfig? = nil,
        betas: [String]? = nil,
        enablePromptCaching: Bool = true,
        options: RetryOptions? = nil,
        toolChoice: String? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let retryOptions = options ?? RetryOptions(
            maxRetries: DEFAULT_MAX_RETRIES,
            model: model,
            thinkingConfig: thinking ?? .disabled
        )

        return AsyncThrowingStream { continuation in
            Task {
                var consecutive529Errors = retryOptions.initialConsecutive529Errors
                var lastError: Error?

                for attempt in 1...(retryOptions.maxRetries + 1) {
                    do {
                        // Try streaming request
                        try await self.streamRequest(
                            messages: messages,
                            model: model,
                            systemPrompt: systemPrompt,
                            maxTokens: maxTokens,
                            tools: tools,
                            thinking: thinking,
                            betas: betas,
                            enablePromptCaching: enablePromptCaching,
                            toolChoice: toolChoice,
                            continuation: continuation
                        )
                        continuation.finish()
                        return
                    } catch {
                        lastError = error

                        // Check if non-retryable
                        if !isRetryableError(error) {
                            continuation.finish(throwing: error)
                            return
                        }

                        // Background sources bail immediately on 529
                        if is529Error(error) && shouldBailOn529(querySource: retryOptions.querySource) {
                            continuation.finish(throwing: CannotRetryError(
                                originalError: error,
                                retryContext: RetryContext(model: model, thinkingConfig: retryOptions.thinkingConfig)
                            ))
                            return
                        }

                        // Track consecutive 529s for model fallback
                        if is529Error(error),
                           let fallbackModel = retryOptions.fallbackModel,
                           isNonCustomOpusModel(retryOptions.model) {
                            consecutive529Errors += 1
                            if consecutive529Errors >= MAX_529_RETRIES {
                                // Fall back to non-streaming on the fallback model as last resort
                                do {
                                    try await self.streamNonStreamingFallback(
                                        messages: messages,
                                        model: fallbackModel,
                                        systemPrompt: systemPrompt,
                                        maxTokens: maxTokens,
                                        tools: tools,
                                        thinking: thinking,
                                        betas: betas,
                                        enablePromptCaching: enablePromptCaching,
                                        continuation: continuation
                                    )
                                    continuation.finish()
                                    return
                                } catch {
                                    // Non-streaming fallback also failed — throw FallbackTriggeredError
                                    continuation.finish(throwing: FallbackTriggeredError(
                                        originalModel: retryOptions.model,
                                        fallbackModel: fallbackModel
                                    ))
                                    return
                                }
                            }
                        }

                        // Last attempt — try non-streaming fallback
                        if attempt > retryOptions.maxRetries {
                            do {
                                try await self.streamNonStreamingFallback(
                                    messages: messages,
                                    model: retryOptions.fallbackModel ?? model,
                                    systemPrompt: systemPrompt,
                                    maxTokens: maxTokens,
                                    tools: tools,
                                    thinking: thinking,
                                    betas: betas,
                                    enablePromptCaching: enablePromptCaching,
                                    continuation: continuation
                                )
                                continuation.finish()
                                return
                            } catch {
                                continuation.finish(throwing: CannotRetryError(
                                    originalError: error,
                                    retryContext: RetryContext(model: model, thinkingConfig: retryOptions.thinkingConfig)
                                ))
                                return
                            }
                        }

                        // Compute backoff delay
                        let delay = getRetryDelay(
                            attempt: attempt,
                            retryAfterHeader: (error as? LLMError)?.retryAfterSeconds.map { String($0) }
                        )
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }

                // Should not reach here — fallback or CannotRetryError would have been thrown
                if let lastError {
                    continuation.finish(throwing: lastError)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// Non-streaming API call, wrapped as StreamEvent values.
    /// Used as fallback when streaming fails (529 overload, network errors).
    /// Matches CC's executeNonStreamingRequest() in claude.ts.
    public func sendNonStreaming(
        messages: [Message],
        model: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        tools: [ToolDefinition]? = nil,
        thinking: ThinkingConfig? = nil,
        betas: [String]? = nil,
        enablePromptCaching: Bool = false,
        timeoutMs: Double? = nil
    ) async throws -> NonStreamingResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        request.setValue("claude-cli/1.0 SwiftAgent", forHTTPHeaderField: "User-Agent")
        request.setValue(sessionID, forHTTPHeaderField: "X-Claude-Code-Session-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-client-request-id")

        var body: [String: Any] = [
            "model": normalizeModelStringForAPI(model),
            "max_tokens": maxTokens,
            "stream": false,
            "messages": apiFormattedMessages(messages, enablePromptCaching: enablePromptCaching)
        ]

        if let systemPrompt {
            body["system"] = apiFormattedSystem(systemPrompt, enablePromptCaching: enablePromptCaching)
        }

        if let tools {
            body["tools"] = tools.map { $0.apiFormatted }
            body["tool_choice"] = ["type": "auto"]
        }

        if let thinking, case .disabled = thinking {
            // no-op
        } else if let thinking {
            switch thinking {
            case .adaptive:
                body["thinking"] = ["type": "adaptive"]
            case .enabled(let budgetTokens):
                body["thinking"] = ["type": "enabled", "budget_tokens": min(budgetTokens, maxTokens - 1)]
            case .disabled:
                break
            }
            body.removeValue(forKey: "temperature")
        } else {
            body["temperature"] = 1
        }

        if let betas, !betas.isEmpty {
            body["anthropic_beta"] = betas
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let timeout = timeoutMs.map { $0 / 1000.0 } ?? (DEFAULT_NONSTREAMING_FALLBACK_TIMEOUT_MS / 1000.0)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        let nonStreamingSession = URLSession(configuration: config)

        let (data, response) = try await nonStreamingSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.httpError(status: 0, body: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.allHeaderFields["retry-after"] as? String
                throw LLMError.rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
            }
            if httpResponse.statusCode == 529 {
                throw LLMError.overloaded(body: body)
            }
            throw LLMError.nonStreamingError(status: httpResponse.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(NonStreamingResponse.self, from: data)
    }

    /// Stream a non-streaming response as StreamEvent values.
    /// Matches CC's non-streaming→streaming adaptation in claude.ts.
    private func streamNonStreamingFallback(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ToolDefinition]?,
        thinking: ThinkingConfig?,
        betas: [String]?,
        enablePromptCaching: Bool,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let response = try await sendNonStreaming(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            tools: tools,
            thinking: thinking,
            betas: betas,
            enablePromptCaching: enablePromptCaching
        )

        // Convert non-streaming response to stream events
        continuation.yield(.messageStart(message: StreamMessageStart(
            model: response.model,
            messageID: response.id,
            usage: nil
        )))

        for (index, block) in response.content.enumerated() {
            switch block.type {
            case "text":
                if let text = block.text {
                    continuation.yield(.contentBlockStart(index: index, block: .text))
                    continuation.yield(.textDelta(text: text))
                    continuation.yield(.contentBlockStop(index: index))
                }
            case "tool_use":
                if let id = block.id, let name = block.name {
                    continuation.yield(.contentBlockStart(index: index, block: .toolUse(name: name, id: id)))
                    if let input = block.input {
                        let inputData = try? JSONSerialization.data(withJSONObject: input.mapValues { $0.jsonObject })
                        if let inputStr = inputData.flatMap({ String(data: $0, encoding: .utf8) }) {
                            continuation.yield(.inputJSONDelta(delta: inputStr))
                        }
                    }
                    continuation.yield(.contentBlockStop(index: index))
                }
            default:
                break
            }
        }

        continuation.yield(.messageDelta(stopReason: response.stopReason, usage: response.usage))
        continuation.yield(.messageStop)
    }

    // MARK: - Private request

    private func streamRequest(
        messages: [Message],
        model: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ToolDefinition]?,
        thinking: ThinkingConfig?,
        betas: [String]?,
        enablePromptCaching: Bool,
        toolChoice: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        request.setValue("claude-cli/1.0 SwiftAgent", forHTTPHeaderField: "User-Agent")
        request.setValue(sessionID, forHTTPHeaderField: "X-Claude-Code-Session-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-client-request-id")

        var body: [String: Any] = [
            "model": normalizeModelStringForAPI(model),
            "max_tokens": maxTokens,
            "stream": true,
            "messages": apiFormattedMessages(messages, enablePromptCaching: enablePromptCaching)
        ]

        // System prompt with optional cache_control
        if let systemPrompt {
            body["system"] = apiFormattedSystem(systemPrompt, enablePromptCaching: enablePromptCaching)
        }

        if let tools {
            body["tools"] = tools.map { $0.apiFormatted }
            body["tool_choice"] = ["type": toolChoice ?? "auto"]
        }
        let hasThinking: Bool
        if let thinking, case .disabled = thinking {
            hasThinking = false
        } else if let thinking {
            hasThinking = true
            switch thinking {
            case .adaptive:
                body["thinking"] = ["type": "adaptive"]
            case .enabled(let budgetTokens):
                body["thinking"] = ["type": "enabled", "budget_tokens": min(budgetTokens, maxTokens - 1)]
            case .disabled:
                break
            }
        } else {
            hasThinking = false
        }

        // Temperature: omitted when thinking is enabled (API default is 1)
        if !hasThinking {
            body["temperature"] = 1
        }

        // Beta headers as anthropic_beta array in request body (matching CC SDK wire format)
        if let betas, !betas.isEmpty {
            body["anthropic_beta"] = betas
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Debug: log outgoing request
        if let logger = debugLogger {
            let reqHeaders = request.allHTTPHeaderFields ?? [:]
            let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "(binary)"
            logger.logRequest(url: request.url?.absoluteString ?? "", method: "POST", headers: reqHeaders, body: bodyStr)
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retryAfterHeader = (response as? HTTPURLResponse)?.allHeaderFields["retry-after"] as? String
            let respHeaders = ((response as? HTTPURLResponse)?.allHeaderFields as? [String: String]) ?? [:]
            var errorBody: String?
            var bodyData = Data()
            do {
                for try await byte in bytes {
                    bodyData.append(byte)
                }
                errorBody = String(data: bodyData, encoding: .utf8)
            } catch {
                // Body read failed — proceed without it
            }

            // Debug: log error response
            if let logger = debugLogger {
                logger.logResponse(status: status, headers: respHeaders)
                if let body = errorBody { logger.logResponseBody(body) }
            }

            if status == 401 { throw LLMError.unauthorized }
            if status == 429 { throw LLMError.rateLimited(retryAfter: retryAfterHeader.flatMap { Int($0) }) }
            if status == 529 { throw LLMError.overloaded(body: errorBody) }
            throw LLMError.httpError(status: status, body: errorBody)
        }

        // Debug: log successful response status
        if let logger = debugLogger {
            let respHeaders = (httpResponse.allHeaderFields as? [String: String]) ?? [:]
            logger.logResponse(status: httpResponse.statusCode, headers: respHeaders)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8) else { continue }

            // Debug: log raw SSE event
            if let logger = debugLogger {
                logger.logStreamEvent(jsonStr)
            }

            if let event = parser.parse(data: data) {
                continuation.yield(event)
            }
        }
    }

    // MARK: - API formatting helpers

    private func apiFormattedMessages(_ messages: [Message], enablePromptCaching: Bool) -> [[String: Any]] {
        guard enablePromptCaching, let lastIndex = messages.lastIndex(where: { _ in true }) else {
            return messages.map { $0.apiFormatted }
        }

        // Add cache_control to the last content block of the last message
        return messages.enumerated().map { (i, msg) in
            if i == lastIndex {
                return msg.apiFormattedWithCache
            }
            return msg.apiFormatted
        }
    }

    private func apiFormattedSystem(_ prompt: String, enablePromptCaching: Bool) -> Any {
        guard enablePromptCaching else { return prompt }

        // Two-phase system prompt caching: split on dynamic boundary so only the
        // static prefix gets cache_control. The dynamic suffix (CLAUDE.md, memory,
        // environment, date, etc.) is sent uncached. Matches CC's splitSysPromptPrefix.
        if let boundaryRange = prompt.range(of: SYSTEM_PROMPT_DYNAMIC_BOUNDARY) {
            let staticPrefix = prompt[..<boundaryRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let dynamicSuffix = prompt[boundaryRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

            var blocks: [[String: Any]] = []
            if !staticPrefix.isEmpty {
                blocks.append(["type": "text", "text": staticPrefix, "cache_control": ["type": "ephemeral"]])
            }
            if !dynamicSuffix.isEmpty {
                blocks.append(["type": "text", "text": dynamicSuffix])
            }
            return blocks.isEmpty ? prompt : blocks
        }

        // No boundary marker — cache entire prompt as a single block
        return [
            ["type": "text", "text": prompt, "cache_control": ["type": "ephemeral"]]
        ]
    }

    /// Normalize model string for API:
    /// 1. Resolve short keys (sonnet46) or canonical IDs to provider-specific IDs
    /// 2. Strip [1m]/[2m] suffixes
    /// Matches CC's normalizeModelStringForAPI in utils/model/model.ts.
    private func normalizeModelStringForAPI(_ model: String) -> String {
        let resolved = resolveModelID(model, provider: provider)
        return resolved
            .replacingOccurrences(of: "[1m]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[2m]", with: "", options: .caseInsensitive)
    }

    /// Resolve a model identifier to a provider-specific model ID.
    /// Matches CC's model resolution logic in utils/model/.
    private func resolveModelID(_ model: String, provider: APIProvider) -> String {
        // Try matching as a ModelKey first
        if let key = ModelKey(rawValue: model), let config = ALL_MODEL_CONFIGS[key] {
            switch provider {
            case .firstParty: return config.firstParty
            case .bedrock: return config.bedrock
            case .vertex: return config.vertex
            case .foundry: return config.foundry
            }
        }

        // Try matching as a canonical first-party ID
        for (_, config) in ALL_MODEL_CONFIGS {
            if config.firstParty == model {
                switch provider {
                case .firstParty: return config.firstParty
                case .bedrock: return config.bedrock
                case .vertex: return config.vertex
                case .foundry: return config.foundry
                }
            }
        }

        // Unknown model — return as-is
        return model
    }
}

// MARK: - ToolDefinition

/// Lightweight tool definition passed to the API.
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public var apiFormatted: [String: Any] {
        if let data = try? JSONEncoder().encode(inputSchema),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ["name": name, "description": description, "input_schema": dict]
        }
        return ["name": name, "description": description, "input_schema": ["type": "object"]]
    }
}

// MARK: - Message API formatting

extension Message {
    var apiFormatted: [String: Any] {
        let contentBlocks: [[String: Any]] = content.map { block in
            switch block {
            case .text(let text):
                return ["type": "text", "text": text] as [String: Any]
            case .toolUse(let id, let name, let input):
                return ["type": "tool_use", "id": id, "name": name, "input": input.anyValue] as [String: Any]
            case .serverToolUse(let id, let name, let input):
                return ["type": "server_tool_use", "id": id, "name": name, "input": input.anyValue] as [String: Any]
            case .toolResult(let toolID, let content, let isError):
                let contentValue: Any = content.apiFormatted
                return ["type": "tool_result", "tool_use_id": toolID, "content": contentValue, "is_error": isError] as [String: Any]
            case .image(_, let mediaType, let data, _):
                return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]] as [String: Any]
            case .thinking(let text, _):
                return ["type": "thinking", "thinking": text] as [String: Any]
            case .redactedThinking(let text):
                return ["type": "redacted_thinking", "data": text] as [String: Any]
            case .document(_, let mediaType, let data):
                return ["type": "document", "source": ["type": "base64", "media_type": mediaType, "data": data]] as [String: Any]
            case .toolReference(let name, let description):
                return ["type": "tool_reference", "name": name, "description": description] as [String: Any]
            }
        }
        return [
            "role": role.rawValue,
            "content": contentBlocks
        ]
    }

    /// Format with cache_control on the last cacheable content block.
    /// Walks backwards past thinking/redactedThinking blocks to find the correct
    /// cache breakpoint. Matches CC's assistantMessageToMessageParam.
    var apiFormattedWithCache: [String: Any] {
        let cacheMarkerIndex = lastCacheableBlockIndex()
        let contentBlocks: [[String: Any]] = content.enumerated().map { (i, block) in
            switch block {
            case .text(let text):
                var dict: [String: Any] = ["type": "text", "text": text]
                if i == cacheMarkerIndex {
                    dict["cache_control"] = ["type": "ephemeral"]
                }
                return dict
            case .toolUse(let id, let name, let input):
                return ["type": "tool_use", "id": id, "name": name, "input": input.anyValue] as [String: Any]
            case .serverToolUse(let id, let name, let input):
                return ["type": "server_tool_use", "id": id, "name": name, "input": input.anyValue] as [String: Any]
            case .toolResult(let toolID, let content, let isError):
                let contentValue: Any = content.apiFormatted
                var dict: [String: Any] = ["type": "tool_result", "tool_use_id": toolID, "content": contentValue, "is_error": isError]
                if i == cacheMarkerIndex {
                    dict["cache_control"] = ["type": "ephemeral"]
                }
                return dict
            case .image(_, let mediaType, let data, _):
                return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]] as [String: Any]
            case .thinking(let text, _):
                return ["type": "thinking", "thinking": text] as [String: Any]
            case .redactedThinking(let text):
                return ["type": "redacted_thinking", "data": text] as [String: Any]
            case .document(_, let mediaType, let data):
                return ["type": "document", "source": ["type": "base64", "media_type": mediaType, "data": data]] as [String: Any]
            case .toolReference(let name, let description):
                return ["type": "tool_reference", "name": name, "description": description] as [String: Any]
            }
        }
        return [
            "role": role.rawValue,
            "content": contentBlocks
        ]
    }

    /// Walks backwards from the last content block to find the first block that can
    /// carry a cache_control marker. Thinking and redactedThinking blocks are skipped
    /// because the API ignores cache_control on them.
    private func lastCacheableBlockIndex() -> Int? {
        var idx = content.count - 1
        while idx >= 0 {
            switch content[idx] {
            case .thinking, .redactedThinking:
                idx -= 1
            default:
                return idx
            }
        }
        return nil
    }
}

// MARK: - JSONValue marshalling

extension JSONValue {
    var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.jsonObject }
        case .object(let dict): return dict.mapValues { $0.jsonObject }
        }
    }
}

// MARK: - Errors

public enum LLMError: Error {
    case httpError(status: Int, body: String? = nil)
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case overloaded(body: String? = nil)
    case parseError(String)
    case noData
    /// Non-streaming API request failed.
    case nonStreamingError(status: Int, body: String? = nil)

    /// Extract the HTTP status code from error cases that carry one.
    public var statusCode: Int? {
        switch self {
        case .httpError(let status, _): return status
        case .nonStreamingError(let status, _): return status
        default: return nil
        }
    }

    /// Human-readable diagnostic string for logging and debugging.
    public var diagnosticDescription: String {
        switch self {
        case .httpError(let status, let body):
            var desc = "HTTP \(status)"
            if let body, !body.isEmpty { desc += ": \(body.prefix(500))" }
            return desc
        case .unauthorized: return "Unauthorized (401)"
        case .rateLimited(let retryAfter):
            var desc = "Rate limited (429)"
            if let s = retryAfter { desc += ", retry after \(s)s" }
            return desc
        case .overloaded(let body):
            var desc = "Overloaded (529)"
            if let body, !body.isEmpty { desc += ": \(body.prefix(500))" }
            return desc
        case .parseError(let msg): return "Parse error: \(msg)"
        case .noData: return "No data received"
        case .nonStreamingError(let status, let body):
            var desc = "Non-streaming HTTP \(status)"
            if let body, !body.isEmpty { desc += ": \(body.prefix(500))" }
            return desc
        }
    }

    /// Extract the retry-after header value in seconds, if any.
    public var retryAfterSeconds: Int? {
        if case .rateLimited(let retryAfter) = self {
            return retryAfter
        }
        return nil
    }

    /// Extract the response body, if captured.
    public var responseBody: String? {
        switch self {
        case .httpError(_, let body): return body
        case .overloaded(let body): return body
        case .nonStreamingError(_, let body): return body
        default: return nil
        }
    }
}

// MARK: - Non-Streaming Response Types

/// Decodable representation of a non-streaming Anthropic Messages API response.
/// Used for streaming→non-streaming fallback matching CC's executeNonStreamingRequest().
public struct NonStreamingResponse: Decodable, Sendable {
    public let id: String
    public let type: String
    public let role: String
    public let content: [NonStreamingContentBlock]
    public let model: String
    public let stopReason: String?
    public let stopSequence: String?
    public let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

/// A content block within a non-streaming API response.
public struct NonStreamingContentBlock: Decodable, Sendable {
    public let type: String
    public let text: String?
    public let id: String?
    public let name: String?
    public let input: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent([String: JSONValue].self, forKey: .input)
    }
}
