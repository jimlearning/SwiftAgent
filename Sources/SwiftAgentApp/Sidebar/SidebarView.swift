import SwiftUI

/// Sidebar: top entries + Projects list + Chats (global) + Settings.
///
/// Built from `ScrollView` + `VStack` rather than `List` because List's
/// row container hijacks Button hit-testing: a `Button` placed inside a
/// List row has its tap region restricted to the label/icon, not the
/// full row. ScrollView + VStack keeps every Button's contentShape
/// intact, so each top entry, project row, and thread row is a
/// fully-clickable cell with hover highlight.
struct SidebarView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var showNewProjectSheet = false
    @State private var showRenameSheet = false
    @State private var renameTarget: RenameTarget?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showPluginsSheet = false
    @State private var pluginTab: PluginTab = .skills

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topEntries
                searchFieldArea
                projectsSection
                chatsSection
                Spacer().frame(height: 8)
                settingsLink
            }
            .padding(.vertical, 8)
        }
        .background(Color.bgSidebar)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet { name, path in
                _ = appViewModel.createProject(name: name, path: path)
            }
        }
        .sheet(item: $renameTarget) { target in
            RenameSheet(target: target) { newName in
                switch target {
                case .thread(let id):
                    appViewModel.renameThread(id: id, title: newName)
                case .project(let id):
                    appViewModel.renameProject(id: id, name: newName)
                }
            }
        }
        .sheet(isPresented: $showPluginsSheet) {
            pluginsSheetContent
        }
        .onAppear {
            // Listen for the ⌘F menu command to focus the search field.
            // We store the observer token so we can remove it on disappear;
            // passing `self` to removeObserver on a SwiftUI View struct is a
            // no-op at runtime (no such observer registered), so we track
            // the token directly.
            searchObserverToken = NotificationCenter.default.addObserver(
                forName: .swiftAgentFocusSearch,
                object: nil,
                queue: .main
            ) { [self] _ in
                isSearchFocused = true
            }
        }
        .onDisappear {
            if let token = searchObserverToken {
                NotificationCenter.default.removeObserver(token)
                searchObserverToken = nil
            }
        }
    }

    @State private var searchObserverToken: NSObjectProtocol?

    // MARK: - Top 4 entries

    private var topEntries: some View {
        VStack(alignment: .leading, spacing: 0) {
            topEntry(icon: "square.and.pencil", title: "New chat", shortcut: "⌘N") {
                _ = appViewModel.createThread()
            }
            topEntry(icon: "magnifyingglass", title: "Search", shortcut: "⌘F") {
                isSearchFocused = true
            }
            topEntry(icon: "at", title: "Plugins", shortcut: nil) {
                showPluginsSheet = true
            }
            topEntry(icon: "clock", title: "Automations", shortcut: nil) {
                // Phase 4 stub — opens an Inbox placeholder
            }
        }
    }

    private func topEntry(icon: String, title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(title)
                    .font(.uiLabel)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        )
        .help(title)
    }

    // MARK: - Search Field

    @ViewBuilder
    private var searchFieldArea: some View {
        // Always visible (not just on focus) so the user can immediately
        // see the input affordance and the focus highlight is obvious.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textTertiary)
                .font(.system(size: 12))
                .frame(width: 16)
            TextField("Search threads...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, newValue in
                    appViewModel.searchFilter = newValue
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    appViewModel.searchFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSearchFocused ? Color.bgElevated.opacity(0.6) : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Projects", trailing: AnyView(
                Menu {
                    Button("Open Project…") { openProjectFolder() }
                    Button("New Project…") { showNewProjectSheet = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            ))

            if appViewModel.projects.isEmpty {
                Text("No projects yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            // ProjectSectionView observes the ProjectViewModel directly so
            // changes to `isExpanded` (collapse/expand) redraw correctly.
            ForEach(appViewModel.projects) { project in
                ProjectSectionView(
                    project: project,
                    renameTarget: $renameTarget,
                    onSelectThread: { appViewModel.selectThread($0) },
                    onNewThread: { _ = appViewModel.createThread(projectId: project.id) },
                    onDeleteProject: { appViewModel.deleteProject(id: project.id) },
                    onDeleteThread: { appViewModel.deleteThread(id: $0) }
                )
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: AnyView?) -> some View {
        HStack {
            Text(title)
                .font(.uiCaption)
                .foregroundColor(.textSecondary)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Chats (global) Section

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Chats (global)", trailing: nil)

            if appViewModel.globalThreads.isEmpty {
                Text("No chats yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            ForEach(appViewModel.globalThreads) { thread in
                ThreadRowView(
                    thread: thread,
                    isSelected: appViewModel.selectedThreadID == thread.id,
                    renameTarget: $renameTarget,
                    onSelect: { appViewModel.selectThread(thread) },
                    onDelete: { appViewModel.deleteThread(id: thread.id) }
                )
            }
        }
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        Button {
            // Use SwiftUI's openWindow environment so the Settings
            // scene declared in EntryPoint presents as an independent
            // NSWindow (per §17 #23 — settings is NOT an in-app popup
            // and must NOT use a custom URL scheme).
            openWindow(id: "settings")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                Text("Settings")
                    .font(.uiLabel)
                Spacer()
            }
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        )
        .accessibilityLabel("Open Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    // MARK: - Open Project Folder

    private func openProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Select a project folder to open in SwiftAgent"
        if panel.runModal() == .OK, let url = panel.url {
            _ = appViewModel.openProject(path: url.path)
        }
    }

    // MARK: - Plugins Sheet

    enum PluginTab: String, CaseIterable {
        case skills = "Skills"
        case mcp = "MCP"
    }

    private var pluginsSheetContent: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                HStack(spacing: 0) {
                    ForEach(PluginTab.allCases, id: \.self) { tab in
                        Button {
                            pluginTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(pluginTab == tab ? .textPrimary : .textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(pluginTab == tab ? Color.bgContent : Color.clear)
                    }
                }
                Spacer()
                Button {
                    showPluginsSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .background(Color.bgSidebar)

            Divider().background(Color.borderSubtle)

            if pluginTab == .skills {
                SkillsView()
            } else {
                MCPConfigView()
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Project Section View (observes its own ProjectViewModel)

/// A self-contained row + child thread list for a single project.
/// Uses `@ObservedObject` on `project` so changes to `isExpanded`
/// trigger a redraw of just this row. Without this observation,
/// SidebarView never gets a "project was collapsed" signal because
/// SidebarView only observes AppViewModel, not ProjectViewModel.
struct ProjectSectionView: View {
    @ObservedObject var project: ProjectViewModel

    @Binding var renameTarget: RenameTarget?
    let onSelectThread: (ThreadViewModel) -> Void
    let onNewThread: () -> Void
    let onDeleteProject: () -> Void
    let onDeleteThread: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectRow
            if project.isExpanded {
                if project.threads.isEmpty {
                    Text("No chats")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                        .padding(.leading, 40)
                        .padding(.vertical, 2)
                }
                ForEach(project.threads) { thread in
                    ThreadRowView(
                        thread: thread,
                        isSelected: false,
                        renameTarget: $renameTarget,
                        onSelect: { onSelectThread(thread) },
                        onDelete: { onDeleteThread(thread.id) }
                    )
                }
            }
        }
    }

    private var projectRow: some View {
        Button {
            project.isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: project.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Image(systemName: "folder")
                    .font(.system(size: 13))
                Text(project.name)
                    .font(.uiLabel)
                Spacer()
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        )
        .contextMenu {
            Button("Rename") { renameTarget = .project(project.id) }
            Button("New Thread") { onNewThread() }
            Divider()
            Button("Delete", role: .destructive) { onDeleteProject() }
        }
    }
}

// MARK: - Thread Row View (cell with hover)

/// Single thread row: title + relative timestamp + hover highlight.
/// Self-contained so it can be used both inside ProjectSectionView and
/// directly in the global Chats section.
struct ThreadRowView: View {
    @ObservedObject var thread: ThreadViewModel
    let isSelected: Bool

    @Binding var renameTarget: RenameTarget?
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if thread.hasUnread {
                    Circle()
                        .fill(Color.accentPrimary)
                        .frame(width: 6, height: 6)
                } else {
                    Spacer().frame(width: 6)
                }
                Text(displayTitle)
                    .font(.uiBody)
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(thread.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.bgElevated.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(0.06),
            cornerRadius: 6,
            padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        )
        .contextMenu {
            Button("Rename") { renameTarget = .thread(thread.id) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    /// Show the thread title — fall back to "New Chat" when it's
    /// still the placeholder from creation.
    private var displayTitle: String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled" || trimmed == "New Chat" {
            return "New Chat"
        }
        return trimmed
    }

    private func relativeTime(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
