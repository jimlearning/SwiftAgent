import Foundation

/// Status of a background task.
public enum TaskStatus: String, Codable, Sendable, Equatable {
    case pending
    case running
    case completed
    case failed
    case killed
}

/// Type of task — mirrors Claude Code's TaskType.
/// CC: Task.ts:6-13 — 7 task types.
public enum TaskType: String, Codable, Sendable, Equatable {
    case localBash = "local_bash"
    case localAgent = "local_agent"
    case remoteAgent = "remote_agent"
    case inProcessTeammate = "in_process_teammate"
    case localWorkflow = "local_workflow"
    case monitorMcp = "monitor_mcp"
    case dream = "dream"
}

/// High-level phase for a background task.
public enum TaskProgressPhase: String, Codable, Sendable {
    case pending
    case running
    case thinking
    case usingTool = "using_tool"
    case writingResults = "writing_results"
    case turnComplete = "turn_complete"
    case completed
    case failed
    case killed
}

/// Structured progress event for background task status surfaces.
public struct TaskProgressEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let taskId: String
    public let taskName: String
    public let phase: TaskProgressPhase
    public let message: String
    public let timestamp: Date
    public let toolName: String?
    public let turnNumber: Int?
    public let toolCallCount: Int?

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        taskName: String,
        phase: TaskProgressPhase,
        message: String,
        timestamp: Date = Date(),
        toolName: String? = nil,
        turnNumber: Int? = nil,
        toolCallCount: Int? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.phase = phase
        self.message = message
        self.timestamp = timestamp
        self.toolName = toolName
        self.turnNumber = turnNumber
        self.toolCallCount = toolCallCount
    }
}

/// Compact current-state summary for a background task.
public struct TaskProgressSummary: Codable, Sendable, Equatable {
    public let taskId: String
    public let taskName: String
    public let description: String
    public let status: TaskStatus
    public let phase: TaskProgressPhase
    public let currentTool: String?
    public let lastMessage: String
    public let turnCount: Int
    public let completedToolCount: Int
    public let updatedAt: Date

    public init(
        taskId: String,
        taskName: String,
        description: String,
        status: TaskStatus,
        phase: TaskProgressPhase,
        currentTool: String?,
        lastMessage: String,
        turnCount: Int,
        completedToolCount: Int,
        updatedAt: Date
    ) {
        self.taskId = taskId
        self.taskName = taskName
        self.description = description
        self.status = status
        self.phase = phase
        self.currentTool = currentTool
        self.lastMessage = lastMessage
        self.turnCount = turnCount
        self.completedToolCount = completedToolCount
        self.updatedAt = updatedAt
    }
}

/// Current task plus structured progress details.
public struct TaskProgressSnapshot: Sendable, Equatable {
    public let task: AgentTask
    public let summary: TaskProgressSummary
    public let recentEvents: [TaskProgressEvent]

    public init(task: AgentTask, summary: TaskProgressSummary, recentEvents: [TaskProgressEvent]) {
        self.task = task
        self.summary = summary
        self.recentEvents = recentEvents
    }
}

/// Represents a tracked background task.
public struct AgentTask: Sendable, Identifiable, Equatable {
    public static let progressEventLimit = 50

    public let id: String
    public let type: TaskType
    public let name: String
    public let description: String
    public let createdAt: Date
    public var status: TaskStatus
    public var result: String?
    public var output: String?  // Accumulated stdout/stderr or agent messages
    public var finishedAt: Date?
    public var prompt: String?  // For agent tasks: the prompt given
    public var exitCode: Int?   // For bash tasks: exit code
    public var error: String?   // Error message if failed
    public var recentProgressEvents: [TaskProgressEvent]
    public var currentPhase: TaskProgressPhase
    public var currentTool: String?
    public var lastProgressMessage: String
    public var turnCount: Int
    public var completedToolCount: Int
    public var progressUpdatedAt: Date

    public init(
        id: String = UUID().uuidString,
        type: TaskType = .localWorkflow,
        name: String,
        description: String = "",
        prompt: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.status = .pending
        self.result = nil
        self.output = nil
        self.finishedAt = nil
        self.prompt = prompt
        self.exitCode = nil
        self.error = nil
        self.recentProgressEvents = []
        self.currentPhase = .pending
        self.currentTool = nil
        self.lastProgressMessage = description.isEmpty ? name : description
        self.turnCount = 0
        self.completedToolCount = 0
        self.progressUpdatedAt = createdAt
    }

    /// Append output text (e.g., stdout chunks).
    public mutating func appendOutput(_ text: String) {
        if output == nil { output = text }
        else { output! += text }
    }

    public mutating func markRunning() {
        status = .running
        appendProgress(phase: .running, message: "\(name) is running")
    }

    public mutating func markCompleted(result: String) {
        status = .completed
        self.result = result
        finishedAt = Date()
        appendProgress(phase: .completed, message: "\(name) completed")
    }

    public mutating func markFailed(error: String) {
        status = .failed
        result = error
        self.error = error
        finishedAt = Date()
        appendProgress(phase: .failed, message: "\(name) failed: \(error)")
    }

    public mutating func kill() {
        status = .killed
        finishedAt = Date()
        appendProgress(phase: .killed, message: "\(name) was stopped")
    }

