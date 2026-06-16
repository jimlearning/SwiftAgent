import SwiftUI

/// Sidebar: top entries + Projects list + Chats (global) + Settings.
///
/// Uses `ScrollView` + `VStack` rather than `List` because List's row
/// container hijacks hit-testing: a `Button` placed inside a List row has
/// its tap region restricted to the label/icon, not the full row.
/// That produced the "click the blank cell — nothing happens" bug.
/// ScrollView + VStack keeps every Button's contentShape intact.
struct SidebarView: View {
    @EnvironmentObject var appViewModel: AppViewModel

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
                if isSearchFocused { searchField }
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
        .onAppear { setupKeyboardShortcuts() }
    }

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
                // Phase 4 stub
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
        .help(title)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textTertiary)
                .font(.system(size: 12))
            TextField("Search threads...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .focused($isSearchFocused)
                .onSubmit {
                    appViewModel.searchFilter = searchText
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    appViewModel.searchFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textTertiary)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

            ForEach(appViewModel.projects) { project in
                VStack(alignment: .leading, spacing: 0) {
                    projectRow(project: project)
                    if project.isExpanded {
                        if project.threads.isEmpty {
                            Text("No chats")
                                .font(.uiCaption)
                                .foregroundColor(.textTertiary)
                                .padding(.leading, 40)
                                .padding(.vertical, 2)
                        }
                        ForEach(project.threads) { thread in
                            threadRow(thread: thread)
                        }
                    }
                }
            }
        }
    }

    private func projectRow(project: ProjectViewModel) -> some View {
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
        .contextMenu {
            Button("Rename") { renameTarget = .project(project.id) }
            Button("New Thread") { _ = appViewModel.createThread(projectId: project.id) }
            Button("Delete", role: .destructive) { appViewModel.deleteProject(id: project.id) }
        }
    }

    private func threadRow(thread: ThreadViewModel) -> some View {
        let isSelected = appViewModel.selectedThreadID == thread.id
        return Button {
            appViewModel.selectThread(thread)
        } label: {
            HStack(spacing: 4) {
                if thread.hasUnread {
                    Circle()
                        .fill(Color.accentPrimary)
                        .frame(width: 6, height: 6)
                } else {
                    Spacer().frame(width: 6)
                }
                Text(thread.title)
                    .font(.uiBody)
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(thread.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(isSelected ? .textPrimary : .textPrimary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.bgElevated.opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { renameTarget = .thread(thread.id) }
            Button("Delete", role: .destructive) { appViewModel.deleteThread(id: thread.id) }
        }
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
                threadRow(thread: thread)
            }
        }
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        Button {
            openSettingsWindow()
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
        .accessibilityLabel("Open Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    // MARK: - Section Header

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

    // MARK: - Settings Window

    private func openSettingsWindow() {
        if let url = URL(string: "swiftagent-settings://settings") {
            NSWorkspace.shared.open(url)
        }
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

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = modifiers.contains(.command)
            let hasShift = modifiers.contains(.shift)
            let hasOption = modifiers.contains(.option)

            switch event.keyCode {
            case 45: // N key
                if hasCommand && hasOption {
                    let pid = appViewModel.selectedThread.flatMap { t in
                        appViewModel.projects.first(where: { $0.threads.contains(where: { $0.id == t.id }) })?.id
                    }
                    _ = appViewModel.createThread(title: "Quick Chat", projectId: pid)
                    return nil
                }
                if hasCommand && hasShift {
                    let pid = appViewModel.selectedThread.flatMap { t in
                        appViewModel.projects.first(where: { $0.threads.contains(where: { $0.id == t.id }) })?.id
                    }
                    _ = appViewModel.createThread(projectId: pid)
                    return nil
                }
                if hasCommand {
                    _ = appViewModel.createThread()
                    return nil
                }
            case 3: // F key
                if hasCommand {
                    isSearchFocused = true
                    return nil
                }
            case 15: // R key
                if hasCommand && hasOption {
                    if let id = appViewModel.selectedThreadID {
                        renameTarget = .thread(id)
                    }
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    // MARK: - Plugins Sheet

    enum PluginTab: String, CaseIterable {
        case skills = "Skills"
        case mcp = "MCP"
    }

    private var pluginsSheetContent: some View {
        VStack(spacing: 0) {
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
                Spacer()
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
