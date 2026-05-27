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

        // If blocking, wait for completion while surfacing live background progress.
        let finalSnapshot: TaskProgressSnapshot?
        if shouldBlock && task.status == .running {
            finalSnapshot = await waitForCompletionWithProgress(
                taskId: taskId,
                timeout: timeout,
                toolUseID: context.toolUseID ?? "TaskOutput",
                onProgress: onProgress
            )
            if finalSnapshot == nil {
                let current = await taskManager.progressSnapshot(taskId)
                return ToolResult(content: responseJSON(
                    retrievalStatus: "timeout",
                    snapshot: current,
                    fallbackTaskId: taskId
                ))
            }
        } else {
            finalSnapshot = await taskManager.progressSnapshot(taskId)
        }

        let finalTask = finalSnapshot?.task ?? task

        let status: String
        if shouldBlock && task.status == .running && finalTask.status == .running {
            status = "timeout"
        } else {
            status = finalTask.status == .completed ? "success" : "not_ready"
        }

        return ToolResult(content: responseJSON(retrievalStatus: status, snapshot: finalSnapshot))
    }

    private func waitForCompletionWithProgress(
        taskId: String,
        timeout: TimeInterval,
        toolUseID: String,
        onProgress: ToolCallProgress?
    ) async -> TaskProgressSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastProgressEmit = Date.distantPast

        while Date() < deadline {
            guard let snapshot = await taskManager.progressSnapshot(taskId) else {
                return nil
            }

            let now = Date()
            if now.timeIntervalSince(lastProgressEmit) >= 0.5 {
                emitProgress(snapshot: snapshot, toolUseID: toolUseID, onProgress: onProgress)
                lastProgressEmit = now
            }

            switch snapshot.task.status {
            case .completed, .failed, .killed:
                emitProgress(snapshot: snapshot, toolUseID: toolUseID, onProgress: onProgress)
                return snapshot
            case .pending, .running:
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        if let snapshot = await taskManager.progressSnapshot(taskId) {
            emitProgress(snapshot: snapshot, toolUseID: toolUseID, onProgress: onProgress)
        }
        return nil
    }

    private func emitProgress(
        snapshot: TaskProgressSnapshot,
        toolUseID: String,
        onProgress: ToolCallProgress?
    ) {
        onProgress?(ToolProgress(
            toolUseID: toolUseID,
            data: TaskOutputProgressData(summary: snapshot.summary, recentEvents: snapshot.recentEvents)
        ))
    }

    private func responseJSON(
        retrievalStatus: String,
        snapshot: TaskProgressSnapshot?,
        fallbackTaskId: String? = nil
    ) -> String {
        let task = snapshot?.task
        var taskObject: [String: Any] = [
            "task_id": task?.id ?? fallbackTaskId ?? "",
            "task_type": task?.type.rawValue ?? TaskType.localWorkflow.rawValue,
            "status": task?.status.rawValue ?? "unknown",
            "description": task?.description ?? "",
            "output": task?.output ?? "",
        ]

        if let exitCode = task?.exitCode {
            taskObject["exitCode"] = exitCode
        }
        if let prompt = task?.prompt {
            taskObject["prompt"] = prompt
        }
        if let result = task?.result {
            taskObject["result"] = result
        }
        if let error = task?.error {
            taskObject["error"] = error
        }

        let payload: [String: Any] = [
            "retrieval_status": retrievalStatus,
            "progress_summary": snapshot.map(Self.summaryJSON) ?? [:],
            "recent_events": snapshot?.recentEvents.map(Self.eventJSON) ?? [],
            "task": taskObject,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return #"{"retrieval_status":"not_ready","task":{"task_id":"","task_type":"local_workflow","status":"unknown","description":"","output":""}}"#
        }
        return string
    }

    private static func summaryJSON(_ snapshot: TaskProgressSnapshot) -> [String: Any] {
        let summary = snapshot.summary
        var object: [String: Any] = [
            "task_id": summary.taskId,
            "task_name": summary.taskName,
            "description": summary.description,
            "status": summary.status.rawValue,
            "phase": summary.phase.rawValue,
            "last_message": summary.lastMessage,
            "turn_count": summary.turnCount,
            "completed_tool_count": summary.completedToolCount,
            "updated_at": summary.updatedAt.timeIntervalSince1970,
        ]
        if let currentTool = summary.currentTool {
            object["current_tool"] = currentTool
        }
        return object
    }

    private static func eventJSON(_ event: TaskProgressEvent) -> [String: Any] {
        var object: [String: Any] = [
            "id": event.id,
            "task_id": event.taskId,
            "task_name": event.taskName,
            "phase": event.phase.rawValue,
            "message": event.message,
            "timestamp": event.timestamp.timeIntervalSince1970,
        ]
        if let toolName = event.toolName {
            object["tool_name"] = toolName
        }
        if let turnNumber = event.turnNumber {
            object["turn_number"] = turnNumber
        }
        if let toolCallCount = event.toolCallCount {
            object["tool_call_count"] = toolCallCount
        }
        return object
    }
}

public struct TaskOutputProgressData: ToolProgressData {
    public let type = "task_output"
    public let summary: TaskProgressSummary
    public let recentEvents: [TaskProgressEvent]

    public init(summary: TaskProgressSummary, recentEvents: [TaskProgressEvent]) {
        self.summary = summary
        self.recentEvents = recentEvents
    }

    public var displayMessage: String {
        "\(summary.taskName) \(TaskOutputProgressData.phaseLabel(summary))"
    }

    private static func phaseLabel(_ summary: TaskProgressSummary) -> String {
        switch summary.phase {
        case .pending:
            return "pending"
        case .running:
            return summary.lastMessage
        case .thinking:
            return "thinking"
        case .usingTool:
            return "using \(summary.currentTool ?? "tool")"
        case .writingResults:
            return "writing results"
        case .turnComplete:
            return "turn \(summary.turnCount) complete"
        case .completed:
            return "done"
        case .failed:
            return "failed"
        case .killed:
            return "stopped"
        }
    }
}
