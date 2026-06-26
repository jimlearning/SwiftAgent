import Foundation

// MARK: - InterruptBehavior

/// Controls behavior when user submits input during tool execution.
/// Matches Claude Code's interruptBehavior(): 'cancel' | 'block'.
public enum InterruptBehavior: String, Sendable {
    /// Stop the tool and discard its result.
    case cancel
    /// Keep running; the new message waits.
    case block
}
