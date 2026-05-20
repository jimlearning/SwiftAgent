import Foundation

// MARK: - CC Retry/Backoff Constants

/// Default max retries matching CC's DEFAULT_MAX_RETRIES in withRetry.ts.
public let DEFAULT_MAX_RETRIES = 10

/// Base delay in milliseconds for exponential backoff.
/// Matches CC's BASE_DELAY_MS in withRetry.ts.
public let BASE_DELAY_MS: Double = 500

/// Max consecutive 529 errors before triggering model fallback.
/// Matches CC's MAX_529_RETRIES in withRetry.ts.
public let MAX_529_RETRIES = 3

/// Default fast-mode cooldown hold duration (30 min).
/// Matches CC's DEFAULT_FAST_MODE_FALLBACK_HOLD_MS in withRetry.ts.
public let DEFAULT_FAST_MODE_FALLBACK_HOLD_MS = 30 * 60 * 1000

/// Minimum cooldown duration (10 min).
/// Matches CC's MIN_COOLDOWN_MS in withRetry.ts.
public let MIN_COOLDOWN_MS = 10 * 60 * 1000

/// Threshold for short retry-after (20s) — below this, preserve prompt cache.
/// Matches CC's SHORT_RETRY_THRESHOLD_MS in withRetry.ts.
public let SHORT_RETRY_THRESHOLD_MS = 20 * 1000

/// Error message for repeated 529 failures without fallback.
/// Matches CC's REPEATED_529_ERROR_MESSAGE in errors.ts.
public let REPEATED_529_ERROR_MESSAGE = "Repeated 529 Overloaded errors"

/// Persistent-mode max backoff (5 min).
/// Matches CC's PERSISTENT_MAX_BACKOFF_MS in withRetry.ts.
public let PERSISTENT_MAX_BACKOFF_MS = 5 * 60 * 1000

/// Persistent-mode reset cap (6 hours).
/// Matches CC's PERSISTENT_RESET_CAP_MS in withRetry.ts.
public let PERSISTENT_RESET_CAP_MS = 6 * 60 * 60 * 1000

/// Heartbeat interval for persistent retry keep-alive messages (30s).
/// Matches CC's HEARTBEAT_INTERVAL_MS in withRetry.ts.
public let HEARTBEAT_INTERVAL_MS = 30_000

/// Default non-streaming fallback timeout (300s).
/// Matches CC's getNonstreamingFallbackTimeoutMs() default in claude.ts.
public let DEFAULT_NONSTREAMING_FALLBACK_TIMEOUT_MS: Double = 300_000

// MARK: - Foreground 529 Retry Sources

/// Query sources eligible for 529 retry (foreground/user-facing).
/// Background sources bail immediately to avoid gateway amplification.
/// Matches CC's FOREGROUND_529_RETRY_SOURCES in withRetry.ts.
public let FOREGROUND_529_RETRY_SOURCES: Set<QuerySource> = [
    .repl, .compact, .agent, .skill, .slashCommand, .hook, .sdk
]

// MARK: - Error Types

/// Thrown after 3 consecutive 529 errors when a fallback model is available.
/// Matches CC's FallbackTriggeredError in withRetry.ts.
public final class FallbackTriggeredError: Error, @unchecked Sendable {
    public let originalModel: String
    public let fallbackModel: String

    public init(originalModel: String, fallbackModel: String) {
        self.originalModel = originalModel
        self.fallbackModel = fallbackModel
    }
}

/// Thrown when all retries are exhausted or a non-retryable error occurs.
/// Matches CC's CannotRetryError in withRetry.ts.
public final class CannotRetryError: Error, @unchecked Sendable {
    public let originalError: Error
    public let retryContext: RetryContext

    public init(originalError: Error, retryContext: RetryContext) {
        self.originalError = originalError
        self.retryContext = retryContext
    }
}

// MARK: - Retry Configuration Types

/// Context passed to each retry attempt, allows overriding parameters.
/// Matches CC's RetryContext in withRetry.ts.
public struct RetryContext: Sendable {
    public var maxTokensOverride: Int?
    public var model: String
    public var thinkingConfig: ThinkingConfig
    public var fastMode: Bool

    public init(
        maxTokensOverride: Int? = nil,
        model: String,
        thinkingConfig: ThinkingConfig = .disabled,
        fastMode: Bool = false
    ) {
        self.maxTokensOverride = maxTokensOverride
        self.model = model
        self.thinkingConfig = thinkingConfig
        self.fastMode = fastMode
    }
}

/// Options controlling retry behavior.
/// Matches CC's RetryOptions in withRetry.ts.
public struct RetryOptions: Sendable {
    public var maxRetries: Int
    public var model: String
    public var fallbackModel: String?
    public var thinkingConfig: ThinkingConfig
    public var fastMode: Bool
    public var querySource: QuerySource?
    public var initialConsecutive529Errors: Int

