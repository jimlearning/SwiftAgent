import SwiftUI

/// Center pane: thread toolbar + message list + composer.
///
/// Reads the currently selected thread from `AppViewModel` via `@EnvironmentObject`
/// (rather than receiving a `ThreadViewModel` value through the initializer).
/// This guarantees that any `@Published` mutation inside the thread — including
/// `messages`, `state`, and `thoughtTimeString` — drives a redraw of every
/// child view that reads those properties, including the message list, the
/// composer send-button state, and the "Thought for Xs" status row.
///
/// Using a single source of truth through `AppViewModel` also avoids stale
/// closure captures that occur when a parent view rebuilds with a new
/// thread reference but the child view's callback still points at the old one.
public struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var showAPIKeyInput: Bool = false
    @State private var apiKeyText: String = ""
    @State private var isRenamingTitle: Bool = false
    @State private var renameTitleText: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let thread = appViewModel.selectedThread {
                toolbarView(thread: thread)

                // API key banner
                if appViewModel.showAPIKeyBanner {
                    apiKeyBanner
                }

                // Message list (main content area)
                MessageListView(threadID: thread.id)
                    .id(thread.id)  // Force-rebuild on thread switch so scroll position resets cleanly

                // Composer at bottom
                ComposerView(threadID: thread.id)
            } else {
                // No thread selected — show actionable empty state
                emptyStateView
            }
        }
        .background(Color.bgContent)
        .onChange(of: appViewModel.apiKeyStatus) { _, newStatus in
            if newStatus == .configured {
                for vm in appViewModel.threadViewModels.values {
                    vm.setProvider(appViewModel.llmProvider)
                }
            }
        }
    }

    // MARK: - Toolbar

    private func toolbarView(thread: ThreadViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if isRenamingTitle {
                    TextField("Thread title", text: $renameTitleText)
                        .textFieldStyle(.plain)
                        .font(.uiHeadline)
                        .foregroundColor(.textPrimary)
                        .onSubmit {
                            let newTitle = renameTitleText.trimmingCharacters(in: .whitespaces)
                            if !newTitle.isEmpty {
                                thread.title = newTitle
                                appViewModel.renameThread(id: thread.id, title: newTitle)
                            }
                            isRenamingTitle = false
                        }
                        .onExitCommand {
                            isRenamingTitle = false
                        }
                } else {
                    Text(thread.title)
                        .font(.uiHeadline)
                        .foregroundColor(.textPrimary)
                        .onTapGesture(count: 2) {
                            renameTitleText = thread.title
                            isRenamingTitle = true
                        }
                }
                breadcrumb(thread: thread)
            }

            Spacer()

            HStack(spacing: 12) {
                // Environment button (Local/Worktree)
                Button {
                    cycleExecutionEnv(thread: thread)
                } label: {
                    HStack(spacing: 4) {
                        Text(envLabel(thread.executionEnv, thread: thread))
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                // Mode indicator (Plan mode, etc.)
                if thread.mode == "plan" {
                    Text("Planning...")
                        .font(.uiCaption)
                        .foregroundColor(.accentPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentPrimary.opacity(0.15))
                        )
                }

                // Apply to main button (worktree mode)
                if thread.executionEnv == "worktree" {
                    Menu {
                        ForEach(MergeStrategy.allCases, id: \.rawValue) { strategy in
                            Button(strategy.rawValue) {
                                applyWorktree(thread: thread, strategy: strategy)
                            }
                        }
                    } label: {
                        Text("Apply to main")
                            .font(.uiCaption)
                            .foregroundColor(.accentPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.accentPrimary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
    }

    // MARK: - Environment

    private func breadcrumb(thread: ThreadViewModel) -> some View {
        let project = appViewModel.projects.first(where: { $0.threads.contains(where: { $0.id == thread.id }) })
        return Text(project?.name ?? "No project")
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
    }

    private func envLabel(_ env: String, thread: ThreadViewModel) -> String {
        switch env {
        case "worktree": return "Branch: swiftagent/thread-\(String(thread.id.prefix(4)))"
        case "cloud": return "C"
        default: return "L"
        }
    }

    private func cycleExecutionEnv(thread: ThreadViewModel) {
        switch thread.executionEnv {
        case "local": thread.executionEnv = "worktree"
        case "worktree": thread.executionEnv = "local"
        default: thread.executionEnv = "local"
        }
        thread.persistState()
    }

    private func applyWorktree(thread: ThreadViewModel, strategy: MergeStrategy) {
        let manager = AppWorktreeManager()
        Task {
            do {
                try await manager.applyToMain(threadId: thread.id, strategy: strategy)
                await MainActor.run {
                    thread.executionEnv = "local"
                    thread.persistState()
                }
            } catch {
                print("[ContentView] Apply worktree failed: \(error)")
            }
        }
    }

    // MARK: - API Key Banner

    private var apiKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 12))
                .foregroundColor(.warning)
            Text("Please add your DeepSeek API key in Settings → General")
                .font(.uiCaption)
                .foregroundColor(.warning)
            Spacer()
            Button("Set Key") {
                showAPIKeyInput = true
            }
            .font(.uiCaption)
            .foregroundColor(.accentPrimary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bgElevated.opacity(0.5))
        .overlay(alignment: .bottom) {
            Divider().background(Color.borderSubtle)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("SwiftAgent")
                .font(.uiTitle)
                .foregroundColor(.textPrimary)
            Text("Start a new chat to begin coding with AI")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Button {
                let pid = appViewModel.projects.first?.id
                _ = appViewModel.createThread(projectId: pid)
            } label: {
                Label("New Chat", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            Spacer()
        }
    }
}
