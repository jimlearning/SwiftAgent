import Foundation

/// Stops/kills a running background task.
public struct TaskStopTool: Tool {
    public let name = "TaskStop"
    public var searchHint: String? { "kill a running background task" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Stop a running background task" }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The ID of the task to stop")
        schema.required = ["taskId"]
        return schema
    }()

    private let taskManager: TaskManager

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let taskId: String
        if let idVal = input["taskId"], case .string(let id) = idVal {
            taskId = id
        } else {
            return ToolResult(content: "Error: taskId is required", isError: true)
        }

        guard let task = await taskManager.get(taskId) else {
            return ToolResult(content: "No task found with ID \(taskId)", isError: true)
        }
        guard task.status == .running else {
            return ToolResult(content: "Task #\(taskId) is not running (status: \(task.status.rawValue))", isError: true)
        }

        await taskManager.kill(taskId)
        return ToolResult(content: "Task #\(taskId) (\"\(task.name)\") stopped")
    }
}
