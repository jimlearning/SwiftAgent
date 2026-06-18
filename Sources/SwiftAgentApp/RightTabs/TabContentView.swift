import SwiftUI

/// Routes a `RightTab` to its actual panel implementation. Phase 5
/// finished, so Terminal / Browser / Files / Side chat are no longer
/// placeholders — they are real SwiftUI views.
struct TabContentView: View {
    let tab: RightTab
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var rightTabsStore: RightTabsStore

    var body: some View {
        Group {
            switch tab.type {
            case .review:
                ReviewPanelView(entries: reviewEntries)
                    .onAppear { appViewModel.refreshDiffSummary() }
            case .terminal:
                TerminalPanelView(tabID: tab.id.uuidString)
            case .browser:
                BrowserPanelView(tabID: tab.id.uuidString, initialURL: initialBrowserURL)
            case .files:
                FilesPanelView(tabID: tab.id.uuidString, projectPath: currentProjectPath)
            case .sideChat:
                SideChatPanelView(tabID: tab.id.uuidString)
            case .debug:
                DebugPanelView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Derive Review entries from the AppViewModel's live diff cache
    /// (populated by `git diff --numstat` after each agent turn). When
    /// the user has just sent a message that triggered file edits, the
    /// EditSummaryCard carries the file list; we mirror it here so the
    /// Review panel has something to render.
    private var reviewEntries: [ReviewPanelView.DiffEntry] {
        appViewModel.lastReviewEntries.map { entry in
            ReviewPanelView.DiffEntry(
                id: entry.fileName,
                fileName: entry.fileName,
                linesAdded: entry.linesAdded,
                linesRemoved: entry.linesRemoved,
                diffContent: entry.diffContent,
                status: statusFromDiff(entry.status)
            )
        }
    }

    private func statusFromDiff(_ s: DiffSummary.DiffEntry.Status) -> ReviewPanelView.DiffEntry.FileStatus {
        switch s {
        case .added: return .added
        case .deleted: return .deleted
        case .renamed: return .modified
        case .modified: return .modified
        }
    }

    private var currentProjectPath: String? {
        guard let thread = appViewModel.selectedThread else { return nil }
        return appViewModel.projects.first(where: { $0.threads.contains(where: { $0.id == thread.id }) })?.path
            ?? FileManager.default.currentDirectoryPath
    }

    private var initialBrowserURL: URL {
        if let path = currentProjectPath {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(string: "https://deepseek.com")!
    }
}
