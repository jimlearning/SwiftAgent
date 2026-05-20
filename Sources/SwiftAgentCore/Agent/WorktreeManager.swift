import Foundation

/// Manages git worktree creation and cleanup for isolated sub-agent work.
public struct WorktreeManager: Sendable {
    private let repoPath: String

    public init(repoPath: String = FileManager.default.currentDirectoryPath) {
        self.repoPath = repoPath
    }

    /// Create a temporary worktree at a new path.
    /// Returns the path to the worktree.
    public func create(name: String) async throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-agent-worktrees")
            .appendingPathComponent(name)
        let path = tmpDir.path

        try FileManager.default.createDirectory(
            at: tmpDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "worktree", "add", path]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        try await runProcess(process)

        return path
    }

    /// Remove a worktree and clean up.
    public func remove(path: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "worktree", "remove", "--force", path]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        try? await runProcess(process)

        // Prune any stale worktree references
        let prune = Process()
        prune.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        prune.arguments = ["-C", repoPath, "worktree", "prune"]
        prune.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        try? await runProcess(prune)
    }

    /// List all existing worktrees.
    public func list() async throws -> [WorktreeInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "worktree", "list", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        try await runProcess(process)

        let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        return parseWorktreeOutput(String(data: data, encoding: .utf8) ?? "")
    }

    private func runProcess(_ process: Process) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: WorktreeError.gitFailed(Int(proc.terminationStatus)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseWorktreeOutput(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("worktree ") {
                if let path = currentPath {
                    worktrees.append(WorktreeInfo(path: path, branch: currentBranch))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
            } else if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst("branch ".count))
            }
        }
        if let path = currentPath {
            worktrees.append(WorktreeInfo(path: path, branch: currentBranch))
        }

        return worktrees
    }
}

/// Information about a git worktree.
public struct WorktreeInfo: Sendable {
    public let path: String
    public let branch: String?

    public init(path: String, branch: String? = nil) {
        self.path = path
        self.branch = branch
    }
}

public enum WorktreeError: Error, Sendable {
    case gitFailed(Int)
    case notAGitRepository
}
