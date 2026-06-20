import Foundation

/// Extract a TimeInterval from a database row, accepting both Double and Int64.
private func timeInterval(from row: [String: Any], _ key: String) -> Double? {
    if let d = row[key] as? Double { return d }
    if let i = row[key] as? Int64 { return Double(i) }
    return nil
}

// MARK: - Persisted Project

public struct PersistedProject: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Create from a database row.
    init?(row: [String: Any]) {
        guard let id = row["id"] as? String,
              let name = row["name"] as? String,
              let path = row["path"] as? String,
              let createdAt = timeInterval(from: row, "created_at"),
              let updatedAt = timeInterval(from: row, "updated_at")
        else { return nil }
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = Date(timeIntervalSince1970: createdAt)
        self.updatedAt = Date(timeIntervalSince1970: updatedAt)
    }

}

// MARK: - Persisted Thread

public struct PersistedThread: Identifiable, Equatable, Sendable {
    public let id: String
    public var projectId: String?
    public var title: String
    public var state: String
    public var reuseState: String
    public var mode: String
    public var sandboxMode: String
    public var executionEnv: String
    public var model: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String? = nil,
        title: String = "Untitled",
        state: String = "idle",
        reuseState: String = "new",
        mode: String = "code",
        sandboxMode: String = "workspace-write",
        executionEnv: String = "local",
        model: String = "deepseek-v4-pro",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.state = state
        self.reuseState = reuseState
        self.mode = mode
        self.sandboxMode = sandboxMode
        self.executionEnv = executionEnv
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Create from a database row.
    init?(row: [String: Any]) {
        guard let id = row["id"] as? String,
              let title = row["title"] as? String,
              let state = row["state"] as? String,
              let reuseState = row["reuse_state"] as? String,
              let mode = row["mode"] as? String,
              let sandboxMode = row["sandbox_mode"] as? String,
              let executionEnv = row["execution_env"] as? String,
              let model = row["model"] as? String,
              let createdAt = timeInterval(from: row, "created_at"),
              let updatedAt = timeInterval(from: row, "updated_at")
        else { return nil }
        self.id = id
        self.projectId = row["project_id"] as? String
        self.title = title
        self.state = state
        self.reuseState = reuseState
        self.mode = mode
        self.sandboxMode = sandboxMode
        self.executionEnv = executionEnv
        self.model = model
        self.createdAt = Date(timeIntervalSince1970: createdAt)
        self.updatedAt = Date(timeIntervalSince1970: updatedAt)
    }
}

// MARK: - FTS Search Result

/// A message match from FTS5 full-text search.
public struct FTSearchResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let role: String
    public let content: String
    /// Snippet with `<b>...</b>` highlight markers from FTS5.
    public let snippet: String
    public let createdAt: Date

    public init(
        id: String,
        threadId: String,
        role: String,
        content: String,
        snippet: String,
        createdAt: Date
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.snippet = snippet
        self.createdAt = createdAt
    }
}

// MARK: - Persisted Message

public struct PersistedMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let role: String
    public var content: String
    public var metadata: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        threadId: String,
        role: String,
        content: String,
        metadata: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }

    /// Create from a database row.
    init?(row: [String: Any]) {
        guard let id = row["id"] as? String,
              let threadId = row["thread_id"] as? String,
              let role = row["role"] as? String,
              let content = row["content"] as? String,
              let createdAt = timeInterval(from: row, "created_at")
        else { return nil }
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.metadata = row["metadata"] as? String
        self.createdAt = Date(timeIntervalSince1970: createdAt)
    }
}
