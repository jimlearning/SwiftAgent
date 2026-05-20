import Foundation

// MARK: - Constants

/// Tag wrapping persisted tool result content in the message sent to the LLM.
/// Matches CC's PERSISTED_OUTPUT_TAG in utils/toolResultStorage.ts.
public let PERSISTED_OUTPUT_TAG = "<persisted-output>"

/// Closing tag for persisted output.
/// Matches CC's PERSISTED_OUTPUT_CLOSING_TAG.
public let PERSISTED_OUTPUT_CLOSING_TAG = "</persisted-output>"

/// Message replacing tool results cleared during microcompact.
/// Matches CC's TOOL_RESULT_CLEARED_MESSAGE.
public let TOOL_RESULT_CLEARED_MESSAGE = "[Old tool result content cleared]"

/// Default max characters before tool results are persisted to disk.
/// Matches CC's DEFAULT_MAX_RESULT_SIZE_CHARS in constants/toolLimits.ts.
public let DEFAULT_MAX_RESULT_SIZE_CHARS = 50_000

/// Preview size in bytes for persisted output preview.
/// Matches CC's PREVIEW_SIZE_BYTES (2KB).
public let PREVIEW_SIZE_BYTES = 2_000

/// Subdirectory under session dir for persisted tool results.
/// Matches CC's TOOL_RESULTS_SUBDIR.
public let TOOL_RESULTS_SUBDIR = "tool-results"

// MARK: - Persisted Tool Result

/// Metadata about a persisted tool result.
/// Matches CC's PersistedToolResult in utils/toolResultStorage.ts.
public struct PersistedToolResult: Sendable {
    /// Absolute path to the persisted file.
    public let filepath: String
    /// Original content size before persistence.
    public let originalSize: Int
    /// Whether the content was persisted as JSON.
    public let isJson: Bool
    /// Preview text (first ~2KB).
    public let preview: String
    /// Whether there's more content beyond the preview.
    public let hasMore: Bool

    public init(
        filepath: String,
        originalSize: Int,
        isJson: Bool,
        preview: String,
        hasMore: Bool
    ) {
        self.filepath = filepath
        self.originalSize = originalSize
        self.isJson = isJson
        self.preview = preview
        self.hasMore = hasMore
    }
}

/// Error from the persist operation.
public struct PersistToolResultError: Sendable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

// MARK: - ToolResultStorage

/// Handles persisting large tool results to disk and building replacement messages.
/// Matches Claude Code's utils/toolResultStorage.ts.
public enum ToolResultStorage {

    // MARK: - Path Resolution

