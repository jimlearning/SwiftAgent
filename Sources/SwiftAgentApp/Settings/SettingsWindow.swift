import SwiftUI

/// Represents the currently selected settings tab.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    // Personal
    case general
    case appearance
    case configuration
    case personalization
    case keyboardShortcuts

    // Integrations
    case appshots
    case mcpServers
    case browser
    case computerUse

    // Coding
    case hooks
    case connections
    case git
    case environments
    case worktrees

    // Archived
    case archivedChats

    var id: String { rawValue }

    var category: SettingsCategory {
        switch self {
        case .general, .appearance, .configuration, .personalization, .keyboardShortcuts:
            return .personal
        case .appshots, .mcpServers, .browser, .computerUse:
            return .integrations
        case .hooks, .connections, .git, .environments, .worktrees:
            return .coding
        case .archivedChats:
            return .archived
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .configuration: return "Configuration"
        case .personalization: return "Personalization"
        case .keyboardShortcuts: return "Keyboard shortcuts"
        case .appshots: return "Appshots"
        case .mcpServers: return "MCP Servers"
        case .browser: return "Browser"
        case .computerUse: return "Computer use"
        case .hooks: return "Hooks"
        case .connections: return "Connections"
        case .git: return "Git"
        case .environments: return "Environments"
        case .worktrees: return "Worktrees"
        case .archivedChats: return "Archived chats"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .configuration: return "slider.horizontal.3"
        case .personalization: return "person.text.rectangle"
        case .keyboardShortcuts: return "keyboard"
        case .appshots: return "camera.viewfinder"
        case .mcpServers: return "server.rack"
        case .browser: return "globe"
        case .computerUse: return "desktopcomputer"
        case .hooks: return "arrow.triangle.branch"
        case .connections: return "network"
        case .git: return "arrow.triangle.merge"
        case .environments: return "square.stack.3d.up"
        case .worktrees: return "tree"
        case .archivedChats: return "archivebox"
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case personal = "Personal"
    case integrations = "Integrations"
    case coding = "Coding"
    case archived = "Archived"

    var id: String { rawValue }

    var tabs: [SettingsTab] {
        switch self {
        case .personal:
            return [.general, .appearance, .configuration, .personalization, .keyboardShortcuts]
        case .integrations:
            return [.appshots, .mcpServers, .browser, .computerUse]
        case .coding:
            return [.hooks, .connections, .git, .environments, .worktrees]
        case .archived:
            return [.archivedChats]
        }
    }

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .integrations: return "link"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .archived: return "archivebox.fill"
        }
    }
}

