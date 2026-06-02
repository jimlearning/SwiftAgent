import Foundation

/// Creates a task in the agent's task list.
/// Matches Claude Code's TaskCreateTool.
public struct TaskCreateTool: Tool {
    public let name = "TaskCreate"
    public var searchHint: String? { "create a task in the task list" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Create a task in the task list for tracking work progress" }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool { FeatureFlags.isTodoV2Enabled() }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["subject"] = JSONSchemaProperty(type: "string", description: "A brief title for the task")
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "What needs to be done")
        schema.properties?["activeForm"] = JSONSchemaProperty(type: "string", description: "Present continuous form for status display")
        schema.properties?["metadata"] = JSONSchemaProperty(type: "object", description: "Arbitrary metadata to attach to the task")
        schema.required = ["subject", "description"]
        return schema
    }()

    private let taskManager: TaskManager

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let subjectVal = input["subject"], case .string(let subject) = subjectVal else {
            return ToolResult(content: "Error: subject is required", isError: true)
        }
        let description: String
        if let d = input["description"], case .string(let s) = d { description = s }
        else { description = "" }
        let task = await taskManager.create(name: subject, description: description)
        return ToolResult(content: "Task created: #\(task.id) - \"\(subject)\"")
    }
}
