import Foundation

/// Canonical conversation history with typed entries.
/// Provider-agnostic. Consumed by MemoryStore for persistent memory.
public struct Transcript: Sendable, Codable {
    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Typed transcript entry — each case captures one kind of conversation event.
    public enum Entry: Sendable, Codable {
        /// System-level instruction (e.g., system prompt).
        case instruction(String)

        /// User prompt or message.
        case prompt(String)

        /// Model text response.
        case response(String)

        /// A tool call requested by the model.
        case toolCall(id: String, name: String, input: Data)

        /// Output from a completed tool execution.
        case toolOutput(id: String, output: String, isError: Bool)

        /// Model thinking/reasoning content with optional signature
        /// (opaque token required by thinking mode for multi-turn).
        case thinking(String, signature: String? = nil)

        /// System-level message (e.g., compaction notification).
        case system(String)
    }
}

/// Persistence boundary for agent memory.
/// Used by AgentProfile (plan 01-03) to define how long memory persists.
public enum MemoryScope: Sendable {
    /// Memory scoped to the current session only.
    case session

    /// Memory scoped to the current project.
    case project

    /// Memory persists globally across all projects.
    case global
}
