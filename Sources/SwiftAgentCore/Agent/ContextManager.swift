import Foundation

/// Manages token budgeting, context compaction, and warning levels.
/// Mirrors Claude Code's multi-tier context pressure system.
public struct ContextManager: Sendable {
    public let counter: TokenCounter
    public let modelRegistry: ModelRegistry
    public let compactionThreshold: Double

    public init(
        counter: TokenCounter = TokenCounter(),
        modelRegistry: ModelRegistry = .shared,
        compactionThreshold: Double = 0.85
    ) {
        self.counter = counter
        self.modelRegistry = modelRegistry
        self.compactionThreshold = compactionThreshold
    }

    /// Count tokens for an array of messages.
    public func count(messages: [Message]) -> Int {
        counter.count(messages)
    }

    /// Count tokens for a full conversation.
    public func count(conversation: Conversation) -> Int {
        counter.count(conversation: conversation)
    }

    /// Get the effective context window for a model.
    public func effectiveWindow(for modelID: String) -> Int {
        modelRegistry.effectiveContextWindow(for: modelID)
    }

    /// Check if compaction should be triggered.
    public func shouldCompact(currentTokens: Int, windowSize: Int) -> Bool {
        Double(currentTokens) / Double(windowSize) >= compactionThreshold
    }

    /// Get warning level for current token usage.
    public func warningLevel(current: Int, window: Int) -> TokenWarningLevel {
        counter.warningLevel(currentTokens: current, contextWindow: window)
    }

    /// Estimate tokens remaining before compaction.
    public func tokensUntilCompaction(current: Int, window: Int) -> Int {
        let threshold = Int(Double(window) * compactionThreshold)
        return max(0, threshold - current)
    }

    /// Extract a compacted view: keep first N messages + last N messages.
    /// This is a lightweight microcompact — no API call needed.
    public func microcompact(
        messages: [Message],
        keepFirst: Int = 2,
        keepLast: Int = 4
    ) -> [Message] {
        guard messages.count > keepFirst + keepLast else { return messages }

        var result: [Message] = []
        result.append(contentsOf: messages.prefix(keepFirst))
        result.append(Message(
            type: .user,
            content: [.text("[\(messages.count - keepFirst - keepLast) messages omitted]")]
        ))
        result.append(contentsOf: messages.suffix(keepLast))
        return result
    }

    /// Select compaction strategy based on severity.
    public enum CompactionStrategy {
        case none
        case microcompact
        case fullCompact
        case blocking
    }

    public func selectStrategy(currentTokens: Int, windowSize: Int, consecutiveCompactions: Int) -> CompactionStrategy {
        let ratio = Double(currentTokens) / Double(windowSize)

        if consecutiveCompactions >= 3 { return .blocking }

        switch ratio {
        case ..<0.7: return .none
        case ..<0.85: return .microcompact
        case ..<0.95: return .fullCompact
        default: return .blocking
        }
    }
}
