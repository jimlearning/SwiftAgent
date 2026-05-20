import Foundation

/// Tool result size limits matching Claude Code's constants/toolLimits.ts.
public enum ToolLimits {
    /// Default maximum characters before result is persisted to disk.
    /// CC: DEFAULT_MAX_RESULT_SIZE_CHARS = 50_000
    public static let defaultMaxResultSizeChars = 50_000

    /// Maximum tool result size in tokens.
    /// CC: MAX_TOOL_RESULT_TOKENS = 100_000
    public static let maxToolResultTokens = 100_000

    /// Conservative bytes-per-token estimate.
    /// CC: BYTES_PER_TOKEN = 4
    public static let bytesPerToken = 4

    /// Maximum tool result size in bytes (derived from token limit).
    /// CC: MAX_TOOL_RESULT_BYTES = 400_000
    public static let maxToolResultBytes = maxToolResultTokens * bytesPerToken

    /// Maximum aggregate characters for tool_result blocks within a single user message.
    /// CC: MAX_TOOL_RESULTS_PER_MESSAGE_CHARS = 200_000
    public static let maxToolResultsPerMessageChars = 200_000

    /// Maximum character length for tool summary strings in compact views.
    /// CC: TOOL_SUMMARY_MAX_LENGTH = 50
    public static let toolSummaryMaxLength = 50
}
