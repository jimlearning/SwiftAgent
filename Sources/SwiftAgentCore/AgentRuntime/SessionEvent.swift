import Foundation

/// Provider-agnostic streaming event model for the Agent Runtime.
///
/// Replaces Anthropic-specific StreamEvent. Every event flowing between
/// the LanguageModelExecutor and the AgentRuntime loop passes through
/// this enum. The "Delta" names are intentional: the values carry
/// ACCUMULATED snapshot totals, not incremental additions — preventing
/// the double-render bug (PITFALLS.md Pitfall 2).
///
/// ## Snapshot Semantics
/// - `textDelta(String)` — complete accumulated text so far
/// - `thinkingDelta(String)` — complete accumulated thinking so far
///
/// Consumers doing `for try await event` receive full snapshots each
/// emission, so they can simply replace their rendered state rather
/// than concatenating deltas.
public enum SessionEvent: Sendable {
    /// Accumulated text snapshot (NOT raw token delta).
    /// The value is the COMPLETE text accumulated so far.
    case textDelta(String)

    /// Accumulated thinking/reasoning snapshot (NOT raw token delta).
    /// Same snapshot semantics as textDelta.
    case thinkingDelta(String)

    /// Model has requested a tool call execution.
    /// - Parameter id: Tool use ID assigned by the model.
    /// - Parameter name: PascalCase tool name (e.g. "Bash").
    /// - Parameter input: JSON-encoded tool arguments as raw Data.
    case toolCallRequested(id: String, name: String, input: Data)

    /// Tool execution finished successfully.
    /// - Parameter id: Tool use ID matching the request.
    /// - Parameter output: ToolOutputValue result from tool execution.
    /// - Parameter isError: Whether the tool execution itself failed (true for tool errors, false for normal output).
    case toolCallCompleted(id: String, output: ToolOutputValue, isError: Bool)

    /// Model signalled end of turn (end_turn, max_tokens, tool_use, etc.).
    /// - Parameter usage: Token counts for this turn (nil if unavailable).
    /// - Parameter stopReason: Model's stop reason string (e.g. "end_turn", "max_tokens", "tool_use").
    case turnCompleted(usage: Usage?, stopReason: String?)

    /// An error occurred during streaming.
    /// Wraps the unified AgentRuntimeError taxonomy.
    case error(AgentRuntimeError)
}
