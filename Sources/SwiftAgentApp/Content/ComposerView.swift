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
        // Use SwiftUI's native `Menu` for the dropdown so we get correct
        // positioning, hover highlight, and click-anywhere-in-cell hit-testing
        // out of the box. We attach the actions to the Menu's content via a
        // dedicated `AddMenuContent` so the + icon itself stays a simple
        // tap target without owning the menu state.
        Menu {
            Button {
                openFilePicker(thread: thread)
            } label: {
                Label("Add photos & files", systemImage: "paperclip")
            }
            Menu {
                Button("New File") {
                    // Phase 4 stub — opens an empty Swift file in the current project
                }
                Button("New Project") {
                    appViewModel.createProject(name: "Untitled", path: FileManager.default.currentDirectoryPath)
                }
            } label: {
                Label("Create", systemImage: "plus.square")
            }
            Divider()
            Button {
                thread.mode = thread.mode == "plan" ? "code" : "plan"
                thread.persistState()
            } label: {
                Label("Plan mode", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                thread.mode = thread.mode == "goal" ? "code" : "goal"
                thread.persistState()
            } label: {
                Label("Pursue goal", systemImage: "target")
            }
            Menu {
                PluginsSubmenuContent(
                    mcpServerCount: appViewModel.mcpServers.count,
                    skillsCount: appViewModel.skills.count
                )
            } label: {
                Label("Plugins", systemImage: "puzzlepiece.extension")
            }
            Divider()
            Button {
                Task { await GlobalHotkeyManager.shared.triggerManualCapture() }
            } label: {
                Label("Appshot (Cmd+Cmd)", systemImage: "camera")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add — photos, files, plan mode, plugins")
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
        Menu {
            ForEach(Array(PermissionMode.allCases.enumerated()), id: \.offset) { _, mode in
                Button {
                    composer.permissionMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if composer.permissionMode == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                Text(composer.permissionMode.displayLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Permission mode — controls what the agent can do without asking")
    }

    // MARK: - 5.5 High⌄ Button

    private func modelButton(thread: ThreadViewModel) -> some View {
        Menu {
            // Reasoning strength submenu (left panel equivalent in Codex)
            Menu("Reasoning") {
                ForEach(Array(ReasoningStrength.allCases.enumerated()), id: \.offset) { _, strength in
                    Button {
                        composer.reasoningStrength = strength
                    } label: {
                        HStack {
                            Text(strength.rawValue)
                            if composer.reasoningStrength == strength {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            // Model submenu
            Menu("Model") {
                ForEach(Array(DeepSeekModel.allCases.enumerated()), id: \.offset) { _, model in
                    Button {
                        thread.selectedModel = model
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if thread.selectedModel == model {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(modelButtonLabel(thread: thread))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Model and reasoning strength")
    }

    private func modelButtonLabel(thread: ThreadViewModel) -> String {
        "\(thread.selectedModel.displayName) \(composer.reasoningStrength.rawValue)"
    }

    // MARK: - ↑ Send Button

    private func sendButton(thread: ThreadViewModel) -> some View {
        let isEnabled = composer.isSendEnabled && !thread.state.isComposerDisabled
        return Button(action: { sendAction(thread: thread) }) {
            Group {
                if composer.isSending || thread.state == .executing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isEnabled ? .textPrimary : .textTertiary)
        .background(
            Circle()
                .fill(isEnabled ? Color.bgElevated : Color.bgElevated.opacity(0.5))
        )
        .disabled(!isEnabled)
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
