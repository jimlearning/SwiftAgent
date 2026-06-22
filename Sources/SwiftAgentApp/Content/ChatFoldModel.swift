import Foundation

// MARK: - FoldTarget

/// Identifies a foldable entity within a chat message.
/// Supports multiple levels: thinking blocks, individual tool calls,
/// tool-result pairs, and entire message groups.
public enum FoldTarget: Hashable, Sendable {
    /// A thinking/reasoning block within a message.
    case thinking(messageID: String, blockIndex: Int)
    /// A single tool-use block.
    case toolUse(messageID: String, toolUseID: String)
    /// A tool-result block. Keyed only by toolUseID so the tool card
    /// and the result block agree on the same fold target regardless of
    /// which message they belong to.
    case toolResult(toolUseID: String)
    /// An entire turn (user + assistant + tools together).
    case turn(messageID: String)
    /// The entire message (all blocks collapsed).
    case message(messageID: String)
}

// MARK: - FoldState

/// Tracks the collapsed/expanded state of each foldable target.
/// Not thread-safe — must be accessed on @MainActor.
@MainActor
public final class FoldState: ObservableObject {
    @Published public private(set) var collapsed: Set<FoldTarget> = []

    public init() {}

    public func isCollapsed(_ target: FoldTarget) -> Bool {
        collapsed.contains(target)
    }

    public func toggle(_ target: FoldTarget) {
        if collapsed.contains(target) {
            collapsed.remove(target)
        } else {
            collapsed.insert(target)
        }
    }

    public func collapse(_ target: FoldTarget) {
        collapsed.insert(target)
    }

    public func expand(_ target: FoldTarget) {
        collapsed.remove(target)
    }

    public func reset() {
        collapsed.removeAll()
    }
}

// MARK: - Auto-Collapse Policy

/// Determines when blocks should auto-collapse based on conversation progress.
///
/// Inspired by Codex App behaviour:
/// - Tool results older than 2 turns auto-collapse
/// - Tool calls older than 3 turns auto-collapse unless they have errors
/// - Thinking blocks auto-collapse after the assistant response is complete
public struct AutoCollapsePolicy {
    /// Number of messages past which tool results auto-collapse.
    public var toolResultAgeThreshold: Int = 2
    /// Number of messages past which tool calls auto-collapse.
    public var toolCallAgeThreshold: Int = 3
    /// Whether to auto-collapse thinking when assistant finishes.
    public var autoCollapseThinking: Bool = true
    /// Minimum lines in a tool result before it's eligible for auto-collapse.
    public var minToolResultLines: Int = 5

    public init() {}
}

// MARK: - Auto-Collapse Engine

/// Applies the auto-collapse policy to a list of messages,
/// returning the set of targets that should be collapsed.
public struct AutoCollapseEngine {

    public let policy: AutoCollapsePolicy

    public init(policy: AutoCollapsePolicy = AutoCollapsePolicy()) {
        self.policy = policy
    }

    /// Compute which targets should be collapsed given the current message list.
    /// - Parameter messages: All messages in display order.
    /// - Parameter currentFoldState: The existing fold state (already-collapsed items stay collapsed).
    /// - Returns: Updated set of collapsed targets.
    public func computeCollapsed(
        messages: [AgentMessage],
        currentFoldState: Set<FoldTarget>
    ) -> Set<FoldTarget> {
        var collapsed = currentFoldState

        guard messages.count > policy.toolCallAgeThreshold else { return collapsed }

        let totalMessages = messages.count

        for (msgIndex, message) in messages.enumerated() {
            let distanceFromEnd = totalMessages - msgIndex - 1

            // Auto-collapse thinking after assistant finishes
            if policy.autoCollapseThinking && !message.isStreaming {
                for (blockIndex, block) in message.blocks.enumerated() {
                    if case .thinking = block {
                        let target = FoldTarget.thinking(messageID: message.id, blockIndex: blockIndex)
                        collapsed.insert(target)
                    }
                }
            }

            // Auto-collapse tool results older than threshold
            if distanceFromEnd >= policy.toolResultAgeThreshold {
                for block in message.blocks {
                    if case .toolResult(let result) = block {
                        let lineCount = result.content.components(separatedBy: "\n").count
                        if lineCount >= policy.minToolResultLines {
                            let target = FoldTarget.toolResult(toolUseID: result.toolUseID)
                            collapsed.insert(target)
                        }
                    }
                }
            }

            // Auto-collapse tool calls older than threshold (unless they have errors)
            if distanceFromEnd >= policy.toolCallAgeThreshold {
                for block in message.blocks {
                    if case .toolUse(let toolUse) = block {
                        // Don't auto-collapse tools with errors
                        if case .completed = toolUse.status {
                            let target = FoldTarget.toolUse(messageID: message.id, toolUseID: toolUse.toolUseID)
                            collapsed.insert(target)
                        }
                    }
                }
            }
        }

        return collapsed
    }
}
