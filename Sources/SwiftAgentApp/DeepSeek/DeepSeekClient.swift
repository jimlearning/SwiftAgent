import Foundation
import SwiftAgentCore

// MARK: - DeepSeek API Request/Response Types

/// OpenAI-compatible chat completion request body.
private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    var temperature: Double? = nil

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        // Only encode temperature if non-nil (R1 omits it)
        if let temperature {
            try container.encode(temperature, forKey: .temperature)
        }
    }
}

/// A single message in the chat completion request.
private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

/// A single SSE chunk from the streaming response.
private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let index: Int
        let delta: Delta
    }
    let choices: [Choice]
}

// MARK: - DeepSeekClient

/// Streaming chat completions client for the DeepSeek API (OpenAI-compatible).
///
/// Sends POST to `https://api.deepseek.com/v1/chat/completions` with SSE streaming.
/// Handles token extraction, `[DONE]` sentinel, and error responses.
public final class DeepSeekClient: Sendable {
    private let config: DeepSeekConfig
    private let session: URLSession

    public init(config: DeepSeekConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Streaming

    /// Send a streaming chat completion request.
    /// Returns an AsyncThrowingStream that yields token strings as they arrive.
    public func stream(
        messages: [Message],
        model: DeepSeekModel? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let effectiveModel = model ?? config.defaultModel
        let effectiveTemperature = effectiveModel.supportsTemperature
            ? (temperature ?? 0.7)
            : nil

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStream(
                        messages: messages,
                        model: effectiveModel,
                        temperature: effectiveTemperature,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Send a streaming chat completion with R1 reasoning support.
    /// Yields both regular tokens and reasoning tokens for R1 model.
    public func streamWithReasoning(
        messages: [Message],
        model: DeepSeekModel? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<DeepSeekStreamEvent, Error> {
        let effectiveModel = model ?? config.defaultModel
        let effectiveTemperature = effectiveModel.supportsTemperature
            ? (temperature ?? 0.7)
            : nil

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStreamWithReasoning(
                        messages: messages,
                        model: effectiveModel,
                        temperature: effectiveTemperature,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Implementation

    private func performStream(
        messages: [Message],
        model: DeepSeekModel,
        temperature: Double?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let request = try buildRequest(messages: messages, model: model, temperature: temperature)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.networkError("Invalid response type")
        }

        try checkHTTPStatus(httpResponse)

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }

            guard let data = jsonStr.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let content = chunk.choices.first?.delta.content,
                  !content.isEmpty else {
                continue
            }

            continuation.yield(content)
        }
    }

    private func performStreamWithReasoning(
        messages: [Message],
        model: DeepSeekModel,
        temperature: Double?,
        continuation: AsyncThrowingStream<DeepSeekStreamEvent, Error>.Continuation
    ) async throws {
        let request = try buildRequest(messages: messages, model: model, temperature: temperature)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.networkError("Invalid response type")
        }

        try checkHTTPStatus(httpResponse)

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                continuation.yield(.done)
                break
            }

            guard let data = jsonStr.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                continue
            }

            if let reasoning = chunk.choices.first?.delta.reasoningContent, !reasoning.isEmpty {
                continuation.yield(.reasoningToken(reasoning))
            }

            if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                continuation.yield(.token(content))
            }
        }
    }

    private func buildRequest(
        messages: [Message],
        model: DeepSeekModel,
        temperature: Double?
    ) throws -> URLRequest {
        let chatMessages = messages.map { msg in
            ChatMessage(
                role: deepSeekRole(for: msg.type),
                content: extractTextContent(from: msg)
            )
        }

        var url = config.baseURL
        url.appendPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: model.rawValue,
            messages: chatMessages,
            stream: true,
            temperature: temperature
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)

        return request
    }

    private func checkHTTPStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw DeepSeekError.unauthorized
        case 402:
            throw DeepSeekError.paymentRequired
        case 429:
            let retryAfter = response.allHeaderFields["retry-after"] as? String
            throw DeepSeekError.rateLimited(retryAfter: retryAfter.flatMap { Int($0) })
        case 500...599:
            throw DeepSeekError.serverError(status: response.statusCode, body: nil)
        default:
            throw DeepSeekError.httpError(status: response.statusCode)
        }
    }

    private func deepSeekRole(for role: MessageRole) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        default: return "user"
        }
    }

    private func extractTextContent(from message: Message) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: "\n")
    }
}

// MARK: - DeepSeek Stream Event

/// Events emitted during a DeepSeek streaming response.
public enum DeepSeekStreamEvent: Sendable {
    /// A regular text token from the assistant.
    case token(String)
    /// A reasoning/thinking chain token (R1 model).
    case reasoningToken(String)
    /// Stream completed successfully.
    case done
    /// An error occurred during streaming.
    case error(Error)
}

// MARK: - DeepSeek Errors

public enum DeepSeekError: Error, LocalizedError {
    case unauthorized
    case paymentRequired
    case rateLimited(retryAfter: Int?)
    case serverError(status: Int, body: String?)
    case httpError(status: Int)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API key invalid, please update in Settings"
        case .paymentRequired:
            return "DeepSeek balance low"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit hit, retrying in \(seconds)s"
            }
            return "Rate limit hit, please wait before retrying"
        case .serverError(let status, _):
            return "Server error (\(status)), please try again later"
        case .httpError(let status):
            return "HTTP error (\(status))"
        case .networkError(let message):
            return "Network error, \(message)"
        }
    }

    /// Whether this error is retryable.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .networkError:
            return true
        case .unauthorized, .paymentRequired, .httpError:
            return false
        }
    }
}
