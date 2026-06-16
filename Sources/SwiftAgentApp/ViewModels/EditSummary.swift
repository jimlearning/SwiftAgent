import Foundation

/// Snapshot of files edited in the most recent thread turn, used by the
/// Review panel and the EditSummaryCard in the conversation stream.
/// Populated when the agent finishes a turn that modified files; cleared
/// when the user starts a new turn.
public struct EditSummary: Equatable, Sendable {
    public var fileNames: [String]
    public var linesAdded: Int
    public var linesRemoved: Int
    public var generatedAt: Date

    public init(fileNames: [String] = [], linesAdded: Int = 0, linesRemoved: Int = 0, generatedAt: Date = Date()) {
        self.fileNames = fileNames
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.generatedAt = generatedAt
    }

    public static let empty = EditSummary()

    public var isEmpty: Bool { fileNames.isEmpty }
}

extension EditSummary {
    /// Build the per-file `ReviewPanelView.DiffEntry` array from this summary.
    /// The actual diff content is left empty here — the Review panel will
    /// pull real unified diffs from `git diff` once we wire the worktree
    /// editor. For v1 we just show the file list + counts.
    public func entries() -> [ReviewPanelView.DiffEntry] {
        return makeEntries()
    }
}

public extension EditSummary {
    /// Same as `entries()` but free-standing so callers that already
    /// imported EditSummary can use the helper without ambiguity.
    func makeEntries() -> [ReviewPanelView.DiffEntry] {
        // Distribute the total delta evenly across files as a placeholder.
        // Real per-file counts will come from `git diff --numstat`.
        let perFileAdded = fileNames.isEmpty ? 0 : max(1, linesAdded / fileNames.count)
        let perFileRemoved = fileNames.isEmpty ? 0 : max(1, linesRemoved / fileNames.count)
        return fileNames.map { name in
            ReviewPanelView.DiffEntry(
                fileName: name,
                linesAdded: perFileAdded,
                linesRemoved: perFileRemoved,
                diffContent: "",
                status: .modified
            )
        }
    }
}
