import Foundation

/// Updates a task's status or fields.
public struct TaskUpdateTool: Tool {
    public let name = "TaskUpdate"
    public var searchHint: String? { "update a task" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Update a task's status, description, or metadata" }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
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
    }()

    private let taskManager: TaskManager

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let idVal = input["taskId"], case .string(let taskId) = idVal else {
            return ToolResult(content: "Error: taskId is required", isError: true)
        }

        if let statusVal = input["status"], case .string(let newStatus) = statusVal {
            switch newStatus {
            case "in_progress":
                await taskManager.markRunning(taskId)
                return ToolResult(content: "Task #\(taskId) marked as running")
            case "completed":
                await taskManager.markCompleted(taskId, result: "Task completed")
                return ToolResult(content: "Task #\(taskId) completed")
            case "deleted":
                await taskManager.kill(taskId)
                return ToolResult(content: "Task #\(taskId) deleted")
            default: break
            }
        }

        return ToolResult(content: "No valid update specified for task #\(taskId)")
    }
}
