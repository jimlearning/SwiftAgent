import Foundation

// MARK: - TaskOutputTool

/// Gets output from a running or completed background task.
/// Matches Claude Code's TaskOutputTool.
public struct TaskOutputTool: Tool {
    public let name = "TaskOutput"
    public var aliases: [String] { ["AgentOutputTool", "BashOutputTool"] }
    public var searchHint: String? { "read output/logs from a background task" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Retrieve output from a running or completed background task" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    /// CC: isEnabled returns true for external builds (not ant-internal).
    /// SA mirrors this — TaskOutputTool is always enabled externally.
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] != "ant"
    }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The task ID to get output from")
        schema.properties?["block"] = JSONSchemaProperty(type: "boolean", description: "Whether to wait for completion (default: true)")
        schema.properties?["timeout"] = JSONSchemaProperty(type: "number", description: "Max wait time in ms (default: 30000, max: 600000)")
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

        let shouldBlock: Bool
        if let b = input["block"] {
            if case .bool(let v) = b { shouldBlock = v }
            else if case .string(let s) = b, let v = Bool(s) { shouldBlock = v }
            else { shouldBlock = true }
        } else { shouldBlock = true }

        let timeoutMs: Double
        if let t = input["timeout"] {
            if case .number(let n) = t { timeoutMs = n }
            else if case .string(let s) = t, let n = Double(s) { timeoutMs = n }
            else { timeoutMs = 30000 }
        } else { timeoutMs = 30000 }
        let timeout = min(timeoutMs, 600000) / 1000.0

        guard let task = await taskManager.get(taskId) else {
            return ToolResult(content: "No task found with ID \(taskId)", isError: true)
        }

        // If blocking, wait for completion
        let finalTask: AgentTask
        if shouldBlock && task.status == .running {
            if let waited = await taskManager.waitForCompletion(taskId, timeout: timeout) {
                finalTask = waited
            } else {
                let current = await taskManager.get(taskId)
                let output = current?.output ?? ""
                return ToolResult(content: """
                    {"retrieval_status": "timeout", "task": {"task_id": "\(taskId)", "task_type": "local_bash", "status": "\(current?.status.rawValue ?? "unknown")", "description": "\(current?.description ?? "")", "output": "\(output.replacingOccurrences(of: "\"", with: "\\\""))"}}
                    """)
            }
        } else {
            finalTask = task
        }

        let status = finalTask.status == .completed ? "success" : "not_ready"
        let output = finalTask.output ?? finalTask.result ?? ""

        var parts: [String] = []
        parts.append("\"retrieval_status\": \"\(status)\"")
        parts.append("\"task\": {")
        parts.append("\"task_id\": \"\(finalTask.id)\"")
        parts.append(", \"task_type\": \"local_bash\"")
        parts.append(", \"status\": \"\(finalTask.status.rawValue)\"")
        parts.append(", \"description\": \"\(finalTask.description.replacingOccurrences(of: "\"", with: "\\\""))\"")
        parts.append(", \"output\": \"\(output.replacingOccurrences(of: "\"", with: "\\\""))\"")
        if let exitCode = finalTask.exitCode {
            parts.append(", \"exitCode\": \(exitCode)")
        }
        if let prompt = finalTask.prompt {
            parts.append(", \"prompt\": \"\(prompt.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if let result = finalTask.result {
            parts.append(", \"result\": \"\(result.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if let error = finalTask.error {
            parts.append(", \"error\": \"\(error.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        parts.append("}")

        return ToolResult(content: "{\(parts.joined())}")
    }
}
