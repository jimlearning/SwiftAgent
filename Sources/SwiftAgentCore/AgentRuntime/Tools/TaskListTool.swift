import Foundation

/// Lists all tasks.
public struct TaskListTool: Tool {
    public let name = "TaskList"
    public let description = "List all tracked tasks and their statuses"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {}

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let tasks = await taskManager.listAll()
        if tasks.isEmpty {
            return .string("No tasks.")
        }

        var output = ""
        for task in tasks {
            let icon: String = {
                switch task.status {
                case .pending: return "[ ]"
                case .running: return "[>]"
                case .completed: return "[x]"
                case .failed: return "[!]"
                case .killed: return "[-]"
                }
            }()
            let summary = task.progressSummary()
            output += "\(icon) #\(task.id) \(task.name) (\(task.status.rawValue)) — \(TaskProgressFormatter.compact(summary))\n"
        }
        return .string(output)
    }
}
