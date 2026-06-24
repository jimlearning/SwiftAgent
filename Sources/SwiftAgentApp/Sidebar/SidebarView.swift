import SwiftUI
import ClarcCore

/// Sidebar: top entries + Projects list (Clarc-style session rows) + Settings.
struct SidebarView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings

    @State private var showNewProjectSheet = false
    @State private var renameTarget: RenameTarget?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showPluginsSheet = false
    @State private var pluginTab: PluginTab = .skills
    @State private var searchObserverToken: NSObjectProtocol?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topEntries
                searchFieldArea
                projectsSection
                Spacer().frame(height: 12)
                settingsLink
            }
            .padding(.vertical, 6)
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
            searchObserverToken = NotificationCenter.default.addObserver(
                forName: .swiftAgentFocusSearch,
                object: nil,
                queue: .main
            ) { _ in
                DispatchQueue.main.async { [self] in isSearchFocused = true }
            }
        }
        .onDisappear {
            if let token = searchObserverToken {
                NotificationCenter.default.removeObserver(token)
                searchObserverToken = nil
            }
        }
    }

    // MARK: - Top 4 entries

    private var topEntries: some View {
        VStack(alignment: .leading, spacing: 1) {
            topEntry(icon: "square.and.pencil", title: "New chat", shortcut: "⌘N") {
                let pid = appViewModel.selectedThread?.projectId
                    ?? appViewModel.projects.first?.path
                    ?? NSHomeDirectory()
                _ = appViewModel.createThread(projectId: pid)
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
        .padding(.bottom, 6)
    }

    private func topEntry(icon: String, title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 4)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cellHoverHighlight()
        .help(title)
    }

    // MARK: - Search Field

    private var searchFieldArea: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textTertiary)
                .font(.system(size: 12))
                .frame(width: 16)
            TextField("Search threads...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 9, padding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSearchFocused ? Color.bgInput : Color.bgInput.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSearchFocused ? Color.accentPrimary.opacity(0.5) : Color.borderSubtle,
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3))
                .help("Add or open a project")
            ))

            if appViewModel.projects.isEmpty {
                Text("No projects yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }

            ForEach(appViewModel.projects) { project in
                ClarcProjectSectionView(
                    project: project,
                    selectedThreadID: appViewModel.selectedThreadID,
                    renameTarget: $renameTarget,
                    onSelectThread: { appViewModel.selectThread($0) },
                    onNewThread: { _ = appViewModel.createThread(title: "Chat in \(project.name)", projectId: project.path) },
                    onDeleteProject: { appViewModel.deleteProject(id: project.id) },
                    onDeleteThread: { appViewModel.deleteThread(id: $0) }
                )
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: AnyView?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .tracking(0.6)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Settings Link

    private var settingsLink: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text("Settings")
                    .font(.system(size: 13))
                Spacer()
                Text("⌘,")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cellHoverHighlight()
        .accessibilityLabel("Open Settings")
        .keyboardShortcut(",", modifiers: .command)
        .help("Open Settings (⌘,)")
    }

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
            pluginsHeader
            Divider().background(Color.borderSubtle)
            if pluginTab == .skills {
                SkillsView()
            } else {
                MCPConfigView()
            }
        }
        .frame(width: 540, height: 600)
        .background(Color.bgContent)
    }

    private var pluginsHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Plugins")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    showPluginsSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 12, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 4) {
                ForEach(PluginTab.allCases, id: \.self) { tab in
                    Button {
                        pluginTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(pluginTab == tab ? .textPrimary : .textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(pluginTab == tab ? Color.bgElevated : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(
                        background: Color.white.opacity(0.06),
                        cornerRadius: 6,
                        padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Project Section View (Clarc-style)

private struct ClarcProjectSectionView: View {
    @ObservedObject var project: ProjectViewModel
    let selectedThreadID: String?
    @Binding var renameTarget: RenameTarget?
    let onSelectThread: (ThreadViewModel) -> Void
    let onNewThread: () -> Void
    let onDeleteProject: () -> Void
    let onDeleteThread: (String) -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectRow
            if project.isExpanded {
                if project.threads.isEmpty {
                    Text("No chats")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .padding(.leading, 36)
                        .padding(.vertical, 2)
                }
                ForEach(project.threads) { thread in
                    ClarcThreadRowView(
                        thread: thread,
                        isSelected: selectedThreadID == thread.id,
                        renameTarget: $renameTarget,
                        onSelect: { onSelectThread(thread) },
                        onDelete: { onDeleteThread(thread.id) }
                    )
                }
            }
        }
    }

    private var projectRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .rotationEffect(.degrees(project.isExpanded ? 90 : 0))
                .frame(width: 14)
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text(project.name)
                .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                onNewThread()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .scaleEffect(isHovering ? 1 : 0.8)
            .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3))
            .help("New chat in \(project.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .cellHoverHighlight()
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: project.isExpanded)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                project.isExpanded.toggle()
            }
        }
        .contextMenu {
            Button("Rename") { renameTarget = .project(project.id) }
            Button("New Thread") { onNewThread() }
            Divider()
            Button("Delete", role: .destructive) { onDeleteProject() }
        }
    }
}

// MARK: - Thread Row View (Clarc-style)

/// Clarc-style session row: compact, relative date, rename/delete context menu.
private struct ClarcThreadRowView: View {
    @ObservedObject var thread: ThreadViewModel
    let isSelected: Bool
    @Binding var renameTarget: RenameTarget?
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Spacer().frame(width: 6)

                if thread.hasUnread && !isSelected {
                    Circle()
                        .fill(ClaudeTheme.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: ClaudeTheme.accent.opacity(0.35), radius: 3, x: 0, y: 0)
                }

                Text(displayTitle)
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(isSelected ? ClaudeTheme.textPrimary : ClaudeTheme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(relativeTime(thread.updatedAt))
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: isSelected ? CellTokens.selectedHoverBackground : CellTokens.hoverBackground,
            cornerRadius: CellTokens.cornerRadius,
            padding: CellTokens.padding
        )
        .background(
            RoundedRectangle(cornerRadius: CellTokens.cornerRadius)
                .fill(isSelected ? Color.bgElevated : Color.clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(ClaudeTheme.accent)
                .frame(width: 2)
                .padding(.vertical, 7)
                .padding(.leading, 2)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .contextMenu {
            Button("Rename") { renameTarget = .thread(thread.id) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var displayTitle: String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled" {
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
