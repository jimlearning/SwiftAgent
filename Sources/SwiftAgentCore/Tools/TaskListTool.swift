import Foundation

/// Lists all tasks.
public struct TaskListTool: Tool {
    public let name = "TaskList"
    public var searchHint: String? { "list all tasks" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "List all tracked tasks and their statuses" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool { FeatureFlags.isTodoV2Enabled() }
    public let inputSchema = JSONSchema(type: "object", properties: [:])

    private let taskManager: TaskManager

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let tasks = await taskManager.listAll()
        if tasks.isEmpty {
            return ToolResult(content: "No tasks.")
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
            output += "\(icon) #\(task.id) \(task.name) (\(task.status.rawValue))\n"
        }
        return ToolResult(content: output)
    }
}
