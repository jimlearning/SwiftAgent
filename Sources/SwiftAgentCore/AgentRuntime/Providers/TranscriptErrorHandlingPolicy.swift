import Foundation

// MARK: - TranscriptErrorHandlingPolicy

/// Policy controlling how errors in a Transcript are handled during generation.
/// Mirrors Apple's `TranscriptErrorHandlingPolicy` (FoundationModels, iOS 27+).
public struct TranscriptErrorHandlingPolicy: Sendable {
    /// Strategy for handling tool execution errors in the transcript.
    public enum ToolErrorStrategy: String, Sendable {
        /// Retry the tool call (default behavior).
        case retry
        /// Skip the tool call and continue.
        case skip
        /// Abort the entire turn on any tool error.
        case abort
        /// Report the error to the model and let it decide.
        case reportToModel
    }

    /// Strategy for handling context size exceeded errors.
    public enum ContextOverflowStrategy: String, Sendable {
        /// Truncate the oldest entries to fit.
        case truncateOldest
        /// Compress/summarize older entries.
        case compress
        /// Abort the request.
        case abort
    }

    /// How to handle tool execution errors.
    public var toolErrorStrategy: ToolErrorStrategy

    /// How to handle context window overflow.
    public var contextOverflowStrategy: ContextOverflowStrategy

    /// Maximum number of tool error retries before giving up.
    public var maxToolErrorRetries: Int

    public init(
        toolErrorStrategy: ToolErrorStrategy = .retry,
        contextOverflowStrategy: ContextOverflowStrategy = .truncateOldest,
        maxToolErrorRetries: Int = 3
    ) {
        self.toolErrorStrategy = toolErrorStrategy
        self.contextOverflowStrategy = contextOverflowStrategy
        self.maxToolErrorRetries = maxToolErrorRetries
    }

    /// Default policy: retry tool errors, truncate on overflow, 3 max retries.
    public static let `default` = TranscriptErrorHandlingPolicy()
}