    /// Resolve the Claude config home directory.
    /// Matches CC's getClaudeConfigHomeDir: ~/.claude or $CLAUDE_CONFIG_DIR.
    public static func getClaudeConfigHomeDir() -> String {
        if let envDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            return (envDir as NSString).standardizingPath
        }
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".claude")
    }

    /// Get the projects directory.
    public static func getProjectsDir() -> String {
        (getClaudeConfigHomeDir() as NSString).appendingPathComponent("projects")
    }

    /// Sanitize a path for use as a directory name.
    /// Matches CC's sanitizePath — replaces `/` with `-`.
    public static func sanitizePath(_ path: String) -> String {
        var sanitized = path
            .replacingOccurrences(of: "/", with: "-")
        if sanitized.hasPrefix("-") {
            sanitized = String(sanitized.dropFirst())
        }
        return sanitized
    }

    /// Get the project directory for a given working directory.
    public static func getProjectDir(cwd: String) -> String {
        (getProjectsDir() as NSString).appendingPathComponent(sanitizePath(cwd))
    }

    /// Get the session directory for the given project and session.
    public static func getSessionDir(cwd: String, sessionId: String) -> String {
        (getProjectDir(cwd: cwd) as NSString).appendingPathComponent(sessionId)
    }

    /// Get the tool results directory.
    public static func getToolResultsDir(cwd: String, sessionId: String) -> String {
        (getSessionDir(cwd: cwd, sessionId: sessionId) as NSString)
            .appendingPathComponent(TOOL_RESULTS_SUBDIR)
    }

    /// Get the path for a specific tool result file.
    public static func getToolResultPath(cwd: String, sessionId: String, toolUseId: String, isJson: Bool) -> String {
        let ext = isJson ? "json" : "txt"
        let dir = getToolResultsDir(cwd: cwd, sessionId: sessionId)
        return (dir as NSString).appendingPathComponent("\(toolUseId).\(ext)")
    }

    /// Ensure the tool results directory exists.
    public static func ensureToolResultsDir(cwd: String, sessionId: String) throws {
        let dir = getToolResultsDir(cwd: cwd, sessionId: sessionId)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: dir) {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Persistence

    /// Persist tool result content to disk when it exceeds the threshold.
    /// Matches CC's persistToolResult() in utils/toolResultStorage.ts.
    public static func persistToolResult(
        content: String,
        toolUseId: String,
        cwd: String,
        sessionId: String
    ) -> PersistedToolResult {
        let isJson = content.trimmingCharacters(in: .whitespaces).hasPrefix("{")
            || content.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        let filepath = getToolResultPath(cwd: cwd, sessionId: sessionId, toolUseId: toolUseId, isJson: isJson)
        let originalSize = content.utf8.count

        do {
            try ensureToolResultsDir(cwd: cwd, sessionId: sessionId)
            try content.write(toFile: filepath, atomically: true, encoding: .utf8)
        } catch {
            // If write fails, return the content inline
            let preview = generatePreview(content, maxBytes: PREVIEW_SIZE_BYTES)
            return PersistedToolResult(
                filepath: filepath,
                originalSize: originalSize,
                isJson: isJson,
                preview: preview,
                hasMore: content.utf8.count > PREVIEW_SIZE_BYTES
            )
        }

        let preview = generatePreview(content, maxBytes: PREVIEW_SIZE_BYTES)
        return PersistedToolResult(
            filepath: filepath,
            originalSize: originalSize,
            isJson: isJson,
            preview: preview,
            hasMore: content.utf8.count > PREVIEW_SIZE_BYTES
        )
    }

    /// Build the replacement message for a persisted tool result.
    /// Matches CC's buildLargeToolResultMessage() in utils/toolResultStorage.ts.
    public static func buildLargeToolResultMessage(result: PersistedToolResult) -> String {
        var message = "\(PERSISTED_OUTPUT_TAG)\n"
        message += "Output too large (\(formatFileSize(result.originalSize))). Full output saved to: \(result.filepath)\n\n"
        message += "Preview (first \(formatFileSize(PREVIEW_SIZE_BYTES))):\n"
        message += result.preview
        message += result.hasMore ? "\n...\n" : "\n"
        message += PERSISTED_OUTPUT_CLOSING_TAG
        return message
    }

    /// Generate a preview of the content at a byte boundary (preferring newline breaks).
    /// Matches CC's generatePreview() in utils/toolResultStorage.ts.
    public static func generatePreview(_ content: String, maxBytes: Int) -> String {
        let data = content.utf8
        if data.count <= maxBytes {
            return content
        }
        // Find the last newline within the maxBytes window
        let prefix = String(data.prefix(maxBytes)) ?? String(content.prefix(maxBytes))
        if let lastNewline = prefix.lastIndex(of: "\n") {
            return String(prefix[..<lastNewline])
        }
        return prefix
    }

    /// Get the effective persistence threshold for a tool.
    /// Matches CC's getPersistenceThreshold() — min(tool.max, DEFAULT_MAX).
    public static func getPersistenceThreshold(declaredMax: Int) -> Int {
        guard declaredMax != Int.max else { return Int.max }
        return min(declaredMax, DEFAULT_MAX_RESULT_SIZE_CHARS)
    }

    /// Check if content should be persisted given a threshold.
    public static func shouldPersist(_ content: String, threshold: Int) -> Bool {
        guard threshold != Int.max else { return false }
        return content.utf8.count > threshold
    }

    // MARK: - Helpers

    /// Format a byte count as a human-readable file size.
    /// Matches CC's formatFileSize().
    public static func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1_048_576 { return String(format: "%.1fKB", Double(bytes) / 1024.0) }
        return String(format: "%.1fMB", Double(bytes) / 1_048_576.0)
    }

    /// Process a tool result, persisting if it exceeds the threshold.
    /// Returns the (possibly replaced) content and a flag indicating whether it was persisted.
    /// Matches CC's processToolResultBlock().
    public static func processToolResult(
        content: String,
        toolName: String,
        maxResultSizeChars: Int,
        toolUseId: String,
        cwd: String,
        sessionId: String
    ) -> (content: String, persisted: Bool, persistPath: String?) {
        let threshold = getPersistenceThreshold(declaredMax: maxResultSizeChars)
        guard shouldPersist(content, threshold: threshold) else {
            return (content, false, nil)
        }

        let result = persistToolResult(
            content: content,
            toolUseId: toolUseId,
            cwd: cwd,
            sessionId: sessionId
        )

        let message = buildLargeToolResultMessage(result: result)
        return (message, true, result.filepath)
    }

    // MARK: - Aggregate Budget Enforcement

    /// Maximum total characters in tool results per user message.
    /// Matches CC's MAX_TOOL_RESULTS_PER_MESSAGE_CHARS in constants/toolLimits.ts.
    public static let maxToolResultsPerMessageChars = 200_000

    /// Enforce aggregate tool result budget: truncates results exceeding total per-message limit.
    /// Matches CC's applyToolResultBudget() in utils/toolResultStorage.ts.
    public static func applyToolResultBudget(
        messages: [Message],
        skipToolNames: Set<String> = []
    ) -> [Message] {
        messages.map { message in
            guard message.type == .user else { return message }

            let blocks = message.content
            var totalChars = 0
            var newBlocks: [ContentBlock] = []

            for block in blocks {
                if case .toolResult(let toolUseID, let content, let isError) = block {
                    // Skip tools that opt out of budget enforcement (e.g., Read with Infinity maxResultSizeChars)
                    // We approximate this by checking skipToolNames
                    let contentStr: String
                    switch content {
                    case .string(let s): contentStr = s
                    default: contentStr = ""
                    }

                    let charCount = contentStr.utf8.count
                    if skipToolNames.contains(toolUseID) {
                        totalChars += charCount
                        newBlocks.append(block)
                    } else if totalChars + charCount > maxToolResultsPerMessageChars {
                        // Truncate: replace with cleared message
                        let remaining = maxToolResultsPerMessageChars - totalChars
                        if remaining > 0 {
                            let truncated = String(contentStr.prefix(remaining)) + "\n...\n\(TOOL_RESULT_CLEARED_MESSAGE)"
                            newBlocks.append(.toolResult(toolUseID: toolUseID, content: .string(truncated), isError: isError))
                            totalChars = maxToolResultsPerMessageChars
                        }
                        // If no room, drop the block entirely
                    } else {
                        totalChars += charCount
                        newBlocks.append(block)
                    }
                } else {
                    newBlocks.append(block)
                }
            }

            return Message(type: .user, content: newBlocks)
        }
    }
}
