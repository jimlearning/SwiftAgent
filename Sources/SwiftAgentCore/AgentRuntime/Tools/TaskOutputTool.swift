import Foundation

/// Gets output from a running or completed background task.
/// Matches Claude Code's TaskOutputTool.
public struct TaskOutputTool: Tool {
    public let name = "TaskOutput"
    public let description = "Retrieve output from a running or completed background task"

    private let taskManager: TaskManager

    public struct Arguments: Codable, Sendable {
        public var taskId: String
        public var block: Bool?
        public var timeout: Double?

        enum CodingKeys: String, CodingKey {
            case taskId
            case block
            case timeout
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["taskId"] = JSONSchemaProperty(type: "string", description: "The task ID to get output from")
        schema.properties?["block"] = JSONSchemaProperty(type: "boolean", description: "Whether to wait for completion (default: true)")
        schema.properties?["timeout"] = JSONSchemaProperty(type: "number", description: "Max wait time in ms (default: 30000, max: 600000)")
        schema.required = ["taskId"]
        return schema
    }

    public init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let taskId = arguments.taskId
        let shouldBlock = arguments.block ?? true
        let timeoutMs = min(arguments.timeout ?? 30000, 600000)
        let timeout = timeoutMs / 1000.0

        guard let task = await taskManager.get(taskId) else {
            return .string("No task found with ID \(taskId)")
        }

        let finalSnapshot: TaskProgressSnapshot?
        if shouldBlock && task.status == .running {
            finalSnapshot = await waitForCompletion(taskId: taskId, timeout: timeout)
            if finalSnapshot == nil {
                let current = await taskManager.progressSnapshot(taskId)
                return .string(responseJSON(
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

        return .string(responseJSON(retrievalStatus: status, snapshot: finalSnapshot))
    }

    // MARK: - Private helpers

    private func waitForCompletion(
        taskId: String,
        timeout: TimeInterval
    ) async -> TaskProgressSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            guard let snapshot = await taskManager.progressSnapshot(taskId) else {
                return nil
            }

            switch snapshot.task.status {
            case .completed, .failed, .killed:
                return snapshot
            case .pending, .running:
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return await taskManager.progressSnapshot(taskId)
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
