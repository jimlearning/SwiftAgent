import Foundation

/// Approximate token counter using character/word heuristics.
/// For production, integrate with a proper tokenizer (e.g., tiktoken).
public struct TokenCounter: Sendable {
    /// Rough estimate: ~4 characters per token for English text.
    private let charsPerToken: Double = 4.0

    public init() {}

    /// Estimate token count for a string.
    public func count(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.utf16.count) / charsPerToken)))
    }

    /// Estimate token count for a message.
    public func count(_ message: Message) -> Int {
        message.content.reduce(0) { total, block in
            switch block {
            case .text(let text):
                return total + count(text)
            case .toolUse, .serverToolUse:
                return total + 50  // rough overhead for tool_use blocks
            case .toolResult(_, let content, _):
                switch content {
                case .string(let str): return total + count(str)
                case .blocks(let blocks):
                    return total + blocks.reduce(0) { acc, block in
                        switch block {
                        case .text(let text): return acc + count(text)
                        default: return acc + 50
                        }
                    }
                }
            case .image:
                return total + 100  // rough overhead for image blocks
            case .thinking(let text, _, _):
                return total + count(text)
            case .redactedThinking:
                return total + 50  // rough overhead for redacted thinking
            case .document:
                return total + 100  // rough overhead for document blocks
            case .toolReference:
                return total + 30   // tool reference metadata overhead
            }
        }
    }

    /// Estimate total token count for an array of messages.
    public func count(_ messages: [Message]) -> Int {
        messages.reduce(0) { $0 + count($1) }
    }

    /// Estimate total token count for a conversation including system prompt.
    public func count(conversation: Conversation) -> Int {
        var total = 0
        if let prompt = conversation.systemPrompt {
            total += count(prompt)
        }
        total += count(conversation.messages.filter { $0.type != .system })
        return total
    }

    /// Check if adding `additionalTokens` would exceed `contextWindow`.
    public func wouldExceedContext(
        currentTokens: Int,
        additionalTokens: Int,
        contextWindow: Int
    ) -> Bool {
        (currentTokens + additionalTokens) > contextWindow
    }

    /// Get the token warning level (green/yellow/orange/red).
    public func warningLevel(currentTokens: Int, contextWindow: Int) -> TokenWarningLevel {
        let ratio = Double(currentTokens) / Double(contextWindow)
        switch ratio {
        case ..<0.5: return .green
        case ..<0.75: return .yellow
        case ..<0.9: return .orange
        default: return .red
        }
    }
}

public enum TokenWarningLevel: String, Sendable {
    case green
    case yellow
    case orange
    case red
}
