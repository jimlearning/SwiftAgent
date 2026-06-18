import SwiftUI
import AppKit

@main
struct SwiftAgentAppEntry: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var urlRouter = URLRouter()
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var rightTabsStore = RightTabsStore()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var errorPresenter = ErrorPresenter.shared

    /// `openWindow` is the SwiftUI-native way to present a separately
    /// declared `Window` scene (e.g. the Settings window) — calling
    /// `NSWorkspace.open(scheme://...)` triggers macOS's
    /// "no app registered to handle this URL" alert.
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window
        Window("SwiftAgent", id: "main") {
            ZStack {
                MainContentView()
                    .environmentObject(appViewModel)
                    .environmentObject(urlRouter)
                    .environmentObject(rightTabsStore)
                    .environmentObject(errorPresenter)
                    .frame(minWidth: 980, minHeight: 640)

                // Error banner overlay (top)
                if !errorPresenter.activeErrors.isEmpty {
                    VStack {
                        ForEach(errorPresenter.activeErrors, id: \.id) { error in
                            if error.severity == .retryable {
                                ErrorBannerView(
                                    error: error,
                                    onDismiss: { errorPresenter.dismiss(error) },
                                    onAction: {
                                        handleRetryableAction(error)
                                    }
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        Spacer()
                    }
                }

                // Error toast overlay (bottom)
                if !errorPresenter.activeErrors.isEmpty {
                    VStack {
                        Spacer()
                        ForEach(errorPresenter.activeErrors, id: \.id) { error in
                            if error.severity == .warning {
                                ErrorToastView(
                                    error: error,
                                    onDismiss: { errorPresenter.dismiss(error) }
                                )
                            }
                        }
                    }
                }

                // Error modal
                if errorPresenter.showModal, let modalError = errorPresenter.currentModalError {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { }
                    ErrorModalView(
                        error: modalError,
                        onDismiss: { errorPresenter.dismissModal() },
                        onAction: {
                            handleModalAction(modalError)
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                // Appshot toast overlay
                if hotkeyManager.showToast {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            AppshotToastView(
                                success: hotkeyManager.toastSuccess,
                                message: hotkeyManager.toastMessage
                            )
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: hotkeyManager.showToast)
                }
            }
            .onAppear {
                appViewModel.initializeStorage()
                hotkeyManager.startMonitoring()
                hotkeyManager.onCapture = { [weak appViewModel] capture in
                    guard let appVM = appViewModel else { return }
                    if let thread = appVM.selectedThread {
                        injectAppshot(capture, into: thread)
                    }
                }
            }
            .onDisappear {
                hotkeyManager.stopMonitoring()
            }
            .onOpenURL { url in
                _ = urlRouter.handle(url)
            }
        }
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["swiftagent"])
        .commands {
            // Thread management
            CommandGroup(before: .newItem) {
                Button("New Chat") {
                    _ = appViewModel.createThread()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Quick Chat") {
                    let pid = appViewModel.selectedThread.flatMap { t in
                        appViewModel.projects.first(where: { $0.threads.contains(where: { $0.id == t.id }) })?.id
                    }
                    _ = appViewModel.createThread(title: "Quick Chat", projectId: pid)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("Find") {
                    NotificationCenter.default.post(name: .swiftAgentFocusSearch, object: nil)
                }
                    .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Archive Chat") { }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            // Right tabs — auto-show the right pane when a tab is opened
            // via keyboard shortcut, so the user sees the tab appear.
            CommandGroup(after: .windowArrangement) {
                Button("New Review Tab") { openTabAndShow(type: .review) }
                    .keyboardShortcut("g", modifiers: [.control, .shift])
                Button("New Terminal Tab") { openTabAndShow(type: .terminal) }
                    .keyboardShortcut("`", modifiers: .control)
                Button("New Browser Tab") { openTabAndShow(type: .browser) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Files Tab") { openTabAndShow(type: .files) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("New Side Chat Tab") { openTabAndShow(type: .sideChat) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }

            // Panel toggles — wired to `appViewModel`'s published layout state
            // so the toolbar icons in `ContentView` stay in sync.
            // ⌘B and ⌘⇧B match the macOS-standard hide/show-sidebars
            // shortcuts (Xcode, Mail, Notes).
            CommandGroup(after: .toolbar) {
                Button("Toggle Left Sidebar") {
                    appViewModel.sidebarVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Toggle Right Panel") {
                    appViewModel.rightVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }

            // Close tab
            CommandGroup(after: .windowArrangement) {
                Button("Close Current Tab") {
                    if let id = rightTabsStore.activeTabID {
                        rightTabsStore.close(id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }

        // Settings scene — SwiftUI's macOS-native settings entry. Renders
        // as a standard Settings window (no toolbar with + - x buttons;
        // just a clean macOS title bar + close/min/max). ⌘, is wired up
        // by SwiftUI automatically; we don't need to attach it ourselves.
        Settings {
            SettingsWindow()
                .environmentObject(settingsViewModel)
                .environmentObject(appViewModel)
        }
    }

    /// Open a right-pane tab and auto-show the right pane if hidden.
    /// Wrapped in animation so the pane slides in when the tab appears.
    private func openTabAndShow(type: RightTabType) {
        if !appViewModel.rightVisible {
            withAnimation(.easeInOut(duration: 0.22)) {
                appViewModel.rightVisible = true
            }
        }
        rightTabsStore.openTab(type: type)
    }

    /// Open the Settings window programmatically. SwiftUI's Settings
    /// scene is wired to ⌘, automatically; we route programmatic
    /// opens through `openSettings` (an environment value, available
    /// since macOS 14) which is the canonical Apple way to present it.
    private func openSettingsWindow() {
        // Fallback: if the env value isn't available we post a
        // notification so any view with the env value can react.
        NotificationCenter.default.post(name: .swiftAgentOpenSettings, object: nil)
    }

    /// Inject an appshot capture as a message into the active thread.

    /// Inject an appshot capture as a message into the active thread.
    private func injectAppshot(_ capture: AppshotCapture.AppshotData, into thread: ThreadViewModel) {
        let contextMsg = capture.contextDescription
        let msg = AgentMessage(
            role: .user,
            blocks: [.text(contextMsg)]
        )
        thread.messages.append(msg)
    }

    // MARK: - Error Action Handlers

    private func handleRetryableAction(_ error: AppError) {
        switch error {
        case .invalidAPIKey401:
            openSettingsWindow()
        case .lowBalance402:
            if let url = URL(string: "https://platform.deepseek.com/top_up") {
                NSWorkspace.shared.open(url)
            }
        case .appshotPermissionDenied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .modelError5xx:
            errorPresenter.dismiss(error)
        case .networkProxy:
            openSettingsWindow()
        default:
            errorPresenter.dismiss(error)
        }
    }

    private func handleModalAction(_ error: AppError) {
        switch error {
        case .sandboxDenied:
            errorPresenter.dismissModal()
        case .invalidAPIKey401, .lowBalance402:
            errorPresenter.dismissModal()
            openSettingsWindow()
        case .worktreeConflict:
            errorPresenter.dismissModal()
        case .diffMergeFailed:
            errorPresenter.dismissModal()
        default:
            errorPresenter.dismissModal()
        }
    }
}
