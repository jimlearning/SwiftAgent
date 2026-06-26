import Foundation

// MARK: - TodoItem

/// A single todo item in the session task checklist.
/// Matches Claude Code's TodoItemSchema.
public struct TodoItem: Codable, Sendable, Equatable {
    public var content: String
    public var status: String  // "pending" | "in_progress" | "completed"
    public var activeForm: String

    public init(content: String, status: String, activeForm: String) {
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }
}

// MARK: - TodoStore

/// Thread-safe store for session-level todo items.
/// Separate from TaskManager which tracks background processes.
public actor TodoStore {
    private var todos: [String: [TodoItem]] = [:]

    public init() {}

    public func get(for key: String) -> [TodoItem] {
        todos[key] ?? []
    }

    public func set(for key: String, items: [TodoItem]) {
        let allDone = items.allSatisfy { $0.status == "completed" }
        todos[key] = allDone ? [] : items
    }
}

// MARK: - TodoWriteTool

/// Manages the session task checklist.
/// Matches Claude Code's TodoWriteTool.
public struct TodoWriteTool: Tool {
    public let name = "TodoWrite"
    public let description = "Update the todo list for the current session. To be used proactively and often to track progress and pending tasks. Make sure that at least one task is in_progress at all times. Always provide both content (imperative) and activeForm (present continuous) for each task."

    private let todoStore: TodoStore

    public struct Arguments: Codable, Sendable {
        public var todos: [TodoItemArg]

        enum CodingKeys: String, CodingKey {
            case todos
        }
    }

    public struct TodoItemArg: Codable, Sendable {
        public var content: String
        public var status: String
        public var activeForm: String

        enum CodingKeys: String, CodingKey {
            case content
            case status
            case activeForm = "activeForm"
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        var itemSchema = JSONSchema(type: "object", properties: [:])
        itemSchema.properties?["content"] = JSONSchemaProperty(type: "string", description: "The imperative form describing what needs to be done (e.g., \"Run tests\", \"Build the project\")")
        itemSchema.properties?["status"] = JSONSchemaProperty(type: "string", description: "Task status", enum: ["pending", "in_progress", "completed"])
        itemSchema.properties?["activeForm"] = JSONSchemaProperty(type: "string", description: "The present continuous form shown during execution (e.g., \"Running tests\", \"Building the project\")")
        schema.properties?["todos"] = JSONSchemaProperty(type: "array", description: "The updated todo list. Must include ALL tasks — completed, in-progress, and pending. Items removed from the list are permanently deleted.")
        schema.required = ["todos"]
        return schema
    }

    public init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        var todoItems: [TodoItem] = []
        for item in arguments.todos {
            guard !item.content.isEmpty else {
                return .string("Error: Todo content cannot be empty")
            }
            guard !item.activeForm.isEmpty else {
                return .string("Error: Todo activeForm cannot be empty")
            }
            guard ["pending", "in_progress", "completed"].contains(item.status) else {
                return .string("Error: Invalid status '\(item.status)'. Must be pending, in_progress, or completed")
            }
            todoItems.append(TodoItem(content: item.content, status: item.status, activeForm: item.activeForm))
        }

        // Use a placeholder key since we don't have context.sessionID in the new protocol.
        // The TodoStore is session-scoped by the caller.
        let key = "session"
        await todoStore.set(for: key, items: todoItems)

        // Check that exactly one task is in_progress
        let inProgress = todoItems.filter { $0.status == "in_progress" }
        if inProgress.count > 1 {
            return .string("Warning: \(inProgress.count) tasks marked as in_progress. You should have exactly ONE task in_progress at a time.")
        }
        if inProgress.isEmpty && !todoItems.isEmpty && !todoItems.allSatisfy({ $0.status == "completed" }) {
            return .string("Warning: No task is in_progress. Mark the task you're working on as in_progress.")
        }

        return .string("Todos have been modified successfully. Ensure that you continue to use the todo list to track your progress. Please proceed with the current tasks if applicable.")
    }
}
