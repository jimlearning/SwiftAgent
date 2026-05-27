import Foundation

public enum TaskProgressFormatter {
    public static func compact(_ summary: TaskProgressSummary) -> String {
        switch summary.phase {
        case .pending:
            return "pending"
        case .running:
            return trim(summary.lastMessage, taskName: summary.taskName)
        case .thinking:
            return "thinking"
        case .usingTool:
            return trim(summary.lastMessage, taskName: summary.taskName)
        case .writingResults:
            return "writing results"
        case .turnComplete:
            return "turn \(summary.turnCount) complete"
        case .completed:
            return "done"
        case .failed:
            return "failed"
        case .killed:
            return "stopped"
        }
    }

    private static func trim(_ message: String, taskName: String) -> String {
        let prefix = taskName + " "
        let value = message.hasPrefix(prefix) ? String(message.dropFirst(prefix.count)) : message
        return value.count > 80 ? String(value.prefix(77)) + "..." : value
    }
}
