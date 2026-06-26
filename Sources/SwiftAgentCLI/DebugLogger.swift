import Foundation
import SwiftAgentCore

/// Debug logger for CLI sessions.
///
/// Writes plain-text debug logs to `~/.swift-agent/debug/<session-id>.txt`
/// in CC-compatible format.
public final class DebugLogger: @unchecked Sendable {
    private let sessionLog: SessionDebugLog
    private let sessionID: String

    /// Initialize for a specific session.
    /// - Parameter sessionId: The session UUID. Defaults to a timestamp-based ID.
    public init(sessionId: String? = nil) {
        let sid: String
        if let sessionId {
            sid = sessionId
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            sid = formatter.string(from: Date())
        }
        self.sessionID = sid
        self.sessionLog = SessionDebugLog(sessionId: sid)
    }

    // MARK: - DebugLogSink

    public func debug(_ message: String, category: String = "general") {
        sessionLog.debug(message, category: category)
    }

    public func warn(_ message: String, category: String = "general") {
        sessionLog.warn(message, category: category)
    }

    public func error(_ message: String, category: String = "general") {
        sessionLog.error(message, category: category)
    }

    // MARK: - LLMDebugLogger (legacy, for LLMClient)

    public func logRequest(url: String, method: String, headers: [String: String], body: String) {
        let safeBody = body.count > 500 ? String(body.prefix(500)) + "..." : body
        debug("\(method) \(url) body=\(safeBody)", category: "API:request")
    }

    public func logResponse(status: Int, headers: [String: String]) {
        debug("status=\(status)", category: "API:response")
    }

    public func logStreamEvent(_ rawJSON: String) {
        let truncated = rawJSON.count > 200 ? String(rawJSON.prefix(200)) + "..." : rawJSON
        debug("event: \(truncated)", category: "API:stream")
    }

    public func logError(_ error: Error) {
        self.error(error.localizedDescription, category: "API:error")
    }

    public func logResponseBody(_ body: String) {
        let truncated = body.count > 500 ? String(body.prefix(500)) + "..." : body
        debug("body: \(truncated)", category: "API:response")
    }

    // MARK: - Convenience Methods

    /// Log a general info message.
    public func logInfo(_ message: String) {
        debug(message, category: "general")
    }

    /// Log token usage with cache metrics after a turn completes.
    public func logUsage(inputTokens: Int, outputTokens: Int,
                         cacheRead: Int, cacheCreation: Int,
                         cache1h: Int = 0, cache5m: Int = 0) {
        let comparableInputTokens = inputTokens + cacheRead + cacheCreation
        let cacheHitRate = comparableInputTokens > 0
            ? Double(cacheRead) / Double(comparableInputTokens) * 100.0 : 0.0
        let msg = "input=\(inputTokens) output=\(outputTokens) cacheRead=\(cacheRead) cacheCreation=\(cacheCreation) cacheHitRate=\(String(format: "%.1f", cacheHitRate))%"
        debug(msg, category: "API:usage")
    }

    /// Path to the current log file, for display to the user.
    public var logFilePath: String {
        sessionLog.path
    }
}
