import SwiftUI
import SwiftAgentCore

/// Root view model for the SwiftAgent app.
/// Holds the LLM provider, manages API key setup, serves as the app-wide state,
/// and owns the storage layer + project/thread tracking.
@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - Storage (file-based, CC-compatible)

    /// Primary persistence layer — reads/writes ~/.swift-agent/projects/.
    public let store = SwiftAgentStore()

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
        let vm = threadViewModels[id]
        if vm == nil {
            print("[AppVM] WARNING: selectedThread — threadID=\(id.prefix(8)) NOT found in threadViewModels (count=\(threadViewModels.count))")
        }
        return vm
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
        // File-based storage requires no initialization — just load data.
        loadAllData()
        loadSkills()
        loadMCPServers()
        isStorageReady = true
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

    // MARK: - Load from FS

    /// Load all projects and threads from ~/.swift-agent/projects/.
    public func loadAllData() {
        let discovered = store.discoverProjects()

        var allProjects: [ProjectViewModel] = []
        var vmMap: [String: ThreadViewModel] = [:]
        let globalList: [ThreadViewModel] = []

        for project in discovered {
            let displayName = (project.originalPath as NSString).lastPathComponent
            let pvm = ProjectViewModel(id: project.sanitizedName, name: displayName, path: project.originalPath)
            pvm.isExpanded = true

            // Load sessions for this project.
            // Use the session index entry's projectPath as the authoritative
            // value — it was written by createSession with the correct case.
            // unsanitizePath() is lossy (lowercases), so project.originalPath
            // can differ from the real path on case-sensitive volumes.
            let sessions: [SessionIndexEntry]
            if let loaded = try? store.listSessions(projectPath: project.originalPath) {
                sessions = loaded
            } else {
                // Index corrupted or unreadable — attempt recovery by
                // rebuilding from JSONL files on disk (orphan recovery).
                print("[AppVM] loadAllData: CORRUPT INDEX for \(project.sanitizedName) — attempting rebuild from JSONL files")
                do {
                    try store.rebuildIndex(projectPath: project.originalPath)
                    sessions = (try? store.listSessions(projectPath: project.originalPath)) ?? []
                    print("[AppVM] loadAllData: rebuildIndex recovered \(sessions.count) sessions for \(project.sanitizedName)")
                } catch {
                    print("[AppVM] loadAllData: rebuildIndex FAILED for \(project.sanitizedName): \(error)")
                    sessions = []
                }
            }
            if !sessions.isEmpty {
                // Restore the project path from the first session's authoritative
                // projectPath so the path survives case-preserving round-trip.
                if let correctPath = sessions.first?.projectPath {
                    pvm.path = correctPath
                }
                for session in sessions {
                    // Validate: skip sessions whose JSONL doesn't exist in
                    // this project directory (stale/corrupt index entry).
                    let transcriptPath = SwiftAgentPaths.transcriptPath(sessionId: session.sessionId, projectPath: project.originalPath)
                    if !FileManager.default.fileExists(atPath: transcriptPath) {
                        print("[AppVM] loadAllData: SKIPPING \(session.sessionId.prefix(8)) — transcript missing at \(transcriptPath)")
                        continue
                    }

                    let vm = ThreadViewModel(
                        id: session.sessionId,
                        agentSession: agentSession,
                        store: store
                    )
                    vm.appViewModel = self
                    vm.projectId = session.projectPath ?? project.originalPath
                    print("[AppVM] loadAllData: session=\(session.sessionId.prefix(8)) projectId=\(vm.projectId ?? "nil") (index.projectPath=\(session.projectPath ?? "nil") discover.originalPath=\(project.originalPath))")
                    vm.title = session.customTitle ?? session.firstPrompt ?? "New Chat"
                    vm.selectedModel = "claude-sonnet-4-6"
                    vm.updatedAt = ISO8601DateFormatter().date(from: session.modified) ?? Date()

                    // Load messages lazily (on thread selection)
                    vmMap[session.sessionId] = vm
                    pvm.threads.append(vm)
                }
                pvm.threads.sort { $0.updatedAt > $1.updatedAt }
            } else {
                // Auto-recovery: the index is empty but there may be orphan JSONL
                // files on disk (e.g. from the ordering bug where createSession was
                // never called). Rebuild the index from JSONL files and reload.
                let dir = SwiftAgentPaths.projectDir(forProjectPath: project.originalPath)
                let jsonlFiles = (try? FileManager.default.contentsOfDirectory(atPath: dir))?
                    .filter { $0.hasSuffix(".jsonl") } ?? []
                if !jsonlFiles.isEmpty {
                    print("[AppVM] loadAllData: EMPTY INDEX but \(jsonlFiles.count) JSONL files exist for \(project.sanitizedName) — auto-rebuilding")
                    do {
                        try store.rebuildIndex(projectPath: project.originalPath)
                        if let recovered = try? store.listSessions(projectPath: project.originalPath), !recovered.isEmpty {
                            if let correctPath = recovered.first?.projectPath {
                                pvm.path = correctPath
                            }
                            for session in recovered {
                                let tp = SwiftAgentPaths.transcriptPath(sessionId: session.sessionId, projectPath: project.originalPath)
                                if !FileManager.default.fileExists(atPath: tp) { continue }
                                let vm = ThreadViewModel(id: session.sessionId, agentSession: agentSession, store: store)
                                vm.appViewModel = self
                                vm.projectId = session.projectPath ?? project.originalPath
                                vm.title = session.customTitle ?? session.firstPrompt ?? "New Chat"
                                vm.selectedModel = "claude-sonnet-4-6"
                                vm.updatedAt = ISO8601DateFormatter().date(from: session.modified) ?? Date()
                                vmMap[session.sessionId] = vm
                                pvm.threads.append(vm)
                            }
                            pvm.threads.sort { $0.updatedAt > $1.updatedAt }
                            print("[AppVM] loadAllData: auto-rebuild recovered \(recovered.count) sessions for \(project.sanitizedName)")
                        }
                    } catch {
                        print("[AppVM] loadAllData: auto-rebuild FAILED for \(project.sanitizedName): \(error)")
                    }
                }
            }

            allProjects.append(pvm)
        }

        self.projects = allProjects.sorted { ($0.threads.first?.updatedAt ?? Date.distantPast) > ($1.threads.first?.updatedAt ?? Date.distantPast) }
        self.threadViewModels = vmMap

        // Separate global threads (those without a matching project)
        // For now, all threads are under projects.
        self.globalThreads = globalList

        // Auto-select first thread and load its messages.
        if selectedThreadID == nil, let thread = allProjects.first?.threads.first {
            selectThread(thread)
            print("[AppVM] loadAllData: auto-selected thread \(thread.id.prefix(8)) (first project's first thread)")
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
        let thread = ThreadViewModel(agentSession: agentSession, store: store)
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
            // Note: selectedThreadID set by caller (createProject)
        } else {
            // Pending: only set selectedThreadID, do NOT add to the
            // sidebar list. The sidebar will show this thread as soon
            // as the user sends the first message.
            selectedThreadID = thread.id
            print("[AppVM] createThread (pending): selectedThreadID=\(thread.id.prefix(8)) projectId=\(projectId ?? "nil")")
        }

        return thread
    }

    /// Promote a pending thread into the visible sidebar list. Called
    /// from `ThreadViewModel.send` once the user has actually started
    /// a conversation.
    public func commitPendingThreadIfNeeded(_ thread: ThreadViewModel) {
        let projectId = thread.projectId
        let cwd = projectId ?? thread.workingDirectory
        print("[AppVM] commitPending thread.id=\(thread.id) projectId=\(projectId ?? "nil")")

        // Only persist if not already registered in the index (e.g. from
        // createProject with persist:true). We check the index, NOT the
        // transcript file, because appendMessage can create the JSONL before
        // createSession has a chance to register the session in the index.
        let alreadyIndexed: Bool
        do {
            alreadyIndexed = try store.sessionIndex.get(sessionId: thread.id, projectPath: cwd) != nil
        } catch {
            alreadyIndexed = false // index missing/corrupt — persist to be safe
        }
        if !alreadyIndexed {
            persistThreadToDB(thread, projectId: projectId)
        }

        // Only promote to sidebar if not already there
        let alreadyInSidebar = projects.contains(where: { $0.threads.contains(where: { $0.id == thread.id }) })
            || globalThreads.contains(where: { $0.id == thread.id })
        if !alreadyInSidebar {
            DispatchQueue.main.async { [self] in
                promoteThreadToSidebar(thread, projectId: projectId)
            }
        }
    }

    /// Insert the thread into the right `projects[].threads` or
    /// `globalThreads` list, sorted by updatedAt (newest first).
    private func promoteThreadToSidebar(_ thread: ThreadViewModel, projectId: String?) {
        if let pid = projectId, let project = projects.first(where: { $0.path.lowercased() == pid.lowercased() }) {
            project.threads.insert(thread, at: 0)
            project.threads.sort { $0.updatedAt > $1.updatedAt }
        } else {
            globalThreads.insert(thread, at: 0)
            globalThreads.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Write the thread to the filesystem (~/.swift-agent/projects/).
    private func persistThreadToDB(_ thread: ThreadViewModel, projectId: String?) {
        let cwd = projectId ?? thread.workingDirectory
        do {
            let result = try store.createSession(
                sessionId: thread.id,
                projectPath: cwd,
                title: thread.title == "New Chat" ? nil : thread.title,
                cwd: cwd
            )
            print("[AppViewModel] Persisted session: \(result.transcriptPath)")
        } catch {
            print("[AppViewModel] Failed to persist thread: \(error)")
        }
    }

    /// Select a thread and load its messages.
    public func selectThread(_ thread: ThreadViewModel) {
        let previousID = selectedThreadID
        selectedThreadID = thread.id
        print("[AppVM] selectThread: \(previousID?.prefix(8) ?? "nil") → \(thread.id.prefix(8)) projectId=\(thread.projectId ?? "nil") title=\(thread.title)")
        if thread.messages.isEmpty {
            thread.loadMessagesFromStore()
        }
    }

    /// Persist thread state change immediately (no-op for file-based storage).
    public func persistThreadState(_ thread: ThreadViewModel) {
        // File-based storage: state is tracked in-memory; sessions-index.json updated on message append.
    }

    /// Persist a message to the session JSONL file.
    public func persistMessage(_ message: PersistedMessage) {
        guard isStorageReady else { return }
        // Message persistence is handled by ThreadViewModel via SwiftAgentStore
    }

    /// Rename a thread (updates sessions-index.json customTitle).
    public func renameThread(id: String, title: String) {
        guard let vm = threadViewModels[id] else { return }
        let cwd = vm.projectId ?? vm.workingDirectory
        do {
            let entry = SessionIndexEntry(
                sessionId: id,
                customTitle: title,
                messageCount: 0,
                created: ISO8601DateFormatter().string(from: Date()),
                modified: ISO8601DateFormatter().string(from: Date()),
                projectPath: cwd,
                isSidechain: false
            )
            try store.sessionIndex.upsert(entry, projectPath: cwd)
            vm.title = title
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
        guard let vm = threadViewModels[id] else { return }
        let cwd = vm.projectId ?? vm.workingDirectory
        do {
            try store.deleteSession(sessionId: id, projectPath: cwd)
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

    /// Create a new project directory and auto-create a thread.
    @discardableResult
    public func createProject(name: String, path: String) -> ProjectViewModel {
        let sanitized = SwiftAgentPaths.sanitizePath(path)
        let vm = ProjectViewModel(id: sanitized, name: name, path: path)
        vm.isExpanded = true

        do {
            try store.createProject(projectPath: path)
            projects.append(vm)

            let threadTitle = "Chat in \(name)"
            let thread = createThread(title: threadTitle, projectId: path, persist: true)
            // Auto-select the newly created thread so the user's first
            // message goes to the correct project, not the previously
            // selected Home thread.
            selectedThreadID = thread.id
            print("[AppVM] createProject: selectedThreadID=\(thread.id.prefix(8)) projectId=\(path)")
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

    /// Delete a project (removes directory and all sessions).
    public func deleteProject(id: String) {
        // Find the project's original path
        guard let project = projects.first(where: { $0.id == id }) else { return }
        do {
            try store.deleteProject(projectPath: project.path)
            loadAllData()
        } catch {
            print("[AppViewModel] Delete project failed: \(error)")
        }
    }

    /// Rename a project (in-memory only; path-based identity).
    public func renameProject(id: String, name: String) {
        if let vm = projects.first(where: { $0.id == id }) {
            vm.name = name
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
