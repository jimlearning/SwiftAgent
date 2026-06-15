import SwiftUI

/// Functional composer with 4 controls at the bottom:
/// + (add menu) | ⚙️ Custom⌄ (permission picker) | 5.5 High⌄ (model picker) | ↑ (send)
///
/// - Enter sends, Shift+Enter inserts newline (§6.5)
/// - Typing "/" opens slash command palette
/// - Send button disabled when text empty, shows spinner when executing
/// - Status row ("Thought for Xs") shown above the text area
public struct ComposerView: View {
    @ObservedObject var thread: ThreadViewModel
    @StateObject private var composer = ComposerViewModel()
    @EnvironmentObject var appViewModel: AppViewModel

    /// Callback when send is triggered. The composer text is passed as argument.
    public var onSend: ((String) -> Void)?

    /// Optional callback for slash command execution.
    public var onSlashCommand: ((SlashCommand) -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showAddMenu: Bool = false
    @State private var showPermissionPicker: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var showSlashPalette: Bool = false
    @State private var slashFilter: String = "/"

    public var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderSubtle)

            // Status row (thought time or error)
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

            // Text editor
            textEditorArea
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Control row
            controlRow
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
                    handleSlashCommand(cmd)
                    showSlashPalette = false
                },
                onDismiss: { showSlashPalette = false }
            )
        }
    }

    // MARK: - Text Editor

    private var textEditorArea: some View {
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
                    // Enter sends, Shift+Enter inserts newline
                    if showSlashPalette {
                        // Let the palette handle Enter
                        return .ignored
                    }
                    if keyPress.modifiers.contains(.shift) {
                        // Shift+Enter: insert newline
                        composer.text.append("\n")
                        return .handled
                    }
                    // Enter: send
                    sendAction()
                    return .handled
                }
        }
    }

    // MARK: - Slash Command Detection

    private func checkSlashCommand() {
        let trimmed = composer.text.trimmingCharacters(in: .newlines)
        // Show palette when user types "/" as the first character on a new line
        if trimmed.hasPrefix("/") && !trimmed.contains(" ") && trimmed.count >= 1 && trimmed.count <= 30 {
            slashFilter = trimmed
            showSlashPalette = true
        } else if !trimmed.hasPrefix("/") {
            showSlashPalette = false
        } else {
            // Has space after /, might be a full command
            showSlashPalette = false
        }
    }

    private func handleSlashCommand(_ cmd: SlashCommand) {
        onSlashCommand?(cmd)

        switch cmd.command {
        case "/help":
            composer.text = ""
            // Handled by parent
        case "/plan":
            thread.mode = thread.mode == "plan" ? "code" : "plan"
            composer.text = ""
        case "/clear":
            composer.text = ""
            // Handled by parent (confirmation)
        case "/status":
            // Show status message as a system message
            composer.text = ""
        case "/compact":
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

    private var controlRow: some View {
        HStack(spacing: 8) {
            // + button
            addButton

            // ⚙️ Custom⌄ button
            permissionButton

            Spacer()

            // 5.5 High⌄ button
            modelButton

            // ↑ send button
            sendButton
        }
    }

    // MARK: - + Button

    private var addButton: some View {
        Button {
            showAddMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .foregroundColor(.textSecondary)
        .popover(isPresented: $showAddMenu, arrowEdge: .bottom) {
            AddMenuView(
                onFilePick: {
                    showAddMenu = false
                    openFilePicker()
                },
                onCreateNewFile: {
                    showAddMenu = false
                    // Create new file stub - notify via thread
                },
                onCreateNewProject: {
                    showAddMenu = false
                    // Handled at ContentView level
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
                mcpServerCount: mcpServerCount,
                skillsCount: skillsCount
            )
        }
    }

    private var mcpServerCount: Int {
        // stub — will read from MCPConfigStore in future
        0
    }

    private var skillsCount: Int {
        // stub — will read from SkillsView data in future
        0
    }

    private func openFilePicker() {
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
        .popover(isPresented: $showPermissionPicker, arrowEdge: .bottom) {
            PermissionPickerView(selected: $composer.permissionMode)
        }
    }

    // MARK: - 5.5 High⌄ Button

    private var modelButton: some View {
        Button {
            showModelPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(modelButtonLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
            ModelPickerView(
                selectedModel: $thread.selectedModel,
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

    private var modelButtonLabel: String {
        "\(thread.selectedModel.displayName) \(composer.reasoningStrength.rawValue)"
    }

    // MARK: - ↑ Send Button

    private var sendButton: some View {
        Button(action: sendAction) {
            if composer.isSending {
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
        .foregroundColor(composer.isSendEnabled ? .textPrimary : .textTertiary)
        .background(
            Circle()
                .fill(composer.isSendEnabled ? Color.bgElevated : Color.bgElevated.opacity(0.5))
        )
        .disabled(!composer.isSendEnabled || thread.state.isComposerDisabled)
    }

    // MARK: - Actions

    private func sendAction() {
        guard composer.isSendEnabled, !thread.state.isComposerDisabled else { return }
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        composer.isSending = true
        composer.clear()
        isFocused = false

        onSend?(text)
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