/// Shared settings state persisted to UserDefaults.
@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - General
    @Published var workMode: String = "Agent"
    @Published var defaultPermission: String = "Ask for approval"

    // MARK: - Appearance
    @Published var theme: String = "System"
    @Published var lightAccent: String = "#339CFF"
    @Published var lightBackground: String = "#FFFFFF"
    @Published var lightForeground: String = "#1C1C1C"
    @Published var lightUIFont: String = "SF Pro"
    @Published var lightCodeFont: String = "SF Mono"
    @Published var darkAccent: String = "#339CFF"
    @Published var darkBackground: String = "#1C1C1C"
    @Published var darkForeground: String = "#F5F5F5"
    @Published var darkUIFont: String = "SF Pro"
    @Published var darkCodeFont: String = "SF Mono"
    @Published var translucentSidebar: Bool = true
    @Published var contrast: Double = 50

    // MARK: - Configuration
    @Published var defaultModel: String = "deepseek-chat"
    @Published var defaultReasoningLevel: String = "High"
    @Published var defaultSandboxMode: String = "ask"

    // MARK: - Personalization
    @Published var personality: String = "Pragmatic"
    @Published var customInstructions: String = ""
    @Published var memories: [String] = []

    // MARK: - Integrations
    @Published var appshotsEnabled: Bool = true
    @Published var browserSearchEngine: String = "Google"
    @Published var browserHomepage: String = ""
    @Published var browserAllowList: String = ""

    // MARK: - Coding
    @Published var hooksToml: String = ""
    @Published var sshConnections: [String] = []
    @Published var defaultGitBranch: String = "main"
    @Published var commitMessageTemplate: String = ""
    @Published var pushBehavior: String = "current"
    @Published var currentEnvironment: String = "local"
    @Published var worktreeAutoCleanup: Bool = true
    @Published var worktreeBaseBranch: String = "main"

    // MARK: - Search
    @Published var searchQuery: String = ""

    init() { load() }

    func load() {
        let d = UserDefaults.standard
        workMode = d.string(forKey: "settings.workMode") ?? "Agent"
        defaultPermission = d.string(forKey: "settings.defaultPermission") ?? "Ask for approval"
        theme = d.string(forKey: "settings.theme") ?? "System"
        lightAccent = d.string(forKey: "settings.lightAccent") ?? "#339CFF"
        lightBackground = d.string(forKey: "settings.lightBackground") ?? "#FFFFFF"
        lightForeground = d.string(forKey: "settings.lightForeground") ?? "#1C1C1C"
        lightUIFont = d.string(forKey: "settings.lightUIFont") ?? "SF Pro"
        lightCodeFont = d.string(forKey: "settings.lightCodeFont") ?? "SF Mono"
        darkAccent = d.string(forKey: "settings.darkAccent") ?? "#339CFF"
        darkBackground = d.string(forKey: "settings.darkBackground") ?? "#1C1C1C"
        darkForeground = d.string(forKey: "settings.darkForeground") ?? "#F5F5F5"
        darkUIFont = d.string(forKey: "settings.darkUIFont") ?? "SF Pro"
        darkCodeFont = d.string(forKey: "settings.darkCodeFont") ?? "SF Mono"
        translucentSidebar = d.object(forKey: "settings.translucentSidebar") as? Bool ?? true
        contrast = d.double(forKey: "settings.contrast")
        if contrast == 0 { contrast = 50 }
        defaultModel = d.string(forKey: "settings.defaultModel") ?? "deepseek-chat"
        defaultReasoningLevel = d.string(forKey: "settings.defaultReasoningLevel") ?? "High"
        defaultSandboxMode = d.string(forKey: "settings.defaultSandboxMode") ?? "ask"
        personality = d.string(forKey: "settings.personality") ?? "Pragmatic"
        customInstructions = d.string(forKey: "settings.customInstructions") ?? ""
        memories = d.stringArray(forKey: "settings.memories") ?? []
        appshotsEnabled = d.object(forKey: "settings.appshotsEnabled") as? Bool ?? true
        browserSearchEngine = d.string(forKey: "settings.browserSearchEngine") ?? "Google"
        browserHomepage = d.string(forKey: "settings.browserHomepage") ?? ""
        browserAllowList = d.string(forKey: "settings.browserAllowList") ?? ""
        hooksToml = d.string(forKey: "settings.hooksToml") ?? ""
        sshConnections = d.stringArray(forKey: "settings.sshConnections") ?? []
        defaultGitBranch = d.string(forKey: "settings.defaultGitBranch") ?? "main"
        commitMessageTemplate = d.string(forKey: "settings.commitMessageTemplate") ?? ""
        pushBehavior = d.string(forKey: "settings.pushBehavior") ?? "current"
        currentEnvironment = d.string(forKey: "settings.currentEnvironment") ?? "local"
        worktreeAutoCleanup = d.object(forKey: "settings.worktreeAutoCleanup") as? Bool ?? true
        worktreeBaseBranch = d.string(forKey: "settings.worktreeBaseBranch") ?? "main"
    }

    func save() {
        let d = UserDefaults.standard
        d.set(workMode, forKey: "settings.workMode")
        d.set(defaultPermission, forKey: "settings.defaultPermission")
        d.set(theme, forKey: "settings.theme")
        d.set(lightAccent, forKey: "settings.lightAccent")
        d.set(lightBackground, forKey: "settings.lightBackground")
        d.set(lightForeground, forKey: "settings.lightForeground")
        d.set(lightUIFont, forKey: "settings.lightUIFont")
        d.set(lightCodeFont, forKey: "settings.lightCodeFont")
        d.set(darkAccent, forKey: "settings.darkAccent")
        d.set(darkBackground, forKey: "settings.darkBackground")
        d.set(darkForeground, forKey: "settings.darkForeground")
        d.set(darkUIFont, forKey: "settings.darkUIFont")
        d.set(darkCodeFont, forKey: "settings.darkCodeFont")
        d.set(translucentSidebar, forKey: "settings.translucentSidebar")
        d.set(contrast, forKey: "settings.contrast")
        d.set(defaultModel, forKey: "settings.defaultModel")
        d.set(defaultReasoningLevel, forKey: "settings.defaultReasoningLevel")
        d.set(defaultSandboxMode, forKey: "settings.defaultSandboxMode")
        d.set(personality, forKey: "settings.personality")
        d.set(customInstructions, forKey: "settings.customInstructions")
        d.set(memories, forKey: "settings.memories")
        d.set(appshotsEnabled, forKey: "settings.appshotsEnabled")
        d.set(browserSearchEngine, forKey: "settings.browserSearchEngine")
        d.set(browserHomepage, forKey: "settings.browserHomepage")
        d.set(browserAllowList, forKey: "settings.browserAllowList")
        d.set(hooksToml, forKey: "settings.hooksToml")
        d.set(sshConnections, forKey: "settings.sshConnections")
        d.set(defaultGitBranch, forKey: "settings.defaultGitBranch")
        d.set(commitMessageTemplate, forKey: "settings.commitMessageTemplate")
        d.set(pushBehavior, forKey: "settings.pushBehavior")
        d.set(currentEnvironment, forKey: "settings.currentEnvironment")
        d.set(worktreeAutoCleanup, forKey: "settings.worktreeAutoCleanup")
        d.set(worktreeBaseBranch, forKey: "settings.worktreeBaseBranch")
    }
}