    public mutating func appendProgress(
        phase: TaskProgressPhase,
        message: String,
        toolName: String? = nil,
        turnNumber: Int? = nil,
        toolCallCount: Int? = nil
    ) {
        let event = TaskProgressEvent(
            taskId: id,
            taskName: name,
            phase: phase,
            message: message,
            toolName: toolName,
            turnNumber: turnNumber,
            toolCallCount: toolCallCount
        )
        recentProgressEvents.append(event)
        if recentProgressEvents.count > Self.progressEventLimit {
            recentProgressEvents.removeFirst(recentProgressEvents.count - Self.progressEventLimit)
        }

        currentPhase = phase
        currentTool = phase == .usingTool ? toolName : nil
        lastProgressMessage = message
        progressUpdatedAt = event.timestamp
        if let turnNumber {
            turnCount = max(turnCount, turnNumber)
        }
        if phase == .usingTool, toolName != nil {
            // Keep current tool visible but count completed tools only after the
            // matching completion event arrives.
        } else if message.contains(" completed "), toolName != nil {
            completedToolCount += 1
        }
        if let toolCallCount, phase == .turnComplete {
            completedToolCount = max(completedToolCount, toolCallCount)
        }
    }

    public func progressSummary() -> TaskProgressSummary {
        TaskProgressSummary(
            taskId: id,
            taskName: name,
            description: description,
            status: status,
            phase: currentPhase,
            currentTool: currentTool,
            lastMessage: lastProgressMessage,
            turnCount: turnCount,
            completedToolCount: completedToolCount,
            updatedAt: progressUpdatedAt
        )
    }
}

/// Manages background task lifecycle — creation, status tracking, cancellation.
public actor TaskManager {
    private var tasks: [String: AgentTask] = [:]
    private var cancellations: Set<String> = []
    private var cancellationHandlers: [String: @Sendable () -> Void] = [:]

    public init() {}

    /// Create a new task in pending state.
    public func create(
        name: String,
        description: String = "",
        type: TaskType = .localWorkflow,
        prompt: String? = nil
    ) -> AgentTask {
        let task = AgentTask(type: type, name: name, description: description, prompt: prompt)
        tasks[task.id] = task
        return task
    }

    /// Mark a task as running.
    public func markRunning(_ id: String) {
        tasks[id]?.markRunning()
    }

    /// Mark a task as completed with a result.
    public func markCompleted(_ id: String, result: String) {
        guard tasks[id]?.status != .killed else { return }
        cancellationHandlers[id] = nil
        tasks[id]?.markCompleted(result: result)
    }

    /// Mark a task as failed with an error message.
    public func markFailed(_ id: String, error: String) {
        guard tasks[id]?.status != .killed else { return }
        cancellationHandlers[id] = nil
        tasks[id]?.markFailed(error: error)
    }

    /// Kill a task.
    public func kill(_ id: String) {
        cancellations.insert(id)
        cancellationHandlers.removeValue(forKey: id)?()
        tasks[id]?.kill()
    }

    /// Check if a task has been killed.
    public func isKilled(_ id: String) -> Bool {
        cancellations.contains(id)
    }

    /// Get a task by ID.
    public func get(_ id: String) -> AgentTask? {
        tasks[id]
    }

    /// Append output to a task.
    public func appendOutput(_ id: String, _ text: String) {
        tasks[id]?.appendOutput(text)
    }

    /// Append structured progress to a task.
    public func appendProgress(
        _ id: String,
        phase: TaskProgressPhase,
        message: String,
        toolName: String? = nil,
        turnNumber: Int? = nil,
        toolCallCount: Int? = nil
    ) {
        tasks[id]?.appendProgress(
            phase: phase,
            message: message,
            toolName: toolName,
            turnNumber: turnNumber,
            toolCallCount: toolCallCount
        )
    }

    /// Get a task and its current structured progress snapshot.
    public func progressSnapshot(_ id: String) -> TaskProgressSnapshot? {
        guard let task = tasks[id] else { return nil }
        return TaskProgressSnapshot(
            task: task,
            summary: task.progressSummary(),
            recentEvents: task.recentProgressEvents
        )
    }

    /// Register cancellation behavior for an actively running task.
    public func registerCancellationHandler(_ id: String, handler: @escaping @Sendable () -> Void) {
        guard cancellations.contains(id) == false else {
            handler()
            return
        }
        guard let task = tasks[id], task.status == .pending || task.status == .running else {
            return
        }
        cancellationHandlers[id] = handler
    }

    /// Clear a task's cancellation handler after it finishes.
    public func clearCancellationHandler(_ id: String) {
        cancellationHandlers[id] = nil
    }

    /// List all tasks.
    public func listAll() -> [AgentTask] {
        Array(tasks.values).sorted { $0.createdAt > $1.createdAt }
    }

    /// List active tasks (pending or running).
    public func listActive() -> [AgentTask] {
        tasks.values.filter { $0.status == .pending || $0.status == .running }
    }

    /// Wait for a task to complete within a timeout. Returns the task or nil on timeout.
    public func waitForCompletion(_ id: String, timeout: TimeInterval) async -> AgentTask? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let task = tasks[id], task.status == .completed || task.status == .failed || task.status == .killed {
                return task
            }
            if cancellations.contains(id) { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
        }
        return tasks[id]
    }

    /// Remove completed/cancelled tasks older than the given date.
    public func prune(before date: Date) {
        tasks = tasks.filter { _, task in
            guard let finishedAt = task.finishedAt else { return true }
            return finishedAt >= date
        }
    }
}
