import SwiftUI
import SwiftAgentCore

/// Root view model for the SwiftAgent app.
/// Holds the LLM provider, manages API key setup, serves as the app-wide state,
/// and owns the storage layer + project/thread tracking.
@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Storage

    public let storage = StorageManager()

    // MARK: - LLM Provider

    /// The unified LLM provider (nil if no API key configured).
    @Published public private(set) var agentProvider: AppAgentProvider?

    /// The agent session manager — bootstraps all Core subsystems.
    @Published public private(set) var agentSession: AgentSessionManager?

    /// Whether the API key setup banner should be shown.
    @Published public var showAPIKeyBanner: Bool = false

    /// Whether the Settings window/sheet should be presented.
    /// Driven by the sidebar Settings button and the ⌘, shortcut.
    /// Routed through the SwiftUI scene in `EntryPoint` so it appears
    /// as an independent `Window` (per §17 #23 anti-pattern — settings
    /// is NOT an in-app popup).
    @Published public var showSettings: Bool = false

    // MARK: - Layout (sidebar / right pane / focus mode)
    //
    // Three independent flags control the three-pane layout so the
    // user can mix-and-match (e.g. right pane only, sidebar + right
    // pane with center collapsed). Toggled from toolbar buttons in
    // `ContentView`; observed by `MainContentView`.
    //
    // Persistence: deliberately NOT persisted across launches — these
    // are transient session preferences. Users re-open the panels
    // they want when they relaunch.

    /// Left sidebar visibility. True = sidebar shown at its default
    /// width; false = sidebar collapsed to 0.
    @Published public var sidebarVisible: Bool = true

    /// User-resizable sidebar width. Clamped to `sidebarWidthRange` by
    /// the DragDivider between sidebar and content.
    @Published public var sidebarWidth: CGFloat = 260

    /// Right pane visibility. True = right pane shown at its default
    /// width; false = right pane collapsed to 0.
    ///
    /// When right pane is hidden, focus mode is forced off — focus mode
    /// hides ContentView, and at least one of ContentView/RightTabsView
    /// must remain visible.
    @Published public var rightVisible: Bool = true {
        didSet {
            if !rightVisible && focusMode {
                focusMode = false
            }
        }
    }

    /// User-resizable right-pane width. Clamped to `rightWidthRange` by
    /// the DragDivider between content and right tabs. Ignored in focus
    /// mode (right pane fills all available space).
    @Published public var rightWidth: CGFloat = 420

    /// Focus mode: the center column (ContentView) is removed from the
    /// layout so the right pane expands to fill the freed space.
    ///
    /// Sidebar state is preserved independently. Focus mode can only
    /// engage when the right pane is visible; the toolbar button is
    /// hidden otherwise.
    @Published public var focusMode: Bool = false {
        didSet {
            if focusMode && !rightVisible {
                rightVisible = true
            }
        }
    }

    /// Whether focus mode can be toggled — only when the right pane is
    /// visible (focus hides ContentView; both center and right can't be
    /// hidden simultaneously).
    public var canFocus: Bool { rightVisible }

    /// Min / max bounds for user-resizable sidebar width.
    public let sidebarWidthRange: ClosedRange<CGFloat> = 180...400

    /// Min / max bounds for user-resizable right-pane width.
    public let rightWidthRange: ClosedRange<CGFloat> = 320...700

    /// The resolved API key (empty if not configured).
    @Published public private(set) var apiKeyStatus: APIKeyStatus = .checking

    public enum APIKeyStatus: Equatable {
        case checking
        case configured
        case missing
    }

    // MARK: - Projects & Threads (loaded from SQLite)

    /// All projects (loaded from DB).
    @Published public var projects: [ProjectViewModel] = []

    /// Global threads (no project).
    @Published public var globalThreads: [ThreadViewModel] = []

    /// All threads keyed by ID.
    @Published public var threadViewModels: [String: ThreadViewModel] = [:]

    /// ID of the currently selected thread.
    @Published public var selectedThreadID: String?

    /// The currently selected thread view model.
    public var selectedThread: ThreadViewModel? {
        guard let id = selectedThreadID else { return nil }
        return threadViewModels[id]
    }

    /// Search filter text.
    @Published public var searchFilter: String = ""

    /// Whether storage is initialized and data is loaded.
    @Published public private(set) var isStorageReady: Bool = false

    /// Files edited in the most recent thread turn — surfaced by the
    /// EditSummaryCard in the conversation stream and by the Review
    /// panel in the right tabs workspace. Updated by `ThreadViewModel`
    /// when streaming completes with file-edit metadata.
    @Published public var lastEditSummary: EditSummary = .empty

    /// Per-file Review entries with real unified-diff content, computed
    /// from `git diff` in the current project. The Review panel binds
    /// to this directly so it shows actual `+N -M` counts instead of
    /// the placeholder `+0 -0` from before.
    @Published public var lastReviewEntries: [DiffSummary.DiffEntry] = []

    /// Per-file Review entries backed by an in-memory git diff cache.
    /// Computed lazily on demand by `refreshDiffSummary()`.
    public func refreshDiffSummary() {
        print("[AgentLoop] DIFF_REFRESH triggered — dispatching to background")
        DiffService.refresh(for: self)
    }

    /// Live list of MCP servers — published so the + menu and Settings page
    /// observe the same source. Empty until MCPConfigStore loads its TOML.
    @Published public var mcpServers: [MCPConfigStore.MCPServerConfig] = []

    /// Live list of available skills — published so the + menu and Settings page
    /// observe the same source. Empty until SkillsViewModel loads SKILL.md files.
    @Published public var skills: [SkillDescriptor] = []

    /// Helper: a Binding into the selected thread's @Published properties.
    /// Used by ComposerView's ModelPicker popover, which needs a Binding
    /// into `selectedModel` to mutate it through the picker UI.
    public func selectedThreadBinding(threadID: String) -> ThreadViewModel {
        // Caller is guaranteed to pass the current selected thread id;
        // we resolve fresh on each access so the Binding sees live mutations.
        guard let vm = threadViewModels[threadID] else {
            // Fallback: return a transient VM so SwiftUI doesn't crash
            return ThreadViewModel()
        }
        return vm
    }

    // MARK: - Init

    public init() {
        checkAPIKey()
    }

    /// Initialize storage and load all data. Call on app launch.
    public func initializeStorage() {
        do {
            try storage.initialize()
            loadAllData()
            loadSkills()
            loadMCPServers()
            isStorageReady = true
        } catch {
            print("[AppViewModel] Storage init failed: \(error)")
        }
    }

    // MARK: - Skills

    /// Load available skills from user/project/system scopes (§10.1).
    /// The Skills library reads SKILL.md files; for v1 we keep an in-memory
    /// snapshot that the + menu and Settings consume.
    public func loadSkills() {
        var collected: [SkillDescriptor] = []

        // User scope: ~/.swiftagent/skills/
        let userSkillsPath = ("~/.swiftagent/skills" as NSString).expandingTildeInPath
        collected.append(contentsOf: scanSkills(at: userSkillsPath, scope: .user))

        // Project scope: use first project's path or home directory
        let cwd = projects.first?.path ?? NSHomeDirectory()
        let projectSkillsPath = (cwd as NSString).appendingPathComponent(".swiftagent/skills")
        collected.append(contentsOf: scanSkills(at: projectSkillsPath, scope: .project))

        // System scope: /etc/swiftagent/skills/ (best-effort, may not exist)
        let systemSkillsPath = "/etc/swiftagent/skills"
        collected.append(contentsOf: scanSkills(at: systemSkillsPath, scope: .system))

        self.skills = collected
    }

    private func scanSkills(at path: String, scope: SkillDescriptor.Scope) -> [SkillDescriptor] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return entries.compactMap { entry -> SkillDescriptor? in
            let skillFile = (path as NSString).appendingPathComponent(entry).appending("/SKILL.md")
            guard fm.fileExists(atPath: skillFile) else { return nil }
            // Read first line as description
            let desc = (try? String(contentsOfFile: skillFile, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { !$0.isEmpty && !$0.hasPrefix("---") }) ?? entry
            return SkillDescriptor(name: entry, description: desc, scope: scope, path: skillFile)
        }
    }

    // MARK: - MCP Servers

    /// Load MCP servers from ~/.swiftagent/config.toml. The list is published
    /// so the Composer + menu and the Settings page reflect live changes.
    public func loadMCPServers() {
        let configPath = ("~/.swiftagent/config.toml" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath) else {
            self.mcpServers = []
            return
        }
        // MCPConfigStore.init doesn't throw on the current implementation
        // (it only fails inside .save() / .addServer() / .updateServer()),
        // so we read the loaded `servers` array directly and log on
        // any future change.
        self.mcpServers = MCPConfigStore().servers
    }

    // MARK: - Load from DB

    /// Load all projects, threads, and messages from the database.
    public func loadAllData() {
        do {
            // Load projects
            let persistedProjects = try storage.projectRepo.listAll()
            self.projects = persistedProjects.map { p in
                let vm = ProjectViewModel(id: p.id, name: p.name, path: p.path)
                vm.isExpanded = true
                return vm
            }

            // Load all threads
            let persistedThreads = try storage.threadRepo.listAll()
            var vmMap: [String: ThreadViewModel] = [:]
            var globalList: [ThreadViewModel] = []

            for pt in persistedThreads {
                let vm = ThreadViewModel(
                    id: pt.id,
                    agentSession: agentSession,
                    storageManager: storage
                )
                vm.appViewModel = self
                vm.update(from: pt)

                // Load messages for this thread (most recent batch)
                let messages = try storage.messageRepo.listByThread(threadId: pt.id, limit: 50, offset: 0)
                vm.loadMessages(from: messages)

                // Track total count for pagination
                let totalCount = try storage.messageRepo.count(threadId: pt.id)
                vm.setTotalMessageCount(totalCount)

                vmMap[pt.id] = vm

                if pt.projectId == nil {
                    globalList.append(vm)
                } else {
                    // Attach to its project
                    if let project = projects.first(where: { $0.id == pt.projectId }) {
                        project.threads.append(vm)
                    } else {
                        // Orphaned thread — put in global
                        globalList.append(vm)
                    }
                }
            }

            self.threadViewModels = vmMap
            self.globalThreads = globalList.sorted { $0.updatedAt > $1.updatedAt }

            // Sort project threads by updatedAt
            for project in projects {
                project.threads.sort { $0.updatedAt > $1.updatedAt }
            }

            // Auto-select first thread if none selected
            if selectedThreadID == nil {
                if let first = globalThreads.first?.id ?? projects.first?.threads.first?.id {
                    selectedThreadID = first
                }
            }

            // First launch: if no threads exist at all, create a default one so
            // the chat UI is immediately visible instead of showing a placeholder.
            if threadViewModels.isEmpty {
                // Create initial thread under the first project if available
                _ = createThread(projectId: projects.first?.id)
            }
        } catch {
            print("[AppViewModel] Load failed: \(error)")
        }
    }

    // MARK: - Thread Management

    /// Create a new thread (optionally in a project).
    ///
    /// When `persist` is `false` (the default for "New chat" button
    /// clicks), the thread is held in memory as the selected thread
    /// but NOT added to the sidebar list and NOT written to the
    /// database. The first time the user actually sends a message,
    /// `commitPendingThreadIfNeeded()` promotes it into the sidebar
    /// list and persists it. This matches the Codex/ChatGPT UX where
    /// clicking "New chat" shows a fresh composer without polluting
    /// the sidebar until real activity occurs.
    @discardableResult
    public func createThread(title: String = "New Chat", projectId: String? = nil, persist: Bool = false) -> ThreadViewModel {
        let thread = ThreadViewModel(agentSession: agentSession, storageManager: storage)
        thread.projectId = projectId
        thread.appViewModel = self
        thread.title = title
        print("[AppVM] createThread projectId=\(projectId ?? "nil") thread.id=\(thread.id) workingDir=\(thread.workingDirectory)")

        // Hook the diff refresh so the Review panel updates after each
        // agent turn completes (whether success or error).
        thread.onStreamComplete = { [weak self] in
            self?.refreshDiffSummary()
        }

        // Hook the first-message promotion: when the user sends the
        // first message, move this thread from "pending" (selected but
        // hidden in sidebar) into a real sidebar entry + DB row.
        thread.onFirstUserMessage = { [weak self] in
            self?.commitPendingThreadIfNeeded(thread)
        }

        // Always keep the thread in the in-memory registry so the
        // composer / message list can look it up by id.
        threadViewModels[thread.id] = thread


        if persist {
            promoteThreadToSidebar(thread, projectId: projectId)
            persistThreadToDB(thread, projectId: projectId)
        } else {
            // Pending: only set selectedThreadID, do NOT add to the
            // sidebar list. The sidebar will show this thread as soon
            // as the user sends the first message.
            selectedThreadID = thread.id
        }

        return thread
    }

    /// Promote a pending thread into the visible sidebar list. Called
    /// from `ThreadViewModel.send` once the user has actually started
    /// a conversation.
    public func commitPendingThreadIfNeeded(_ thread: ThreadViewModel) {
        // Already in the sidebar — nothing to do.
        if let project = projects.first(where: { $0.threads.contains(where: { $0.id == thread.id }) }) {
            _ = project
            return
        }
        if globalThreads.contains(where: { $0.id == thread.id }) {
            return
        }

        // Use the thread's stored projectId — set at creation time by
        // createThread(). Previously this fell back to projects.first?.id,
        // which ignored the project the user actually right-clicked on.
        let projectId = thread.projectId
        print("[AppVM] commitPending thread.id=\(thread.id) projectId=\(projectId ?? "nil")")

        // Persist the thread synchronously BEFORE the async sidebar promotion,
        // so the first message's INSERT (which happens immediately on the same
        // @MainActor run) doesn't hit a foreign key violation on thread_id.
        persistThreadToDB(thread, projectId: projectId)

        DispatchQueue.main.async { [self] in
            promoteThreadToSidebar(thread, projectId: projectId)
        }
    }

    /// Insert the thread into the right `projects[].threads` or
    /// `globalThreads` list, sorted by updatedAt (newest first).
    private func promoteThreadToSidebar(_ thread: ThreadViewModel, projectId: String?) {
        if let pid = projectId, let project = projects.first(where: { $0.id == pid }) {
            project.threads.insert(thread, at: 0)
            project.threads.sort { $0.updatedAt > $1.updatedAt }
        } else {
            globalThreads.insert(thread, at: 0)
            globalThreads.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Write the thread to SQLite. Best-effort; failures are logged.
    private func persistThreadToDB(_ thread: ThreadViewModel, projectId: String?) {
        let persisted = PersistedThread(
            id: thread.id,
            projectId: projectId,
            title: thread.title
        )
        do {
            try storage.threadRepo.create(persisted)
        } catch {
            print("[AppViewModel] Failed to persist thread: \(error)")
        }
    }

    /// Select a thread and load its messages.
    public func selectThread(_ thread: ThreadViewModel) {
        selectedThreadID = thread.id
    }

    /// Persist thread state change immediately.
    public func persistThreadState(_ thread: ThreadViewModel) {
        guard isStorageReady else { return }
        do {
            if let pt = try storage.threadRepo.get(id: thread.id) {
                var updated = pt
                updated.state = thread.persistedState
                updated.model = thread.selectedModel
                try storage.threadRepo.update(updated)
            }
        } catch {
            print("[AppViewModel] Persist state failed: \(error)")
        }
    }

    /// Persist a message immediately.
    public func persistMessage(_ message: PersistedMessage) {
        guard isStorageReady else { return }
        do {
            try storage.messageRepo.append(message)
        } catch {
            print("[AppViewModel] Persist message failed: \(error)")
        }
    }

    /// Rename a thread.
    public func renameThread(id: String, title: String) {
        do {
            try storage.threadRepo.updateTitle(id: id, title: title)
            if let vm = threadViewModels[id] {
                vm.title = title
            }
        } catch {
            print("[AppViewModel] Rename failed: \(error)")
        }
    }

    /// Attach a file to the current thread's composer. The composer
    /// picks it up by reading the published `pendingAttachments` list,
    /// so the file path appears as an @-mention-style chip the user
    /// can edit around before sending.
    @Published public var pendingAttachments: [ComposerAttachment] = []

    public func addFileToComposer(_ url: URL) {
        guard let thread = selectedThread else { return }
        let attachment = ComposerAttachment(
            id: UUID().uuidString,
            kind: .attachFile(path: url.path, displayName: url.lastPathComponent),
            addedAt: Date()
        )
        pendingAttachments.append(attachment)
        // Also drop a placeholder user message so the user can see
        // the attachment represented in the conversation stream.
        let msg = AgentMessage.user("[File: \(url.lastPathComponent)]")
        thread.messages.append(msg)
    }

    /// Delete a thread.
    public func deleteThread(id: String) {
        do {
            try storage.threadRepo.delete(id: id)
            threadViewModels.removeValue(forKey: id)
            globalThreads.removeAll { $0.id == id }
            for project in projects {
                project.threads.removeAll { $0.id == id }
            }
            if selectedThreadID == id {
                selectedThreadID = globalThreads.first?.id
                    ?? projects.first?.threads.first?.id
            }
        } catch {
            print("[AppViewModel] Delete thread failed: \(error)")
        }
    }

    // MARK: - Project Management

    /// Create a new project and auto-create a thread so the chat UI appears immediately.
    @discardableResult
    public func createProject(name: String, path: String) -> ProjectViewModel {
        let project = PersistedProject(name: name, path: path)
        let vm = ProjectViewModel(id: project.id, name: name, path: path)
        vm.isExpanded = true

        do {
            try storage.projectRepo.create(project)
            projects.append(vm)

            let threadTitle = "Chat in \(name)"
            let thread = createThread(title: threadTitle, projectId: project.id)
            vm.threads.append(thread)
        } catch {
            print("[AppViewModel] Create project failed: \(error)")
        }

        return vm
    }

    /// Open an existing folder as a project (auto-names from folder basename).
    @discardableResult
    public func openProject(path: String) -> ProjectViewModel {
        let name = (path as NSString).lastPathComponent
        return createProject(name: name, path: path)
    }

    /// Delete a project (moves threads to global).
    public func deleteProject(id: String) {
        do {
            try storage.projectRepo.delete(id: id)
            loadAllData()
        } catch {
            print("[AppViewModel] Delete project failed: \(error)")
        }
    }

    /// Rename a project.
    public func renameProject(id: String, name: String) {
        do {
            if let project = try storage.projectRepo.get(id: id) {
                var updated = project
                updated.name = name
                try storage.projectRepo.update(updated)
                if let vm = projects.first(where: { $0.id == id }) {
                    vm.name = name
                }
            }
        } catch {
            print("[AppViewModel] Rename project failed: \(error)")
        }
    }

    // MARK: - API Key

    /// Check whether an API key is available and bootstrap the agent session.
    public func checkAPIKey() {
        let provider = AppAgentProvider()
        if provider.isConfigured {
            self.agentProvider = provider
            self.apiKeyStatus = .configured
            self.showAPIKeyBanner = false
            // Bootstrap agent session async
            Task {
                let session = AgentSessionManager(provider: provider)
                let result = await session.bootstrap()
                if result.isBootstrapped {
                    self.agentSession = session
                    // Update all existing thread VMs
                    for vm in threadViewModels.values {
                        vm.setAgentSession(session)
                    }
                } else {
                    // Surface bootstrap errors
                    for error in result.errors {
                        ErrorPresenter.shared.present(.skillLoadFailed(error.message))
                    }
                }
            }
        } else {
            self.agentProvider = nil
            self.agentSession = nil
            self.apiKeyStatus = .missing
            self.showAPIKeyBanner = true
        }
    }

    /// Save the API key to Keychain and bootstrap the agent session.
    public func saveAPIKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            try KeychainStore.save(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            let provider = AppAgentProvider(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            self.agentProvider = provider
            self.apiKeyStatus = .configured
            self.showAPIKeyBanner = false
            // Bootstrap agent session async
            Task {
                let session = AgentSessionManager(provider: provider)
                let result = await session.bootstrap()
                if result.isBootstrapped {
                    self.agentSession = session
                    // Update all existing thread VMs
                    for vm in threadViewModels.values {
                        vm.setAgentSession(session)
                    }
                } else {
                    for error in result.errors {
                        ErrorPresenter.shared.present(.skillLoadFailed(error.message))
                    }
                }
            }
        } catch {
            checkAPIKey()
        }
    }
}
