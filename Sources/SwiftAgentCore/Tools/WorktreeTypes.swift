import Foundation

/// A worktree session created by EnterWorktreeTool.
public struct WorktreeSession: Sendable {
    public let id: String
    public let originalCwd: String
    public let worktreePath: String
    public let worktreeBranch: String
    public let createdAt: Date
    public let originalHeadCommit: String?
    public let tmuxSessionName: String?

    public init(
        id: String,
        originalCwd: String,
        worktreePath: String,
        worktreeBranch: String,
        createdAt: Date,
        originalHeadCommit: String? = nil,
        tmuxSessionName: String? = nil
    ) {
        self.id = id
        self.originalCwd = originalCwd
        self.worktreePath = worktreePath
        self.worktreeBranch = worktreeBranch
        self.createdAt = createdAt
        self.originalHeadCommit = originalHeadCommit
        self.tmuxSessionName = tmuxSessionName
    }
}

/// Stores the active worktree session.
public final class WorktreeStore: @unchecked Sendable {
    public var currentSession: WorktreeSession?
    private let lock = NSLock()

    public init(currentSession: WorktreeSession? = nil) {
        self.currentSession = currentSession
    }

    public func getCurrentSession() -> WorktreeSession? {
        lock.lock()
        defer { lock.unlock() }
        return currentSession
    }
}
