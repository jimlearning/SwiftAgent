import Foundation
import SwiftAgentCore

/// Computes the diff summary for the Review panel by running
/// `git diff --numstat` in the current project's working directory.
/// The Review panel uses this to render real `+N -M` counts and a
/// per-file list instead of the placeholder `+0 -0`.
///
/// When the project isn't a git repo (or git isn't installed), the
/// diff is empty and the panel falls back to "No changes to review".
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
    /// Compute the current diff for `projectPath`. Runs synchronously
    /// (git diff is fast on small repos). Returns `.empty` if the
    /// project isn't a git repo, git isn't installed, or there's no
    /// diff.
    public static func compute(projectPath: String?) -> DiffSummary {
        guard let path = projectPath else { return .empty }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .empty
        }

        // numstat: tab-separated added/removed/file
        let numstat = runGit(arguments: ["diff", "--numstat"], cwd: path)
        let nameStatus = runGit(arguments: ["diff", "--name-status"], cwd: path)
        let unified = runGit(arguments: ["diff"], cwd: path)

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

    /// Refresh the AppViewModel.lastEditSummary with the latest diff for
    /// the currently-selected thread's project. Call after the user
    /// sends a message and the agent has had a chance to modify files.
    public static func refresh(for app: AppViewModel) {
        let projectPath = app.selectedThread.flatMap { thread in
            app.projects.first(where: { $0.threads.contains(where: { $0.id == thread.id }) })?.path
        } ?? FileManager.default.currentDirectoryPath

        let summary = compute(projectPath: projectPath)
        // Convert to EditSummary shape so the rest of the app keeps
        // working unchanged.
        app.lastEditSummary = EditSummary(
            fileNames: summary.entries.map(\.fileName),
            linesAdded: summary.totalAdded,
            linesRemoved: summary.totalRemoved
        )
        app.lastReviewEntries = summary.entries
    }

    // MARK: - Helpers

    private static func runGit(arguments: [String], cwd: String) -> String {
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
        // Extract the per-file hunk block from the full `git diff` output.
        let marker = "diff --git a/\(fileName) b/\(fileName)"
        guard let startRange = unified.range(of: marker) else { return "" }
        let rest = unified[startRange.upperBound...]
        // The next "diff --git" marks the end of this file's diff.
        if let endRange = rest.range(of: "\ndiff --git ") {
            return String(unified[startRange.lowerBound..<endRange.lowerBound])
        }
        return String(unified[startRange.lowerBound...])
    }
}
