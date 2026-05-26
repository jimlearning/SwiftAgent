import Foundation
import SwiftAgentCore

/// Structured debug logger for LLM API interactions.
/// Writes timestamped JSON log files to ~/.swift-agent/logs/.
/// Masks sensitive data (API keys) in the output.
public final class DebugLogger: LLMDebugLogger, @unchecked Sendable {
    private let logDir: URL
    private let sessionID: String
    private let logFile: URL
    private var entryCount = 0

    public init(logDir: URL? = nil) {
        let dir = logDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        self.sessionID = timestamp

        self.logDir = dir
        self.logFile = dir.appendingPathComponent("debug-\(timestamp).jsonl")
    }

    /// Log the outgoing API request.
    public func logRequest(url: String, method: String, headers: [String: String], body: String) {
        entryCount += 1
        let safeHeaders = maskSensitiveHeaders(headers)
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "request",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "url": url,
            "method": method,
            "headers": safeHeaders,
            "body": body
        ]
        append(entry)
    }

    /// Log the HTTP response status and headers.
    public func logResponse(status: Int, headers: [String: String]) {
        entryCount += 1
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "response",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "status": status,
            "headers": headers
        ]
        append(entry)
    }

    /// Log a raw response body (error cases).
    public func logResponseBody(_ body: String) {
        entryCount += 1
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "response_body",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "body": body
        ]
        append(entry)
    }

    /// Log a single SSE stream event.
    public func logStreamEvent(_ rawJSON: String) {
        entryCount += 1
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "stream_event",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "raw": rawJSON
        ]
        append(entry)
    }

    /// Log an error during the API interaction.
    public func logError(_ error: Error) {
        entryCount += 1
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "error",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "error": String(describing: error),
            "localizedDescription": error.localizedDescription
        ]
        append(entry)
    }

    /// Log a general info message.
    public func logInfo(_ message: String) {
        entryCount += 1
        let entry: [String: Any] = [
            "seq": entryCount,
            "type": "info",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "message": message
        ]
        append(entry)
    }

    /// Path to the current log file, for display to the user.
    public var logFilePath: String {
        logFile.path
    }

    // MARK: - Private

    private let writeQueue = DispatchQueue(label: "com.swiftagent.debuglogger", qos: .utility)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private func append(_ dict: [String: Any]) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            let captured = dict
            let jsonObj = captured.mapValues { $0 as Any }
            guard JSONSerialization.isValidJSONObject(jsonObj),
                  let data = try? JSONSerialization.data(withJSONObject: jsonObj) else { return }
            var line = data
            line.append(10) // newline (JSONL format)
            if let handle = try? FileHandle(forWritingTo: self.logFile) {
                _ = try? handle.seekToEndCompat()
                try? handle.write(contentsOf: line)
                try? handle.close()
            } else {
                try? line.write(to: self.logFile, options: .atomic)
            }
        }
    }

    private func maskSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        var safe = headers
        for key in ["x-api-key", "authorization", "api-key"] {
            if let value = safe[key], value.count > 8 {
                safe[key] = String(value.prefix(8)) + "..." + String(value.suffix(4))
            }
        }
        return safe
    }
}

// MARK: - FileHandle seekToEnd compatibility

extension FileHandle {
    func seekToEndCompat() throws {
        if #available(macOS 10.15.4, *) {
            try seekToEnd()
        } else {
            seekToEndOfFile()
        }
    }
}
