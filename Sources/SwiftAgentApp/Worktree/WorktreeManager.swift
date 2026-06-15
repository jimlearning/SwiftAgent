import Foundation
import SwiftAgentCore

/// Wraps SwiftAgentCore's WorktreeManager for App-level use.
/// Provides UI-friendly methods for thread worktree isolation.
@MainActor
public final class AppWorktreeManager: ObservableObject {
    @Published public var activeWorktrees: [WorktreeEntry] = []

    /// The project root path for git operations.
    private var repoPath: String?

    public init() {}

    /// Set the repository path.
    public func setRepoPath(_ path: String) {
        self.repoPath = path
    }

    // MARK: - Create

    /// Create a git worktree for a given thread.
    /// Path: <repo>/../.swiftagent-worktrees/<thread-id>/
    /// Branch: swiftagent/thread-<short-id>
    public func createForThread(threadId: String) async throws -> String {
        guard let repo = repoPath else {
            throw AppWorktreeError.noRepoPath
        }
        let core = WorktreeManager(repoPath: repo)
        let shortId = String(threadId.prefix(8))
        let branchName = "swiftagent/thread-\(shortId)"

        // Create branch from HEAD
        try await createBranchIfNeeded(branchName)

        // Determine worktree path
        let repoParent = (repo as NSString).deletingLastPathComponent
        let worktreePath = "\(repoParent)/.swiftagent-worktrees/\(threadId)"

        // Remove existing worktree if present
        try? FileManager.default.removeItem(atPath: worktreePath)

        // Create the worktree
        let path = try await core.create(name: "thread-\(shortId)")
        let entry = WorktreeEntry(
            threadId: threadId,
            branch: branchName,
            path: path,
            createdAt: Date()
        )
        activeWorktrees.append(entry)
        return path
    }

    private func createBranchIfNeeded(_ branch: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath ?? "", "rev-parse", "--verify", branch]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // Branch doesn't exist, create it
            let createProcess = Process()
            createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            createProcess.arguments = ["-C", repoPath ?? "", "branch", branch]
            try createProcess.run()
            createProcess.waitUntilExit()
        }
    }

    // MARK: - Apply to Main

    /// Apply worktree changes to main branch.
    public func applyToMain(threadId: String, strategy: MergeStrategy) async throws {
        guard let entry = activeWorktrees.first(where: { $0.threadId == threadId }) else {
            throw AppWorktreeError.worktreeNotFound
        }
        guard let repo = repoPath else {
            throw AppWorktreeError.noRepoPath
        }

        // Fetch current branch
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let currentBranch = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"

        switch strategy {
        case .merge:
            // Switch to current branch and merge
            try await gitMerge(from: entry.branch, to: currentBranch, repo: repo)
        case .squash:
            try await gitSquash(from: entry.branch, to: currentBranch, repo: repo)
        case .rebase:
            try await gitRebase(from: entry.branch, to: currentBranch, repo: repo)
        }

        // Clean up worktree (keep branch)
        try await removeWorktree(threadId: threadId)
    }

    private func gitMerge(from: String, to: String, repo: String) async throws {
        try await runGit(["-C", repo, "merge", from, "--no-ff", "-m", "'Merge worktree \(from)'"])
    }

    private func gitSquash(from: String, to: String, repo: String) async throws {
        try await runGit(["-C", repo, "merge", "--squash", from])
        try await runGit(["-C", repo, "commit", "-m", "'Squash merge worktree \(from)'"])
    }

    private func gitRebase(from: String, to: String, repo: String) async throws {
        try await runGit(["-C", repo, "rebase", from, to])
    }

    // MARK: - Cleanup

    /// Remove a worktree but keep the branch.
    public func removeWorktree(threadId: String) async throws {
        guard let entry = activeWorktrees.first(where: { $0.threadId == threadId }),
              let repo = repoPath else { return }

        let core = WorktreeManager(repoPath: repo)
        try await core.remove(path: entry.path)

        activeWorktrees.removeAll { $0.threadId == threadId }
    }

    // MARK: - Helpers

    private func runGit(_ args: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown git error"
            throw AppWorktreeError.gitFailed(errStr)
        }
    }

    /// Get a WorktreeEntry for a thread if it exists.
    public func entry(for threadId: String) -> WorktreeEntry? {
        activeWorktrees.first { $0.threadId == threadId }
    }
}

// MARK: - Types

public struct WorktreeEntry: Identifiable, Equatable {
    public let id: String
    public let threadId: String
    public let branch: String
    public let path: String
    public let createdAt: Date

    public init(threadId: String, branch: String, path: String, createdAt: Date) {
        self.id = threadId
        self.threadId = threadId
        self.branch = branch
        self.path = path
        self.createdAt = createdAt
    }
}

public enum MergeStrategy: String, CaseIterable, Sendable {
    case merge = "Merge"
    case squash = "Squash"
    case rebase = "Rebase"
}

public enum AppWorktreeError: Error, Sendable {
    case noRepoPath
    case worktreeNotFound
    case gitFailed(String)
}
