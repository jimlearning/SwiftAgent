import Foundation

/// Stops/kills a running background task.
public struct TaskStopTool: Tool {
    public let name = "TaskStop"
    public let description = "Stop a running background task"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {
        public var taskId: String?
        public var shellId: String?

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case shellId = "shell_id"
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["task_id"] = JSONSchemaProperty(type: "string", description: "The ID of the task to stop")
        schema.properties?["shell_id"] = JSONSchemaProperty(type: "string", description: "Shell ID for backward compatibility")
        return schema
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let taskId: String
        if let id = arguments.taskId {
            taskId = id
        } else if let id = arguments.shellId {
            taskId = id
        } else {
            return .string("Error: task_id is required")
        }

        guard let task = await taskManager.get(taskId) else {
            return .string("No task found with ID \(taskId)")
        }
        guard task.status == .running else {
            return .string("Task #\(taskId) is not running (status: \(task.status.rawValue))")
        }

        await taskManager.kill(taskId)
        return .string("Task #\(taskId) (\"\(task.name)\") stopped")
    }
}
