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

    /// The LLM provider (nil if no API key configured).
    @Published public private(set) var llmProvider: AppLLMProvider?

    /// Whether the API key setup banner should be shown.
    @Published public var showAPIKeyBanner: Bool = false

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

    // MARK: - Init

    public init() {
        checkAPIKey()
    }

    /// Initialize storage and load all data. Call on app launch.
    public func initializeStorage() {
        do {
            try storage.initialize()
            loadAllData()
            isStorageReady = true
        } catch {
            print("[AppViewModel] Storage init failed: \(error)")
        }
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
                    llmProvider: llmProvider,
                    storageManager: storage
                )
                vm.update(from: pt)

                // Load messages for this thread
                let messages = try storage.messageRepo.listByThread(threadId: pt.id)
                vm.loadMessages(from: messages)

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
                _ = createThread()
            }
        } catch {
            print("[AppViewModel] Load failed: \(error)")
        }
    }

    // MARK: - Thread Management

    /// Create a new thread (optionally in a project).
    /// Always registers in-memory so the UI updates. DB persistence is best-effort.
    @discardableResult
    public func createThread(title: String = "New Chat", projectId: String? = nil) -> ThreadViewModel {
        let thread = ThreadViewModel(llmProvider: llmProvider, storageManager: storage)
        thread.setProvider(llmProvider)

        let persisted = PersistedThread(
            id: thread.id,
            projectId: projectId,
            title: title
        )

        // Always register in-memory first — the UI must update even if DB fails
        threadViewModels[thread.id] = thread

        if let pid = projectId, let project = projects.first(where: { $0.id == pid }) {
            project.threads.insert(thread, at: 0)
        } else {
            globalThreads.insert(thread, at: 0)
        }

        selectThread(thread)

        // Persist to DB (best-effort, non-blocking for UI)
        do {
            try storage.threadRepo.create(persisted)
        } catch {
            print("[AppViewModel] Failed to persist thread: \(error)")
        }

        return thread
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
                updated.reuseState = thread.reuseState.rawValue
                updated.model = thread.selectedModel.rawValue
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

    /// Check whether an API key is available and configure the provider.
    public func checkAPIKey() {
        if let key = DeepSeekAPIKeyResolver.resolve() {
            let config = DeepSeekConfig(apiKey: key)
            self.llmProvider = AppLLMProvider(config: config)
            self.apiKeyStatus = .configured
            self.showAPIKeyBanner = false
        } else {
            self.llmProvider = nil
            self.apiKeyStatus = .missing
            self.showAPIKeyBanner = true
        }
    }

    /// Save the API key to Keychain and initialize the provider.
    public func saveAPIKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            try KeychainStore.save(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            let config = DeepSeekConfig(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            self.llmProvider = AppLLMProvider(config: config)
            self.apiKeyStatus = .configured
            self.showAPIKeyBanner = false
            // Update providers on all threads
            for vm in threadViewModels.values {
                vm.setProvider(self.llmProvider)
            }
        } catch {
            checkAPIKey()
        }
    }
}
