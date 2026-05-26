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
    public var searchHint: String? { "manage the session task checklist" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Update the todo list for the current session. To be used proactively and often to track progress and pending tasks. Make sure that at least one task is in_progress at all times. Always provide both content (imperative) and activeForm (present continuous) for each task." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool { !FeatureFlags.isTodoV2Enabled() }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        var itemSchema = JSONSchema(type: "object", properties: [:])
        itemSchema.properties?["content"] = JSONSchemaProperty(type: "string", description: "The imperative form describing what needs to be done (e.g., \"Run tests\", \"Build the project\")")
        itemSchema.properties?["status"] = JSONSchemaProperty(type: "string", description: "Task status", enum: ["pending", "in_progress", "completed"])
        itemSchema.properties?["activeForm"] = JSONSchemaProperty(type: "string", description: "The present continuous form shown during execution (e.g., \"Running tests\", \"Building the project\")")
        schema.properties?["todos"] = JSONSchemaProperty(type: "array", description: "The updated todo list. Must include ALL tasks — completed, in-progress, and pending. Items removed from the list are permanently deleted.")
        schema.required = ["todos"]
        return schema
    }()

    private let todoStore: TodoStore

    public init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let todosVal = input["todos"], case .array(let todosArr) = todosVal else {
            return ToolResult(content: "Error: todos array is required", isError: true)
        }

        var todoItems: [TodoItem] = []
        for itemVal in todosArr {
            guard case .object(let obj) = itemVal,
                  let contentVal = obj["content"], case .string(let content) = contentVal,
                  let statusVal = obj["status"], case .string(let status) = statusVal,
                  let activeFormVal = obj["activeForm"], case .string(let activeForm) = activeFormVal else {
                return ToolResult(content: "Error: Each todo item must have content, status, and activeForm", isError: true)
            }
            guard ["pending", "in_progress", "completed"].contains(status) else {
                return ToolResult(content: "Error: Invalid status '\(status)'. Must be pending, in_progress, or completed", isError: true)
            }
            guard !content.isEmpty else {
                return ToolResult(content: "Error: Todo content cannot be empty", isError: true)
            }
            guard !activeForm.isEmpty else {
                return ToolResult(content: "Error: Todo activeForm cannot be empty", isError: true)
            }
            todoItems.append(TodoItem(content: content, status: status, activeForm: activeForm))
        }

        let key = context.sessionID
        _ = await todoStore.get(for: key)
        await todoStore.set(for: key, items: todoItems)

        // Check that exactly one task is in_progress
        let inProgress = todoItems.filter { $0.status == "in_progress" }
        if inProgress.count > 1 {
            return ToolResult(content: "Warning: \(inProgress.count) tasks marked as in_progress. You should have exactly ONE task in_progress at a time.")
        }
        if inProgress.isEmpty && !todoItems.isEmpty && !todoItems.allSatisfy({ $0.status == "completed" }) {
            return ToolResult(content: "Warning: No task is in_progress. Mark the task you're working on as in_progress.")
        }

        return ToolResult(content: "Todos have been modified successfully. Ensure that you continue to use the todo list to track your progress. Please proceed with the current tasks if applicable.")
    }
}
