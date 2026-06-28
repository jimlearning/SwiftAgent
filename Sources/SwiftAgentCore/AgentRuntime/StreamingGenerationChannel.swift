import Foundation

/// Concrete `GenerationChannel` implementation that bridges executor output
/// to an `AsyncThrowingStream<SessionEvent, Error>` continuation.
///
/// Every method guards against `isFinished` — after `complete()` or `fail()`,
/// all subsequent sends are silently dropped. This prevents the "dangling
/// event after turn complete" pitfall (PITFALLS.md Pitfall 3).
///
/// ## Snapshot Semantics
/// `send(textDelta:)` and `send(thinkingDelta:)` use REPLACEMENT semantics:
/// each call overwrites the accumulated value and yields the full snapshot.
/// The executor is responsible for providing the accumulated total text, not
/// incremental deltas.
public actor StreamingGenerationChannel: GenerationChannel {
    /// The async stream continuation to yield events into.
    private var continuation: AsyncThrowingStream<SessionEvent, Error>.Continuation?

    /// Guards against post-completion sends.
    /// Set to `true` by `complete()` or `fail(with:)`.
    private var isFinished: Bool = false

    /// Accumulated text for snapshot semantics.
    /// Updated via replacement (not append) by `send(textDelta:)`.
    public private(set) var accumulatedText: String = ""

    /// Accumulated thinking for snapshot semantics.
    /// Updated via replacement (not append) by `send(thinkingDelta:)`.
    ///
    /// Public read access allows the agent loop to append thinking to the
    /// transcript so it's passed back to the API on subsequent turns (required
    /// by DeepSeek/Anthropic thinking mode).
    public private(set) var accumulatedThinking: String = ""

    /// Opaque signature token for thinking blocks (required by thinking mode).
    /// Captured from SSE content_block_start events and passed to transcript
    /// so it can be included in subsequent API requests.
    public private(set) var thinkingSignature: String? = nil

    /// Records tool calls that were streamed through this channel.
    /// Used by the agent loop to inspect which tools were requested
    /// after the executor finishes, so it can execute them and re-prompt.
    public private(set) var recordedToolCalls: [(id: String, name: String, input: Data)] = []

    /// Whether `complete()` was called — signals the SSE stream included a
    /// proper `message_delta` completion event. Stays `false` if the stream
    /// was truncated, errored via `fail()`, or produced no events at all.
    public private(set) var receivedCompletion: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Continuation Setup

    /// Store the continuation for later yields.
    /// Must be called before any `send` methods.
    public func setContinuation(_ c: AsyncThrowingStream<SessionEvent, Error>.Continuation) {
        continuation = c
    }

    // MARK: - GenerationChannel Conformance

    /// Yield an accumulated text snapshot.
    /// Uses REPLACEMENT semantics: `accumulatedText = textDelta`.
    public func send(textDelta: String) async {
        guard !isFinished else { return }
        accumulatedText = textDelta
        continuation?.yield(.textDelta(accumulatedText))
    }

    /// Yield an accumulated thinking snapshot.
    /// Uses REPLACEMENT semantics: `accumulatedThinking = thinkingDelta`.
    public func send(thinkingDelta: String) async {
        guard !isFinished else { return }
        accumulatedThinking = thinkingDelta
        continuation?.yield(.thinkingDelta(accumulatedThinking))
    }

    /// Yield a tool call request and record it for the agent loop.
    public func send(toolCallRequest id: String, name: String, input: Data) async {
        guard !isFinished else { return }
        recordedToolCalls.append((id, name, input))
        continuation?.yield(.toolCallRequested(id: id, name: name, input: input))
    }

    /// Yield a completed tool call (success path).
    /// The `isError` flag is `false` — tool errors are handled by `fail(with:)`.
    public func send(toolCallCompleted id: String, output: ToolOutputValue) async {
        guard !isFinished else { return }
        continuation?.yield(.toolCallCompleted(id: id, output: output, isError: false))
    }

    /// Yield a turn-completion event. Sets `isFinished = true` so
    /// subsequent sends are silently dropped. Does NOT call
    /// `continuation.finish()` — the agent loop owns that decision.
    public func complete(stopReason: String?, usage: Usage?) async {
        guard !isFinished else { return }
        isFinished = true
        receivedCompletion = true
        continuation?.yield(.turnCompleted(usage: usage, stopReason: stopReason))
    }

    /// Store the thinking signature for the agent loop to read after streaming.
    public func update(thinkingSignature: String) async {
        self.thinkingSignature = thinkingSignature
    }

    /// Finish the turn with an error.
    /// Sets `isFinished = true`, yields `.error`, then calls
    /// `continuation.finish(throwing:)`. All subsequent sends are silently dropped.
    public func fail(with error: AgentRuntimeError) async {
        guard !isFinished else { return }
        isFinished = true
        continuation?.yield(.error(error))
        continuation?.finish(throwing: error)
    }
}
