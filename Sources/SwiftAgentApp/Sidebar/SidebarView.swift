import SwiftUI

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
        List {
            // Top 4 entries
            Section {
                topEntry(icon: "pencil.tip.crop.circle", title: "New chat", shortcut: "⌘N") {
                    _ = appViewModel.createThread()
                }
                topEntry(icon: "magnifyingglass", title: "Search", shortcut: "⌘F") {
                    isSearchFocused = true
                }
                topEntry(icon: "at", title: "Plugins", shortcut: nil) {
                    showPluginsSheet = true
                }
                topEntry(icon: "clock", title: "Automations", shortcut: nil) {
                    // Stub — Phase 4
                }
            }

            // Search field (shown when focused)
            if isSearchFocused {
                searchField
            }

            // Projects section
            Section {
                if appViewModel.projects.isEmpty {
                    Text("No projects yet")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                }
                ForEach(appViewModel.projects) { project in
                    ProjectRowView(
                        project: project,
                        isExpanded: project.isExpanded,
                        onToggle: { project.isExpanded.toggle() },
                        onRename: { renameTarget = .project(project.id) },
                        onDelete: {
                            appViewModel.deleteProject(id: project.id)
                        },
                        onNewThread: {
                            _ = appViewModel.createThread(projectId: project.id)
                        }
                    )
                    if project.isExpanded {
                        if project.threads.isEmpty {
                            Text("No chats")
                                .font(.uiCaption)
                                .foregroundColor(.textTertiary)
                                .padding(.leading, 56)
                        }
                        ForEach(project.threads) { thread in
                            ThreadRowView(
                                thread: thread,
                                isSelected: appViewModel.selectedThreadID == thread.id,
                                onSelect: { appViewModel.selectThread(thread) },
                                onRename: { renameTarget = .thread(thread.id) },
                                onDelete: {
                                    appViewModel.deleteThread(id: thread.id)
                                }
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Button {
                        showNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textSecondary)
                }
            }

            // Chats (global) section
            Section {
                if appViewModel.globalThreads.isEmpty {
                    Text("No chats yet")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                }
                ForEach(appViewModel.globalThreads) { thread in
                    ThreadRowView(
                        thread: thread,
                        isSelected: appViewModel.selectedThreadID == thread.id,
                        onSelect: { appViewModel.selectThread(thread) },
                        onRename: { renameTarget = .thread(thread.id) },
                        onDelete: {
                            appViewModel.deleteThread(id: thread.id)
                        }
                    )
                }
            } header: {
                Text("Chats (global)")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
            }

            // Settings at bottom
            Section {
                Button {
                    openSettingsWindow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                        Text("Settings")
                            .font(.uiLabel)
                    }
                    .foregroundColor(.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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
        // Keyboard shortcuts
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    // MARK: - Top Entry

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
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Settings Window

    private func openSettingsWindow() {
        if let url = URL(string: "swiftagent-settings://settings") {
            NSWorkspace.shared.open(url)
        }
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
                    // Option+Cmd+R → rename current thread
                    if let id = appViewModel.selectedThreadID {
                        renameTarget = .thread(id)
                    }
                    return nil
                }
            case 35: // P key
                if hasCommand && hasOption {
                    // Option+Cmd+P → pin thread (stub)
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
            // Tab picker
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
                    }
                    .buttonStyle(.plain)
                    .background(pluginTab == tab ? Color.bgContent : Color.clear)
                }
                Spacer()
            }
            .background(Color.bgSidebar)

            Divider().background(Color.borderSubtle)

            // Content
            if pluginTab == .skills {
                SkillsView()
            } else {
                MCPConfigView()
            }
        }
        .frame(width: 500, height: 600)
    }
}
