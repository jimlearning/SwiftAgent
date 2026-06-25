import Foundation

/// Retry decision logic for the Anthropic provider, extracted from RetryPolicy.swift.
/// Handles status code classification (retryable vs non-retryable) and exponential
/// backoff with jitter.
struct AnthropicRetryPolicy: Sendable {

    /// Maximum number of retry attempts.
    static let maxRetries = 10

    /// Base delay in seconds for exponential backoff.
    private static let baseDelaySeconds: TimeInterval = 0.5

    /// Maximum backoff delay in seconds (capped at 60s).
    private static let maxDelaySeconds: TimeInterval = 60.0

    // MARK: - Retry Decision

    /// Determine whether a retry should be attempted for the given status code and attempt number.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code from the API response.
    ///   - attempt: Current attempt number (1-based).
    /// - Returns: `true` if a retry should be attempted.
    static func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        // Guard: max retries exceeded
        guard attempt <= maxRetries else { return false }

        // Non-retryable: authentication errors
        if statusCode == 401 || statusCode == 403 { return false }

        // Non-retryable: bad request
        if statusCode == 400 || statusCode == 413 { return false }

        // Retryable: rate limited
        if statusCode == 429 { return true }

        // Retryable: overloaded
        if statusCode == 529 { return true }

        // Retryable: server errors
        if (500...599).contains(statusCode) { return true }

        return false
    }

    // MARK: - Backoff Delay

    /// Compute the backoff delay for a given attempt using exponential backoff with jitter.
    ///
    /// Formula: `min(2^attempt * base + random(0..1), 60.0)` in seconds.
    ///
    /// - Parameter attempt: Current attempt number (0-based or 1-based).
    /// - Returns: Delay in seconds, or `nil` if the attempt is beyond the max retry limit.
    static func backoffDelay(attempt: Int) -> TimeInterval? {
        guard attempt > 0 else { return nil }

        let exponential = min(
            baseDelaySeconds * pow(2.0, Double(attempt)),
            maxDelaySeconds
        )
        let jitter = Double.random(in: 0...1)
        return exponential + jitter
    }
}
