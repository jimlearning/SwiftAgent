import Foundation
import SwiftAgentCore

// MARK: - ThreadMessage (Backward Compatibility)

/// Backward-compatible wrapper around `AgentMessage`.
///
/// The existing UI layer (`MessageBubbleView`, `MessageListView`, `ComposerView`)
/// references `ThreadMessage` with simple `role`/`content`/`isStreaming`/`reasoningContent`
/// properties. This shim bridges the old flat model to the new block-based `AgentMessage`.
///
/// **Deprecated**: New code should use `AgentMessage` directly. This type exists
/// only to avoid rewriting all UI files in one pass.
public struct ThreadMessage: Identifiable, Equatable {
    /// The underlying agent message.
    public var agentMessage: AgentMessage

    // MARK: - Flat accessors (backward compat)

    public var id: String { agentMessage.displayID }
    public var role: MessageRole {
        switch agentMessage.role {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
    }
    public var content: String {
        get {
            // Flatten text blocks into a single string
            agentMessage.blocks.compactMap { block in
                if case .text(let text) = block { return text }
                return nil
            }.joined()
        }
        set {
            // Replace all text blocks with a single one
            let nonTextBlocks = agentMessage.blocks.filter { block in
                if case .text = block { return false }
                return true
            }
            if newValue.isEmpty {
                agentMessage.blocks = nonTextBlocks
            } else {
                agentMessage.blocks = nonTextBlocks + [.text(newValue)]
            }
        }
    }
    public var reasoningContent: String? {
        get {
            let thinking = agentMessage.blocks.compactMap { block -> String? in
                if case .thinking(let text, _) = block { return text }
                return nil
            }.joined()
            return thinking.isEmpty ? nil : thinking
        }
        set {
            let nonThinkingBlocks = agentMessage.blocks.filter { block in
                if case .thinking = block { return false }
                return true
            }
            if let rc = newValue, !rc.isEmpty {
                agentMessage.blocks = nonThinkingBlocks + [.thinking(rc)]
            } else {
                agentMessage.blocks = nonThinkingBlocks
            }
        }
    }
    public var isStreaming: Bool {
        get { agentMessage.isStreaming }
        set { agentMessage.isStreaming = newValue }
    }
    public var tokenCount: Int { 0 } // Deprecated; use tokenUsage

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String = "",
        reasoningContent: String? = nil,
        isStreaming: Bool = false,
        tokenCount: Int = 0
    ) {
        let agentRole: AgentMessageRole
        switch role {
        case .user: agentRole = .user
        case .assistant: agentRole = .assistant
        default: agentRole = .system
        }

        var blocks: [AgentMessageBlock] = []
        if !content.isEmpty { blocks.append(.text(content)) }
        if let rc = reasoningContent, !rc.isEmpty { blocks.append(.thinking(rc)) }

        self.agentMessage = AgentMessage(
            id: id,
            role: agentRole,
            blocks: blocks,
            isStreaming: isStreaming
        )
    }

    /// Wrap an existing AgentMessage.
    public init(_ agentMessage: AgentMessage) {
        self.agentMessage = agentMessage
    }
}

// MARK: Array bridging

extension Array where Element == ThreadMessage {
    /// Convert to AgentMessage array.
    public var asAgentMessages: [AgentMessage] {
        map(\.agentMessage)
    }
}

extension Array where Element == AgentMessage {
    /// Convert to ThreadMessage array (for backward compat).
    public var asThreadMessages: [ThreadMessage] {
        map { ThreadMessage($0) }
    }
}

// MARK: - ReasoningStrength (retained for model picker UI)

/// Reasoning strength for the model picker menu (per §5.7, §11.5).
public enum ReasoningStrength: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case extraHigh = "Extra High"
}
