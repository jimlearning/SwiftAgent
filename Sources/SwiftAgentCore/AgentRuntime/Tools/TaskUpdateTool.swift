import Foundation

/// Updates a task's status or fields.
public struct TaskUpdateTool: Tool {
    public let name = "TaskUpdate"
    public let description = "Update a task's status, description, or metadata"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {
        public var taskId: String
        public var status: String?
        public var subject: String?
        public var description: String?
        public var activeForm: String?
        public var addBlocks: [String]?
        public var addBlockedBy: [String]?
        public var owner: String?
        public var metadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case taskId
            case status
            case subject
            case description
            case activeForm = "activeForm"
            case addBlocks
            case addBlockedBy
            case owner
            case metadata
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The ID of the task to update")
        schema.properties?["status"] = JSONSchemaProperty(type: "string", description: "New status", enum: ["pending", "in_progress", "completed", "deleted"])
        schema.properties?["subject"] = JSONSchemaProperty(type: "string", description: "New subject for the task")
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "New description")
        schema.properties?["activeForm"] = JSONSchemaProperty(type: "string", description: "Present continuous form shown in spinner when in_progress")
        schema.properties?["addBlocks"] = JSONSchemaProperty(type: "array", description: "Task IDs that this task blocks")
        schema.properties?["addBlockedBy"] = JSONSchemaProperty(type: "array", description: "Task IDs that block this task")
        schema.properties?["owner"] = JSONSchemaProperty(type: "string", description: "New owner for the task")
        schema.properties?["metadata"] = JSONSchemaProperty(type: "object", description: "Arbitrary metadata keys to merge into the task")
        schema.required = ["taskId"]
        return schema
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let taskId = arguments.taskId

        if let newStatus = arguments.status {
            switch newStatus {
            case "in_progress":
                await taskManager.markRunning(taskId)
                return .string("Task #\(taskId) marked as running")
            case "completed":
                await taskManager.markCompleted(taskId, result: "Task completed")
                return .string("Task #\(taskId) completed")
            case "deleted":
                await taskManager.kill(taskId)
                return .string("Task #\(taskId) deleted")
            default: break
            }
        }

        return .string("No valid update specified for task #\(taskId)")
    }
}
