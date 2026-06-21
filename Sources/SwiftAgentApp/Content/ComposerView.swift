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
            // This should never appear in normal use — indicates the thread
            // ID passed from ContentView doesn't exist in threadViewModels.
            Color.clear.frame(height: 0)
                .onAppear {
                    print("[ComposerView] WARNING: threadID=\(threadID.prefix(8)) NOT found in threadViewModels. This composer will not send messages!")
                }
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
            // Auto-focus composer when agent finishes and no queued messages remain
            if newState != .executing && thread.queueCount == 0 {
                isFocused = true
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
        ComposerTextViewWrapper(
            text: $composer.text,
            placeholder: "Ask for follow-up changes",
            isFocused: isFocused,
            onSend: { sendAction(thread: thread) },
            mentionItems: mentionItems
        )
        .frame(minHeight: 28, maxHeight: 120)
    }

    // MARK: - Mention Items

    /// Build the list of @-mentionable items from current app state.
    private var mentionItems: [MentionItem] {
        var items: [MentionItem] = []

        // Skills
        if let session = appViewModel.agentSession {
            for name in session.skillNames {
                items.append(MentionItem(
                    id: "skill:\(name)",
                    mentionText: "@\(name)",
                    displayName: name,
                    detail: "Skill",
                    kind: .skill
                ))
            }
        }

        // MCP tools
        if let session = appViewModel.agentSession {
            for name in session.mcpServerNames {
                items.append(MentionItem(
                    id: "mcp:\(name)",
                    mentionText: "@\(name)",
                    displayName: name,
                    detail: "MCP Server",
                    kind: .mcp
                ))
            }
        }

        // Threads from sidebar
        for vm in appViewModel.threadViewModels.values {
            let title = vm.title
            guard !title.isEmpty, title != "Untitled", title != "New Chat" else { continue }
            items.append(MentionItem(
                id: "thread:\(vm.id)",
                mentionText: "@\(title)",
                displayName: title,
                detail: "Thread",
                kind: .thread
            ))
        }

        return items
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

    private func handleSlashCommand(_ cmd: SlashCommandDefinition, thread: ThreadViewModel) {
        switch cmd.command {
        case "/help":
            let helpText = "Available commands: /help, /goal, /plan, /skills, /mcp, /status, /compact, /clear, /personality, /model, /exit"
            let msg = ThreadMessage(role: .assistant, content: helpText, isStreaming: false)
            thread.messages.append(msg.agentMessage)
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
            thread.messages.append(msg.agentMessage)
            composer.text = ""
        case "/mcp":
            let mcpText = "MCP servers are available via Settings → MCP servers, or via the + menu → Plugins."
            let msg = ThreadMessage(role: .assistant, content: mcpText, isStreaming: false)
            thread.messages.append(msg.agentMessage)
            composer.text = ""
        case "/status":
            let statusText = "Thread ID: \(thread.id.prefix(8))...\nModel: \(thread.selectedModel)\nState: \(thread.persistedState)\nMode: \(thread.mode)"
            let msg = ThreadMessage(role: .assistant, content: statusText, isStreaming: false)
            thread.messages.append(msg.agentMessage)
            composer.text = ""
        case "/clear":
            thread.messages.removeAll()
            let msg = ThreadMessage(role: .assistant, content: "Context cleared.", isStreaming: false)
            thread.messages.append(msg.agentMessage)
            thread.persistState()
            composer.text = ""
        case "/compact":
            let msg = ThreadMessage(role: .assistant, content: "Compacted 0 tokens (compaction engine pending).", isStreaming: false)
            thread.messages.append(msg.agentMessage)
            composer.text = ""
        case "/model":
            // The model command with argument — show available models
            let models = appViewModel.agentProvider?.availableModels.map(\.modelInfo.id).joined(separator: ", ") ?? "No models available"
            let msg = ThreadMessage(role: .assistant, content: "Available models: \(models)", isStreaming: false)
            thread.messages.append(msg.agentMessage)
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
                    appViewModel.createProject(name: "Untitled", path: NSHomeDirectory())
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Hover region expanded past the 28pt icon to match the rest
        // of the toolbar (≈36×36 hit area + 6pt corners), so the user
        // doesn't have to land on the icon glyph itself.
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        )
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
                    thread.messages.append(msg.agentMessage)
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
            .foregroundColor(.textPrimary)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .cellHoverHighlightTight()
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
                        composer.selectedModel = model
                        thread.selectedModel = model.rawValue
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if composer.selectedModel == model {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            // Three visually distinct layers, all rendered:
            //   1. Model name (textPrimary) — bright white, primary identifier
            //   2. Reasoning strength (textSecondary) — mid-gray, readable
            //      but secondary; intentionally brighter than the chevron
            //      so the text doesn't get visually swallowed by it
            //   3. Chevron (textTertiary) — dim gray, far right with a
            //      larger gap so it reads as a control affordance, not
            //      as part of the reasoning text
            // Both text labels are always rendered — Reasoning is NOT
            // hidden. The chevron is always at the end of the row.
            HStack(spacing: 4) {
                Text(composer.selectedModel.displayName)
                    .foregroundColor(.textPrimary)
                Text(composer.reasoningStrength.rawValue)
                    .foregroundColor(.textSecondary)
                    .padding(.leading, 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .padding(.leading, 4)
            }
            .font(.uiCaption)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .cellHoverHighlightTight()
        .help("Model and reasoning strength")
    }

    // MARK: - ↑ Send / ■ Stop Button

    private func sendButton(thread: ThreadViewModel) -> some View {
        let isExecuting = thread.state == .executing
        let isEnabled = composer.isSendEnabled

        return HStack(spacing: 8) {
            // Queue count badge
            if thread.queueCount > 0 {
                Text("\(thread.queueCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(.trailing, -2)
            }

            // Stop button (visible during execution)
            if isExecuting {
                Button(action: { thread.cancel() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.danger)
                .background(Circle().fill(Color.bgElevated))
                .hoverHighlight(background: Color.danger.opacity(0.15), cornerRadius: 14, padding: EdgeInsets())
                .help("Stop (Esc)")
            }

            // Send button
            Button(action: { sendAction(thread: thread) }) {
                Group {
                    if isExecuting {
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
            .hoverHighlight(
                background: Color.white.opacity(0.08),
                cornerRadius: 14,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
            .disabled(!isEnabled)
            .help(isExecuting ? "Queue message (Enter)" : "Send (Enter)")
        }
    }

    // MARK: - Actions

    private func sendAction(thread: ThreadViewModel) {
        guard composer.isSendEnabled else { return }
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        print("[ComposerView] sendAction: threadID=\(thread.id.prefix(8)) projectId=\(thread.projectId ?? "nil") title=\(thread.title)")

        DispatchQueue.main.async { [self] in
            composer.clear()
            isFocused = false
            thread.send(userText: text)
        }
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
