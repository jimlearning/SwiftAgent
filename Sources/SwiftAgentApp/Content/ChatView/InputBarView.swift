import SwiftUI

/// Text input bar with send/stop, attachments, and slash/@ popups.
/// Ported from ClarcChatKit's `InputBarView`, adapted to use the existing
/// ComposerTextView for text input instead of pulling in IMETextView.
struct InputBarView<Accessory: View, TopAccessory: View>: View {
    @Environment(ChatBridge.self) private var chatBridge
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isInputFocused: Bool = false
    @FocusState private var textFieldFocus: Bool
    @State private var showSlashPopup = false
    @State private var slashSelectedIndex = 0
    @State private var showAtFilePopup = false
    @State private var atFileSelectedIndex = 0
    @State private var historyIndex: Int = -1

    private let accessory: Accessory
    private let topAccessory: TopAccessory

    init(accessory: Accessory, @ViewBuilder topAccessory: () -> TopAccessory) {
        self.accessory = accessory
        self.topAccessory = topAccessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appViewModel.attachments.isEmpty {
                attachmentPreviews
                    .padding(.horizontal, 16)
                    .transition(.offset(y: 10).combined(with: .opacity))
            }

            if !appViewModel.messageQueue.isEmpty {
                queuedMessagePreviews
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            topAccessory

            inputComposer
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .background(ChatTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusPill))
                .overlay(
                    RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusPill)
                        .strokeBorder(ChatTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 12)
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 4) {
                    if showSlashPopup && !slashFilteredCommands.isEmpty {
                        SlashCommandPopup(
                            query: slashQuery,
                            onSelect: { cmd in selectSlashCommand(cmd) },
                            selectedIndex: $slashSelectedIndex
                        )
                        .transition(.offset(y: 10).combined(with: .opacity))
                    }
                    if showAtFilePopup && !atFileFilteredEntries.isEmpty {
                        AtFilePopup(
                            entries: atFileFilteredEntries,
                            onSelect: { relativePath in selectAtFile(relativePath) },
                            selectedIndex: $atFileSelectedIndex
                        )
                        .transition(.offset(y: 10).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .offset(y: -4)
            .alignmentGuide(.top) { $0[.bottom] }
        }
        .onChange(of: appViewModel.currentSessionId) { _, _ in
            historyIndex = -1
            if !chatBridge.isStreaming {
                processNextQueued()
            }
        }
        .onChange(of: chatBridge.isStreaming) { _, isStreaming in
            if !isStreaming {
                processNextQueued()
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { textFieldFocus = true }
    }

    // MARK: - Input Composer

    @ViewBuilder
    private var inputComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputTextField
            composerActionRow
        }
    }

    private var composerActionRow: some View {
        HStack(spacing: 10) {
            accessory
                .frame(maxWidth: .infinity, alignment: .leading)

            if chatBridge.isStreaming {
                sendButton(isStop: true) {
                    Task { await chatBridge.cancelStreaming() }
                }
            } else if !showSlashPopup {
                sendButton(isStop: false, isEnabled: !appViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appViewModel.attachments.isEmpty) {
                    sendMessage()
                }
            } else {
                sendButton(isStop: false, isEnabled: false) {}
                    .disabled(true)
            }
        }
        .frame(height: 32)
    }

    private func sendButton(isStop: Bool, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isStop ? "stop.fill" : "arrow.up")
                .font(.system(size: ChatTheme.size(14), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isEnabled ? ChatTheme.accent : ChatTheme.textTertiary.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: .command)
    }

    @ViewBuilder
    private var inputTextField: some View {
        TextField("Type a message...", text: Binding(get: { appViewModel.inputText }, set: { appViewModel.inputText = $0 }), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: ChatTheme.size(14)))
            .foregroundStyle(ChatTheme.textPrimary)
            .focused($textFieldFocus)
            .lineLimit(1...10)
            .onSubmit {
                if showSlashPopup && !slashFilteredCommands.isEmpty {
                    let commands = slashFilteredCommands
                    if slashSelectedIndex < commands.count {
                        selectSlashCommand(commands[slashSelectedIndex])
                    }
                    return
                }
                if showAtFilePopup && !atFileFilteredEntries.isEmpty {
                    let entries = atFileFilteredEntries
                    if atFileSelectedIndex < entries.count {
                        selectAtFile(entries[atFileSelectedIndex].relativePath)
                    }
                    return
                }
                sendMessage()
            }
            .onChange(of: appViewModel.inputText) { _, newValue in
                handleInputTextChange(newValue: newValue)
            }
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = appViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !appViewModel.attachments.isEmpty else { return }
        historyIndex = -1

        if chatBridge.isStreaming {
            withAnimation(.easeOut(duration: 0.2)) {
                appViewModel.enqueueMessage(text: appViewModel.inputText, attachments: appViewModel.attachments)
            }
            appViewModel.inputText = ""
            return
        }

        Task { await chatBridge.send() }
    }

    private func processNextQueued() {
        guard let next = appViewModel.dequeueNext() else { return }
        appViewModel.inputText = next.text
        Task { await chatBridge.send() }
    }

    // MARK: - Slash / At Queries

    private var slashQuery: String {
        let text = appViewModel.inputText
        guard !text.contains(" "), text.hasPrefix("/") else { return "" }
        return text
    }

