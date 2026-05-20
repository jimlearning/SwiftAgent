import Foundation

/// Status of a background task.
public enum TaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case killed
}

/// Type of task — mirrors Claude Code's TaskType.
public enum TaskType: String, Codable, Sendable {
    case localBash = "local_bash"
    case localAgent = "local_agent"
    case remoteAgent = "remote_agent"
}

/// Represents a tracked background task.
public struct AgentTask: Sendable, Identifiable {
    public let id: String
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

    public init(id: String = UUID().uuidString, name: String, description: String = "") {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.status = .pending
        self.result = nil
        self.output = nil
        self.finishedAt = nil
        self.prompt = nil
        self.exitCode = nil
        self.error = nil
    }

    /// Append output text (e.g., stdout chunks).
    public mutating func appendOutput(_ text: String) {
        if output == nil { output = text }
        else { output! += text }
    }

    public mutating func markRunning() {
        status = .running
    }

    public mutating func markCompleted(result: String) {
        status = .completed
        self.result = result
        finishedAt = Date()
    }

    public mutating func markFailed(error: String) {
        status = .failed
        result = error
        finishedAt = Date()
    }

    public mutating func kill() {
        status = .killed
        finishedAt = Date()
    }
}

/// Manages background task lifecycle — creation, status tracking, cancellation.
public actor TaskManager {
    private var tasks: [String: AgentTask] = [:]
    private var cancellations: Set<String> = []

    public init() {}

    /// Create a new task in pending state.
    public func create(name: String, description: String = "") -> AgentTask {
        let task = AgentTask(name: name, description: description)
        tasks[task.id] = task
        return task
    }

    /// Mark a task as running.
    public func markRunning(_ id: String) {
        tasks[id]?.markRunning()
    }

    /// Mark a task as completed with a result.
    public func markCompleted(_ id: String, result: String) {
        tasks[id]?.markCompleted(result: result)
    }

    /// Mark a task as failed with an error message.
    public func markFailed(_ id: String, error: String) {
        tasks[id]?.markFailed(error: error)
    }

    /// Kill a task.
    public func kill(_ id: String) {
        cancellations.insert(id)
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
