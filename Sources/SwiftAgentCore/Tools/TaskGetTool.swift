import Foundation

/// Retrieves a task by ID.
public struct TaskGetTool: Tool {
    public let name = "TaskGet"
    public var searchHint: String? { "retrieve a task by ID" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Retrieve a task by its ID" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The ID of the task to retrieve")
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

        guard let task = await taskManager.get(taskId) else {
            return ToolResult(content: "No task found with ID \(taskId)")
        }

        return ToolResult(content: """
            Task #\(task.id)
            Name: \(task.name)
            Description: \(task.description)
            Status: \(task.status.rawValue)
            Created: \(task.createdAt)
            \(task.result.map { "Result: \($0)" } ?? "")
            """)
    }
}
