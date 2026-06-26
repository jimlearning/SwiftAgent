import Foundation

// MARK: - Response

/// Result of a non-streaming `LanguageModelSession.respond(to:)` call.
/// Wraps the updated transcript with optional usage metadata.
/// Mirrors Apple's FoundationModels `Response` type.
public struct Response: Sendable {
    public var transcript: Transcript
    public var usage: Usage?
    public var stopReason: String?

    public init(
        transcript: Transcript = Transcript(),
        usage: Usage? = nil,
        stopReason: String? = nil
    ) {
        self.transcript = transcript
        self.usage = usage
        self.stopReason = stopReason
    }
}

// MARK: - ResponseStream

/// Type alias for the streaming response type.
/// Mirrors Apple's FoundationModels `ResponseStream`.
/// Consumers iterate with `for try await event in stream`.
public typealias ResponseStream = AsyncThrowingStream<SessionEvent, Error>
