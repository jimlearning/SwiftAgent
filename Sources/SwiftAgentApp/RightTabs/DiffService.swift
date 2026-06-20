import Foundation
import SwiftAgentCore

/// Computes the diff summary for the Review panel by running
/// `git diff --numstat` in the current project's working directory.
/// The Review panel uses this to render real `+N -M` counts and a
/// per-file list instead of the placeholder `+0 -0`.
///
/// When the project isn't a git repo (or git isn't installed), the
/// diff is empty and the panel falls back to "No changes to review".
///
/// ## Concurrency
/// Git commands run on a background queue. Results are published
/// to `AppViewModel` on `@MainActor`. This prevents main-thread
/// hangs when `git diff` takes >100ms on large repos.
public struct DiffSummary: Sendable {
    public var entries: [DiffEntry]
    public var totalAdded: Int
    public var totalRemoved: Int

    public init(entries: [DiffEntry], totalAdded: Int, totalRemoved: Int) {
        self.entries = entries
        self.totalAdded = totalAdded
        self.totalRemoved = totalRemoved
    }

    public struct DiffEntry: Equatable, Sendable {
        public let fileName: String
        public let linesAdded: Int
        public let linesRemoved: Int
        public let diffContent: String
        public let status: Status

        public enum Status: Equatable, Sendable {
            case added, modified, deleted, renamed
        }
    }

    public static let empty = DiffSummary(entries: [], totalAdded: 0, totalRemoved: 0)
}

@MainActor
public enum DiffService {

    /// Logger prefix for agent-loop diagnostics.
    private static let LOG = "[AgentLoop][DiffService]"

    /// Compute the current diff for `projectPath` asynchronously.
    /// Git commands run off the main actor; result is published on `@MainActor`.
    ///
    /// - Parameters:
    ///   - projectPath: The project root (nil = home directory).
    ///   - onResult: Called on `@MainActor` with the computed summary.
    public static func computeAsync(
        projectPath: String?,
        onResult: @escaping @MainActor (DiffSummary) -> Void
    ) {
        let path = projectPath
        let startTime = CFAbsoluteTimeGetCurrent()
        let log = LOG  // capture before Sendable closure

        Task.detached(priority: .userInitiated) {
            let summary = await _compute(projectPath: path)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("\(log) computeAsync elapsed=\(String(format: "%.0f", elapsed))ms files=\(summary.entries.count)")

            await MainActor.run {
                onResult(summary)
            }
        }
    }

    /// Synchronous compute (legacy path — prefer `computeAsync`).
    /// Still blocks the calling thread; only safe from a background context.
    public static func compute(projectPath: String?) -> DiffSummary {
        let startTime = CFAbsoluteTimeGetCurrent()
        let summary = _computeSync(projectPath: projectPath)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("\(LOG) compute SYNC elapsed=\(String(format: "%.0f", elapsed))ms files=\(summary.entries.count)")
        return summary
    }

    /// Refresh the AppViewModel from a background context.
    public static func refresh(for app: AppViewModel) {
        let projectPath = app.selectedThread?.workingDirectory ?? NSHomeDirectory()

        print("\(LOG) refresh starting — path=\(projectPath)")

        computeAsync(projectPath: projectPath) { @MainActor summary in
            app.lastEditSummary = EditSummary(
                fileNames: summary.entries.map(\.fileName),
                linesAdded: summary.totalAdded,
                linesRemoved: summary.totalRemoved
            )
            app.lastReviewEntries = summary.entries
            print("\(LOG) refresh published — entries=\(summary.entries.count) +\(summary.totalAdded) -\(summary.totalRemoved)")
        }
    }

    // MARK: - Async Implementation

    /// Runs in a detached context — safe to call from any queue.
    private static func _compute(projectPath: String?) async -> DiffSummary {
        guard let path = projectPath else { return .empty }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .empty
        }

        async let numstat = runGitAsync(arguments: ["diff", "--numstat"], cwd: path)
        async let nameStatus = runGitAsync(arguments: ["diff", "--name-status"], cwd: path)
        async let unified = runGitAsync(arguments: ["diff"], cwd: path)

        let (numstatStr, nameStatusStr, unifiedStr) = await (numstat, nameStatus, unified)

        return buildSummary(numstat: numstatStr, nameStatus: nameStatusStr, unified: unifiedStr)
    }

    /// Synchronous implementation for legacy callers.
    private static func _computeSync(projectPath: String?) -> DiffSummary {
        guard let path = projectPath else { return .empty }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .empty
        }

        let numstat = runGitSync(arguments: ["diff", "--numstat"], cwd: path)
        let nameStatus = runGitSync(arguments: ["diff", "--name-status"], cwd: path)
        let unified = runGitSync(arguments: ["diff"], cwd: path)

        return buildSummary(numstat: numstat, nameStatus: nameStatus, unified: unified)
    }

    /// Build DiffSummary from raw git output strings.
    private static func buildSummary(numstat: String, nameStatus: String, unified: String) -> DiffSummary {
        var statusByFile: [String: DiffSummary.DiffEntry.Status] = [:]
        for line in nameStatus.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let statusChar = String(parts[0])
            let file = String(parts.last!)
            switch statusChar.first {
            case "A": statusByFile[file] = .added
            case "D": statusByFile[file] = .deleted
            case "M", "T": statusByFile[file] = .modified
            case "R": statusByFile[file] = .renamed
            default: statusByFile[file] = .modified
            }
        }

        var entries: [DiffSummary.DiffEntry] = []
        var totalAdded = 0
        var totalRemoved = 0

        for line in numstat.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            let added = Int(parts[0]) ?? 0
            let removed = Int(parts[1]) ?? 0
            let file = String(parts[2])
            let entry = DiffSummary.DiffEntry(
                fileName: file,
                linesAdded: added,
                linesRemoved: removed,
                diffContent: extractDiffForFile(unified: unified, fileName: file),
                status: statusByFile[file] ?? .modified
            )
            entries.append(entry)
            totalAdded += added
            totalRemoved += removed
        }

        return DiffSummary(entries: entries, totalAdded: totalAdded, totalRemoved: totalRemoved)
    }

    // MARK: - Git Helpers

    private static func runGitSync(arguments: [String], cwd: String) -> String {
        let t0 = CFAbsoluteTimeGetCurrent()
        let output = _runGit(arguments: arguments, cwd: cwd)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if ms > 50 {
            print("\(LOG) git \(arguments.joined(separator: " ")) took \(String(format: "%.0f", ms))ms")
        }
        return output
    }

    private static func runGitAsync(arguments: [String], cwd: String) async -> String {
        let log = LOG  // capture before Sendable closure
        let t0 = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = _runGit(arguments: arguments, cwd: cwd)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                if ms > 50 {
                    print("\(log) git \(arguments.joined(separator: " ")) took \(String(format: "%.0f", ms))ms")
                }
                continuation.resume(returning: output)
            }
        }
    }

    /// Core git invocation — blocks the calling thread. Call from background.
    private static func _runGit(arguments: [String], cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func extractDiffForFile(unified: String, fileName: String) -> String {
        let marker = "diff --git a/\(fileName) b/\(fileName)"
        guard let startRange = unified.range(of: marker) else { return "" }
        let rest = unified[startRange.upperBound...]
        if let endRange = rest.range(of: "\ndiff --git ") {
            return String(unified[startRange.lowerBound..<endRange.lowerBound])
        }
        return String(unified[startRange.lowerBound...])
    }
}