    public init(
        maxRetries: Int = DEFAULT_MAX_RETRIES,
        model: String,
        fallbackModel: String? = nil,
        thinkingConfig: ThinkingConfig = .disabled,
        fastMode: Bool = false,
        querySource: QuerySource? = nil,
        initialConsecutive529Errors: Int = 0
    ) {
        self.maxRetries = maxRetries
        self.model = model
        self.fallbackModel = fallbackModel
        self.thinkingConfig = thinkingConfig
        self.fastMode = fastMode
        self.querySource = querySource
        self.initialConsecutive529Errors = initialConsecutive529Errors
    }
}

// MARK: - Error Detection

/// Detect 529 overloaded errors by HTTP status code or message content.
/// The SDK sometimes fails to properly pass the 529 status code during streaming,
/// so the raw JSON in the error message is checked as a fallback.
/// Matches CC's is529Error() in withRetry.ts.
public func is529Error(_ error: Error) -> Bool {
    // Check LLMError.overloaded (status-based)
    if case LLMError.overloaded = error {
        return true
    }

    // Check LLMError.httpError with 529 status
    if case LLMError.httpError(let status, _) = error, status == 529 {
        return true
    }

    // Check for overloaded_error in error message
    // SDK sometimes fails to propagate 529 status during streaming
    let message = String(describing: error)
    if message.contains("\"type\":\"overloaded_error\"") {
        return true
    }

    return false
}

/// Determine whether an error is retryable.
/// Matches CC's shouldRetry() logic in withRetry.ts.
public func isRetryableError(_ error: Error) -> Bool {
    // 401 (unauthorized) — not retryable
    if case LLMError.unauthorized = error {
        return false
    }

    // 529 overloaded — retryable
    if is529Error(error) {
        return true
    }

    // 429 rate limited — retryable
    if case LLMError.rateLimited = error {
        return true
    }

    // HTTP 5xx — retryable
    if case LLMError.httpError(let status, _) = error, status >= 500 {
        return true
    }

    // Network errors — retryable
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorSecureConnectionFailed:
            return true
        default:
            break
        }
    }

    // Parse errors — maybe retryable (could be transient garbled response)
    if case LLMError.parseError = error {
        return true
    }

    return false
}

/// Check if a background query source should bail immediately on 529.
/// Background sources (summaries, titles, classifiers) bail to avoid
/// 3-10x gateway amplification during capacity cascades.
/// Matches CC's foreground-only 529 retry logic in withRetry.ts.
public func shouldBailOn529(querySource: QuerySource?) -> Bool {
    guard let source = querySource else { return false }
    return !FOREGROUND_529_RETRY_SOURCES.contains(source)
}

// MARK: - Retry Delay Calculation

/// Compute retry delay with exponential backoff and jitter.
/// Matches CC's getRetryDelay() in withRetry.ts.
public func getRetryDelay(
    attempt: Int,
    retryAfterHeader: String? = nil,
    maxDelayMs: Int = 32000
) -> TimeInterval {
    // retry-after header takes priority
    if let header = retryAfterHeader?.trimmingCharacters(in: .whitespaces),
       let seconds = Int(header) {
        return TimeInterval(seconds)
    }

    let baseDelay = min(
        BASE_DELAY_MS * pow(2.0, Double(attempt - 1)),
        Double(maxDelayMs)
    )
    let jitter = Double.random(in: 0...1) * 0.25 * baseDelay
    return (baseDelay + jitter) / 1000.0  // Convert ms to seconds
}

// MARK: - Model Classification

/// Check if a model string represents a non-custom Opus model.
/// Only non-custom Opus models trigger automatic 529→fallback switching.
/// Matches CC's isNonCustomOpusModel() in utils/model/model.ts.
public func isNonCustomOpusModel(_ model: String) -> Bool {
    // Check for canonical first-party Opus model IDs
    let opusPrefixes = [
        "claude-opus-4-0",
        "claude-opus-4-1",
        "claude-opus-4-5",
        "claude-opus-4-6",
    ]
    return opusPrefixes.contains(where: { model.hasPrefix($0) })
}

// MARK: - Legacy RetryPolicy (kept for backward compatibility)

/// Simple exponential backoff retry policy.
/// For CC-matching retry with model fallback, use `sendWithRetry()` on LLMClient.
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitterFactor: Double

    public init(maxRetries: Int = 5, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 32, jitterFactor: Double = 0.25) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }

    /// Execute an async operation with retries and exponential backoff.
    public func execute<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T,
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxRetries - 1, shouldRetry(error) else { throw error }

                let delay = computeDelay(attempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? RetryError.maxRetriesExceeded
    }

    private func computeDelay(attempt: Int) -> TimeInterval {
        let exponential = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
        let jitter = exponential * jitterFactor * Double.random(in: -1...1)
        return max(0, exponential + jitter)
    }
}

public enum RetryError: Error {
    case maxRetriesExceeded
}
