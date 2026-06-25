import Foundation

/// Public tool output type for the Agent Runtime. Replaces ToolResult
/// in the public AgentRuntime API. ContentBlock is NOT exposed — consumers
/// see only String output or structured blocks.
///
/// Named ToolOutputValue to avoid collision with the existing
/// `ToolOutput` discriminated union in Types/Tool.swift.
public enum ToolOutputValue: Sendable {
    /// Plain text output.
    case string(String)

    /// Structured content blocks (provider-agnostic, no Anthropic types).
    case blocks([OutputBlock])
}

// MARK: - OutputBlock

/// A single output block from a tool. Provider-agnostic.
public struct OutputBlock: Sendable {
    /// The type of this output block.
    public let type: OutputBlockType

    /// The content of this output block.
    public let content: String

    public init(type: OutputBlockType, content: String) {
        self.type = type
        self.content = content
    }

    /// Provider-agnostic output block categories.
    public enum OutputBlockType: String, Sendable {
        /// Plain text output.
        case text

        /// Source code block.
        case code

        /// Diff/patch output.
        case diff

        /// Base64-encoded image data.
        case image

        /// Error output (stack traces, diagnostics).
        case error
    }
}
