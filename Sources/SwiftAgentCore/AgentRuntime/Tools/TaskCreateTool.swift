import Foundation

/// Creates a task in the agent's task list.
/// Matches Claude Code's TaskCreateTool.
public struct TaskCreateTool: Tool {
    public let name = "TaskCreate"
    public let description = "Create a task in the task list for tracking work progress"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {
        public var subject: String
        public var description: String
        public var activeForm: String?
        public var metadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case subject
            case description
            case activeForm = "activeForm"
            case metadata
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["subject"] = JSONSchemaProperty(type: "string", description: "A brief title for the task")
        schema.properties?["description"] = JSONSchemaProperty(type: "string", description: "What needs to be done")
        schema.properties?["activeForm"] = JSONSchemaProperty(type: "string", description: "Present continuous form for status display")
        schema.properties?["metadata"] = JSONSchemaProperty(type: "object", description: "Arbitrary metadata to attach to the task")
        schema.required = ["subject", "description"]
        return schema
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard !arguments.subject.isEmpty else {
            return .string("Error: subject is required")
        }
        let desc = arguments.description
        let task = await taskManager.create(name: arguments.subject, description: desc)
        return .string("Task created: #\(task.id) - \"\(arguments.subject)\"")
    }
}
