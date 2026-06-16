import SwiftUI

/// Routes a `RightTab` to its actual panel implementation. Phase 5
/// finished, so Terminal / Browser / Files / Side chat are no longer
/// placeholders — they are real SwiftUI views.
struct TabContentView: View {
    let tab: RightTab
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var rightTabsStore: RightTabsStore

    var body: some View {
        switch tab.type {
        case .review:
            ReviewPanelView(entries: reviewEntries)
        case .terminal:
            TerminalPanelView(tabID: tab.id.uuidString)
        case .browser:
            BrowserPanelView(tabID: tab.id.uuidString, initialURL: initialBrowserURL)
        case .files:
            FilesPanelView(tabID: tab.id.uuidString, projectPath: currentProjectPath)
        case .sideChat:
            SideChatPanelView(tabID: tab.id.uuidString)
        }
    }

    /// Derive Review entries from the selected thread's last-known
    /// edit summary (kept on AppViewModel as `lastEditSummary`). When
    /// the user has just sent a message that triggered file edits, the
    /// EditSummaryCard carries the file list; we mirror it here so the
    /// Review panel has something to render.
    private var reviewEntries: [ReviewPanelView.DiffEntry] {
        appViewModel.lastEditSummary.makeEntries()
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