    private var slashFilteredCommands: [SlashCommandAdapter] {
        SlashCommandFilter.filtered(by: slashQuery)
    }

    private var atFileQuery: String {
        let text = appViewModel.inputText
        guard let atRange = text.range(of: "@", options: .backwards) else { return "" }
        let afterAt = String(text[atRange.upperBound...])
        if afterAt.contains(" ") { return "" }
        return afterAt
    }

    private var atFileFilteredEntries: [AtFileEntry] {
        AtFileSearch.search(query: atFileQuery, projectPath: appViewModel.selectedProject?.path ?? "")
    }

    private func selectSlashCommand(_ cmd: SlashCommandAdapter) {
        withAnimation(.easeOut(duration: 0.15)) { showSlashPopup = false }
        if cmd.acceptsInput && !cmd.isInteractive {
            appViewModel.inputText = cmd.command + " "
        } else {
            appViewModel.inputText = ""
            Task { await chatBridge.sendSlashCommand(cmd.command) }
        }
    }

    private func selectAtFile(_ relativePath: String) {
        withAnimation(.easeOut(duration: 0.15)) { showAtFilePopup = false }
        var text = appViewModel.inputText
        if let atRange = text.range(of: "@", options: .backwards) {
            text.replaceSubrange(atRange.lowerBound..., with: "@\(relativePath) ")
        }
        appViewModel.inputText = text
    }

    private func handleInputTextChange(newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        let hasSpaceAfterSlash = newValue.contains(" ")
        let shouldShowSlash = trimmed.hasPrefix("/") && !hasSpaceAfterSlash
        if shouldShowSlash != showSlashPopup {
            withAnimation(.easeOut(duration: 0.15)) { showSlashPopup = shouldShowSlash }
        }
        if shouldShowSlash { slashSelectedIndex = 0 }

        let shouldShowAt = !shouldShowSlash && hasActiveAtQuery(in: newValue)
        if shouldShowAt != showAtFilePopup {
            withAnimation(.easeOut(duration: 0.15)) { showAtFilePopup = shouldShowAt }
        }
        if shouldShowAt { atFileSelectedIndex = 0 }
    }

    private func hasActiveAtQuery(in text: String) -> Bool {
        guard let atRange = text.range(of: "@", options: .backwards) else { return false }
        let afterAt = String(text[atRange.upperBound...])
        return !afterAt.contains(" ")
    }

    // MARK: - Attachment Previews

    private var attachmentPreviews: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appViewModel.attachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: attachment.type == .image ? "photo" : "doc")
                            .font(.system(size: ChatTheme.size(14)))
                            .foregroundStyle(ChatTheme.accent)
                        Text(attachment.name)
                            .font(.caption)
                            .foregroundStyle(ChatTheme.textSecondary)
                            .lineLimit(1)
                        Button {
                            appViewModel.pendingAttachments.removeAll { $0.id == attachment.id.uuidString }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: ChatTheme.size(9), weight: .semibold))
                                .foregroundStyle(ChatTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(ChatTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Queued Message Previews

    private var queuedMessagePreviews: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(appViewModel.messageQueue) { queued in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: ChatTheme.size(10)))
                        .foregroundStyle(ChatTheme.textSecondary.opacity(0.7))

                    Text(queued.text)
                        .font(.system(size: ChatTheme.size(13)))
                        .foregroundStyle(ChatTheme.textSecondary)
                        .lineLimit(3)

                    Button {
                        appViewModel.dequeueMessage(id: queued.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: ChatTheme.size(9), weight: .semibold))
                            .foregroundStyle(ChatTheme.textSecondary)
                            .padding(3)
                            .background(ChatTheme.textSecondary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .frame(maxWidth: 350, alignment: .trailing)
                .opacity(0.9)
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Slash Command Popup

struct SlashCommandPopup: View {
    let query: String
    let onSelect: (SlashCommandAdapter) -> Void
    @Binding var selectedIndex: Int
    @State private var detailCommand: SlashCommandAdapter?

    private var commands: [SlashCommandAdapter] {
        SlashCommandFilter.filtered(by: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.offset) { idx, cmd in
                Button {
                    onSelect(cmd)
                } label: {
                    HStack {
                        Text(cmd.command)
                            .font(.system(size: ChatTheme.size(13), weight: .medium, design: .monospaced))
                            .foregroundStyle(ChatTheme.textPrimary)
                        Spacer()
                        Text(cmd.definition.description)
                            .font(.system(size: ChatTheme.size(12)))
                            .foregroundStyle(ChatTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(idx == selectedIndex ? ChatTheme.accentSubtle : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320)
        .background(ChatTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall)
                .strokeBorder(ChatTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - At File Popup

struct AtFilePopup: View {
    let entries: [AtFileEntry]
    let onSelect: (String) -> Void
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                Button {
                    onSelect(entry.relativePath)
                } label: {
                    HStack {
                        Image(systemName: "doc")
                            .font(.system(size: ChatTheme.size(12)))
                            .foregroundStyle(ChatTheme.textSecondary)
                        Text(entry.relativePath)
                            .font(.system(size: ChatTheme.size(13), design: .monospaced))
                            .foregroundStyle(ChatTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(idx == selectedIndex ? ChatTheme.accentSubtle : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320)
        .background(ChatTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall)
                .strokeBorder(ChatTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
