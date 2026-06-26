import Foundation

/// Retrieves a task by ID.
public struct TaskGetTool: Tool {
    public let name = "TaskGet"
    public let description = "Retrieve a task by its ID"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {
        public var taskId: String

        enum CodingKeys: String, CodingKey {
            case taskId
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The ID of the task to retrieve")
        schema.required = ["taskId"]
        return schema
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard let task = await taskManager.get(arguments.taskId) else {
            return .string("No task found with ID \(arguments.taskId)")
        }
        let summary = task.progressSummary()

        return .string("""
            Task #\(task.id)
            Name: \(task.name)
            Description: \(task.description)
            Status: \(task.status.rawValue)
            Progress: \(TaskProgressFormatter.compact(summary))
            Created: \(task.createdAt)
            \(task.result.map { "Result: \($0)" } ?? "")
            """)
    }
}
