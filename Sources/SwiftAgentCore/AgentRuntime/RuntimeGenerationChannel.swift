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
public actor RuntimeGenerationChannel: GenerationChannel {
    /// The async stream continuation to yield events into.
    private var continuation: AsyncThrowingStream<SessionEvent, Error>.Continuation?

    /// Guards against post-completion sends.
    /// Set to `true` by `complete()` or `fail(with:)`.
    private var isFinished: Bool = false

    /// Accumulated text for snapshot semantics.
    /// Updated via replacement (not append) by `send(textDelta:)`.
    private var accumulatedText: String = ""

    /// Accumulated thinking for snapshot semantics.
    /// Updated via replacement (not append) by `send(thinkingDelta:)`.
    private var accumulatedThinking: String = ""

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

    /// Yield a tool call request.
    public func send(toolCallRequest id: String, name: String, input: Data) async {
        guard !isFinished else { return }
        continuation?.yield(.toolCallRequested(id: id, name: name, input: input))
    }

    /// Yield a completed tool call (success path).
    /// The `isError` flag is `false` — tool errors are handled by `fail(with:)`.
    public func send(toolCallCompleted id: String, output: ToolOutputValue) async {
        guard !isFinished else { return }
        continuation?.yield(.toolCallCompleted(id: id, output: output, isError: false))
    }

    /// Finish the turn successfully.
    /// Sets `isFinished = true`, yields `.turnCompleted`, then calls
    /// `continuation.finish()`. All subsequent sends are silently dropped.
    public func complete(stopReason: String?, usage: Usage?) async {
        guard !isFinished else { return }
        isFinished = true
        continuation?.yield(.turnCompleted(usage: usage, stopReason: stopReason))
        continuation?.finish()
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
