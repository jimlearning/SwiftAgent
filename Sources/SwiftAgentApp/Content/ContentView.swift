import SwiftUI

/// Center pane: thread toolbar + message list + composer.
/// Loads the currently selected thread from AppViewModel.
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
                if thread.messages.isEmpty {
                    emptyState
                } else {
                    MessageListView(thread: thread)
                }

                // Composer at bottom
                ComposerView(thread: thread) { text in
                    thread.send(userText: text)
                } onSlashCommand: { cmd in
                    handleSlashCommand(cmd, thread: thread)
                }
            } else {
                // No thread selected
                VStack(spacing: 16) {
                    Spacer()
                    Text("SwiftAgent")
                        .font(.uiTitle)
                        .foregroundColor(.textPrimary)
                    Text("Select a chat from the sidebar or press ⌘N to start")
                        .font(.uiBody)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Hello, SwiftAgent")
                .font(.uiTitle)
                .foregroundColor(.textPrimary)

            if appViewModel.apiKeyStatus == .configured {
                Text("Type a message below to start")
                    .font(.uiBody)
                    .foregroundColor(.textSecondary)
            } else {
                VStack(spacing: 8) {
                    Text("DeepSeek API key required")
                        .font(.uiLabel)
                        .foregroundColor(.textSecondary)
                    apiKeyInputField
                }
            }
            Spacer()
        }
    }

    // MARK: - API Key Input

    private var apiKeyInputField: some View {
        HStack(spacing: 8) {
            SecureField("sk-...", text: $apiKeyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit { saveAPIKey() }

            Button("Save") { saveAPIKey() }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
    }

    private func saveAPIKey() {
        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        appViewModel.saveAPIKey(key)
        apiKeyText = ""
    }

    // MARK: - Slash Commands

    private func handleSlashCommand(_ cmd: SlashCommand, thread: ThreadViewModel) {
        switch cmd.command {
        case "/help":
            // Show help — insert help message as system note
            let helpText = "Available commands: /help, /goal, /plan, /skills, /mcp, /status, /compact, /clear, /personality, /exit"
            let msg = ThreadMessage(role: .assistant, content: helpText, isStreaming: false)
            thread.messages.append(msg)
        case "/status":
            let statusText = "Thread ID: \(thread.id.prefix(8))...\nModel: \(thread.selectedModel.displayName)\nState: \(thread.persistedState)\nMode: \(thread.mode)"
            let msg = ThreadMessage(role: .assistant, content: statusText, isStreaming: false)
            thread.messages.append(msg)
        case "/clear":
            // Clear confirmation
            thread.messages.removeAll()
            let msg = ThreadMessage(role: .assistant, content: "Context cleared.", isStreaming: false)
            thread.messages.append(msg)
            thread.persistState()
        case "/compact":
            let msg = ThreadMessage(role: .assistant, content: "Compacted 0 tokens (stub — compaction engine pending Phase 4).", isStreaming: false)
            thread.messages.append(msg)
        default:
            break
        }
    }
}
