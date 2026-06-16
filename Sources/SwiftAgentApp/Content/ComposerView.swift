import SwiftUI

/// Functional composer with 4 controls at the bottom:
/// + (add menu) | ⚙️ Custom⌄ (permission picker) | 5.5 High⌄ (model picker) | ↑ (send)
///
/// - Enter sends, Shift+Enter inserts newline (§6.5)
/// - Typing "/" opens slash command palette
/// - Send button disabled when text empty, shows spinner when executing
/// - Status row ("Thought for Xs") shown above the text area
///
/// Takes a `threadID` and resolves the live `ThreadViewModel` from
/// `AppViewModel` via `@EnvironmentObject` on every render. This is the
/// fix for the "Send a message, the message doesn't appear until I click
/// a different sidebar row" bug: with id-based lookup, every read of
/// `appViewModel.threadViewModels[threadID]?.messages` is a fresh
/// observation, so the Send callback's mutation is immediately visible.
public struct ComposerView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    @StateObject private var composer = ComposerViewModel()

    @FocusState private var isFocused: Bool
    @State private var showAddMenu: Bool = false
    @State private var showPermissionPicker: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var showSlashPalette: Bool = false
    @State private var slashFilter: String = "/"

    public var body: some View {
        if let thread = appViewModel.threadViewModels[threadID] {
            content(thread: thread)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private func content(thread: ThreadViewModel) -> some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderSubtle)

            // Status row (thought time or error)
            statusRow(thread: thread)

            // Text editor
            textEditorArea(thread: thread)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Control row
            controlRow(thread: thread)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(minHeight: 80)
        .background(Color.bgContent)
        .onChange(of: thread.state) { _, newState in
            if newState == .idle || newState == .done {
                composer.isSending = false
            }
            if newState.isComposerDisabled {
                composer.isSending = true
            }
        }
        .onReceive(composer.$text.debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)) { _ in
            composer.updateSendEnabled()
            checkSlashCommand()
        }
        .popover(isPresented: $showSlashPalette, arrowEdge: .top) {
            SlashCommandPalette(
                filterText: $slashFilter,
                onSelect: { cmd in
                    handleSlashCommand(cmd, thread: thread)
                    showSlashPalette = false
                },
                onDismiss: { showSlashPalette = false }
            )
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private func statusRow(thread: ThreadViewModel) -> some View {
        if let thoughtTime = thread.thoughtTimeString, thread.state == .executing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(thoughtTime)
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else if thread.state.isError, let status = thread.state.statusText, !status.isEmpty {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.danger)
                Text(status)
                    .font(.uiCaption)
                    .foregroundColor(.danger)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Text Editor

    private func textEditorArea(thread: ThreadViewModel) -> some View {
        ZStack(alignment: .topLeading) {
            if composer.text.isEmpty && !isFocused {
                Text("Ask for follow-up changes")
                    .font(.uiBody)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $composer.text)
                .font(.uiBody)
                .foregroundColor(.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)
                .frame(minHeight: 28, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(thread.state.isComposerDisabled)
                .onKeyPress(.return, phases: .down) { keyPress in
                    if showSlashPalette {
                        return .ignored
                    }
                    if keyPress.modifiers.contains(.shift) {
                        composer.text.append("\n")
                        return .handled
                    }
                    sendAction(thread: thread)
                    return .handled
                }
        }
    }

    // MARK: - Slash Command Detection

    private func checkSlashCommand() {
        let trimmed = composer.text.trimmingCharacters(in: .newlines)
        if trimmed.hasPrefix("/") && !trimmed.contains(" ") && trimmed.count >= 1 && trimmed.count <= 30 {
            slashFilter = trimmed
            showSlashPalette = true
        } else if !trimmed.hasPrefix("/") {
            showSlashPalette = false
        } else {
            showSlashPalette = false
        }
    }

    private func handleSlashCommand(_ cmd: SlashCommand, thread: ThreadViewModel) {
        switch cmd.command {
        case "/help":
            let helpText = "Available commands: /help, /goal, /plan, /skills, /mcp, /status, /compact, /clear, /personality, /exit"
            let msg = ThreadMessage(role: .assistant, content: helpText, isStreaming: false)
            thread.messages.append(msg)
            composer.text = ""
        case "/plan":
            thread.mode = thread.mode == "plan" ? "code" : "plan"
            thread.persistState()
            composer.text = ""
        case "/goal":
            thread.mode = thread.mode == "goal" ? "code" : "goal"
            thread.persistState()
            composer.text = ""
        case "/skills":
            let skillsText = "Skills view is available via Settings → Skills, or via the + menu → Plugins."
            let msg = ThreadMessage(role: .assistant, content: skillsText, isStreaming: false)
            thread.messages.append(msg)
            composer.text = ""
        case "/mcp":
            let mcpText = "MCP servers are available via Settings → MCP servers, or via the + menu → Plugins."
            let msg = ThreadMessage(role: .assistant, content: mcpText, isStreaming: false)
            thread.messages.append(msg)
            composer.text = ""
        case "/status":
            let statusText = "Thread ID: \(thread.id.prefix(8))...\nModel: \(thread.selectedModel.displayName)\nState: \(thread.persistedState)\nMode: \(thread.mode)"
            let msg = ThreadMessage(role: .assistant, content: statusText, isStreaming: false)
            thread.messages.append(msg)
            composer.text = ""
        case "/clear":
            thread.messages.removeAll()
            let msg = ThreadMessage(role: .assistant, content: "Context cleared.", isStreaming: false)
            thread.messages.append(msg)
            thread.persistState()
            composer.text = ""
        case "/compact":
            let msg = ThreadMessage(role: .assistant, content: "Compacted 0 tokens (compaction engine pending).", isStreaming: false)
            thread.messages.append(msg)
            composer.text = ""
        case "/personality":
            composer.text = ""
        case "/exit":
            composer.text = ""
        default:
            composer.text = ""
        }
    }

    // MARK: - Control Row

    private func controlRow(thread: ThreadViewModel) -> some View {
        HStack(spacing: 8) {
            addButton(thread: thread)
            permissionButton
            Spacer()
            modelButton(thread: thread)
            sendButton(thread: thread)
        }
    }

    // MARK: - + Button (real skills/MCP counts)

    private func addButton(thread: ThreadViewModel) -> some View {
        Button {
            showAddMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(.textSecondary)
        .help("Add — photos, files, plan mode, plugins")
        .popover(isPresented: $showAddMenu, arrowEdge: .bottom) {
            AddMenuView(
                onFilePick: {
                    showAddMenu = false
                    openFilePicker(thread: thread)
                },
                onCreateNewFile: {
                    showAddMenu = false
                },
                onCreateNewProject: {
                    showAddMenu = false
                },
                onTogglePlanMode: {
                    showAddMenu = false
                    thread.mode = thread.mode == "plan" ? "code" : "plan"
                    thread.persistState()
                },
                onToggleGoalMode: {
                    showAddMenu = false
                    thread.mode = thread.mode == "goal" ? "code" : "goal"
                    thread.persistState()
                },
                onTriggerAppshot: {
                    showAddMenu = false
                    Task { await GlobalHotkeyManager.shared.triggerManualCapture() }
                },
                planModeOn: thread.mode == "plan",
                goalModeOn: thread.mode == "goal",
                mcpServerCount: appViewModel.mcpServers.count,
                skillsCount: appViewModel.skills.count
            )
        }
    }

    private func openFilePicker(thread: ThreadViewModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let msg = ThreadMessage(
                        role: .user,
                        content: "[File attached: \(url.lastPathComponent)]",
                        isStreaming: false
                    )
                    thread.messages.append(msg)
                }
            }
        }
    }

    // MARK: - ⚙️ Custom⌄ Button

    private var permissionButton: some View {
        Button {
            showPermissionPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                Text(composer.permissionMode.displayLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Permission mode — controls what the agent can do without asking")
        .popover(isPresented: $showPermissionPicker, arrowEdge: .bottom) {
            PermissionPickerView(selected: $composer.permissionMode)
        }
    }

    // MARK: - 5.5 High⌄ Button

    private func modelButton(thread: ThreadViewModel) -> some View {
        Button {
            showModelPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(modelButtonLabel(thread: thread))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Model and reasoning strength")
        .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
            ModelPickerView(
                selectedModel: Binding(
                    get: { thread.selectedModel },
                    set: { thread.selectedModel = $0 }
                ),
                reasoningStrength: $composer.reasoningStrength
            )
            .onChange(of: thread.selectedModel) { _, _ in
                showModelPicker = false
            }
            .onChange(of: composer.reasoningStrength) { _, _ in
                showModelPicker = false
            }
        }
    }

    private func modelButtonLabel(thread: ThreadViewModel) -> String {
        "\(thread.selectedModel.displayName) \(composer.reasoningStrength.rawValue)"
    }

    // MARK: - ↑ Send Button

    private func sendButton(thread: ThreadViewModel) -> some View {
        Button(action: { sendAction(thread: thread) }) {
            if composer.isSending || thread.state == .executing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(composer.isSendEnabled && !thread.state.isComposerDisabled ? .textPrimary : .textTertiary)
        .background(
            Circle()
                .fill((composer.isSendEnabled && !thread.state.isComposerDisabled) ? Color.bgElevated : Color.bgElevated.opacity(0.5))
        )
        .disabled(!composer.isSendEnabled || thread.state.isComposerDisabled)
        .help("Send (Enter)")
    }

    // MARK: - Actions

    private func sendAction(thread: ThreadViewModel) {
        guard composer.isSendEnabled, !thread.state.isComposerDisabled else { return }
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        composer.isSending = true
        composer.clear()
        isFocused = false

        thread.send(userText: text)
    }
}

// MARK: - PermissionMode display label

extension PermissionMode {
    var displayLabel: String {
        switch self {
        case .askForApproval: return "Ask"
        case .approveForMe: return "Approve"
        case .fullAccess: return "Full"
        case .custom: return "Custom"
        }
    }
}