// MARK: - Settings Window

/// Independent Settings window (per §17 #23 — NOT an in-app popup).
struct SettingsWindow: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsTopBar
            Divider().background(Color.borderSubtle)
            HStack(spacing: 0) {
                SettingsSidebarView(selectedTab: $selectedTab)
                    .frame(width: 200)
                    .background(Color.bgSidebar)
                Divider().background(Color.borderSubtle)
                settingsContent(for: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgContent)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .preferredColorScheme(.dark)
        .environmentObject(viewModel)
        .onChange(of: selectedTab) { _, _ in
            viewModel.save()
        }
    }

    private var settingsTopBar: some View {
        HStack {
            Button {
                if let window = NSApp.keyWindow {
                    window.close()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Back to app")
                        .font(.system(size: 13))
                }
                .foregroundColor(.accentPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to app")
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                    .font(.system(size: 12))
                TextField("Search settings...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                    .frame(width: 200)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
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
            .background(Color.bgInput)
            .cornerRadius(6)
            .accessibilityLabel("Search settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgElevated)
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch tab {
                case .general: GeneralSettingsView()
                case .appearance: AppearanceSettingsView()
                case .configuration: ConfigurationSettingsView()
                case .personalization: PersonalizationSettingsView()
                case .keyboardShortcuts: KeyboardShortcutsSettingsView()
                case .appshots: AppshotsSettingsView()
                case .mcpServers: MCPServersSettingsView()
                case .browser: BrowserSettingsView()
                case .computerUse: ComputerUseSettingsView()
                case .hooks: HooksSettingsView()
                case .connections: ConnectionsSettingsView()
                case .git: GitSettingsView()
                case .environments: EnvironmentsSettingsView()
                case .worktrees: WorktreesSettingsView()
                case .archivedChats: ArchivedChatsSettingsView()
                }
            }
        }
    }
}

struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsCategory.allCases) { category in
                Section {
                    ForEach(category.tabs) { tab in
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(tab.title)
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, 2)
                        .tag(tab)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(.system(size: 10))
                        Text(category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.textTertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}
