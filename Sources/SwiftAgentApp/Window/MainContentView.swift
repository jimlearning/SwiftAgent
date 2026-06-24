import Combine
import SwiftUI
import SwiftAgentCore
import ClarcCore
import ClarcChatKit

/// Three-pane workspace with independent sidebar / right-pane /
/// focus-mode toggles.
struct MainContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var chatBridge = ChatBridge()
    @State private var windowState = WindowState()
    @State private var syncCancellables = Set<AnyCancellable>()

    var body: some View {
        HStack(spacing: 0) {
            if appViewModel.sidebarVisible {
                SidebarView()
                    .frame(width: appViewModel.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)

                DragDivider(
                    width: $appViewModel.sidebarWidth,
                    range: appViewModel.sidebarWidthRange,
                    edge: .leading
                )
            }

            if !appViewModel.focusMode {
                ContentView()
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            if !appViewModel.focusMode && appViewModel.rightVisible {
                DragDivider(
                    width: $appViewModel.rightWidth,
                    range: appViewModel.rightWidthRange,
                    inverted: true,
                    edge: .trailing
                )
            }

            if appViewModel.rightVisible {
                RightTabsView()
                    .frame(maxWidth: appViewModel.focusMode ? .infinity : nil)
                    .frame(width: appViewModel.focusMode ? nil : appViewModel.rightWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.bgContent)
        .environment(chatBridge)
        .environment(windowState)
        .task {
            setupChatBridge()
            windowState.currentSessionId = appViewModel.selectedThreadID ?? windowState.newSessionKey
            chatBridge.messages = convertMessages(appViewModel.selectedThread?.messages ?? [])
            updateSelectedProject()
            subscribeToThread()
        }
        .onChange(of: appViewModel.selectedThreadID) { _, newID in
            windowState.currentSessionId = newID ?? windowState.newSessionKey
            chatBridge.messages = convertMessages(appViewModel.selectedThread?.messages ?? [])
            updateSelectedProject()
            subscribeToThread()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appViewModel.sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(appViewModel.sidebarVisible
                      ? "Hide left sidebar (⌘B)"
                      : "Show left sidebar (⌘B)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if appViewModel.rightVisible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            appViewModel.focusMode.toggle()
                        }
                    } label: {
                        Image(systemName: appViewModel.focusMode
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .help(appViewModel.focusMode
                          ? "Exit focus mode (restore center column)"
                          : "Focus mode (hide center, expand right)")
                    .foregroundStyle(appViewModel.focusMode
                                     ? AnyShapeStyle(.tint)
                                     : AnyShapeStyle(.primary))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appViewModel.rightVisible.toggle()
                    }
                } label: {
                    Image(systemName: appViewModel.rightVisible
                          ? "sidebar.squares.right"
                          : "sidebar.right")
                }
                .help(appViewModel.rightVisible
                      ? "Hide right panel (⌘⇧B)"
                      : "Show right panel (⌘⇧B)")
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.22), value: appViewModel.sidebarVisible)
        .animation(.easeInOut(duration: 0.22), value: appViewModel.rightVisible)
        .animation(.easeInOut(duration: 0.22), value: appViewModel.focusMode)
    }

    // MARK: - ChatBridge Wiring

    private func setupChatBridge() {
        chatBridge.sendHandler = { [self] in
            guard let thread = appViewModel.selectedThread else { return }
            let text = windowState.inputText
            windowState.inputText = ""
            thread.send(userText: text)
        }
        chatBridge.cancelStreamingHandler = { [self] in
            appViewModel.selectedThread?.cancel()
        }
    }

    // MARK: - Project Wiring

    private func updateSelectedProject() {
        guard let thread = appViewModel.selectedThread,
              let projectId = thread.projectId,
              let pvm = appViewModel.projects.first(where: { $0.path.lowercased() == projectId.lowercased() })
        else {
            windowState.selectedProject = nil
            return
        }
        windowState.selectedProject = Project(id: UUID(), name: pvm.name, path: pvm.path)
    }

    // MARK: - Thread Observation (Combine → @Observable bridge)

    /// Tears down old subscriptions and re-subscribes to the current thread's
    /// `@Published` publishers so `chatBridge` stays in sync during streaming.
    private func subscribeToThread() {
        syncCancellables.removeAll()
        guard let thread = appViewModel.selectedThread else { return }

        thread.$messages
            .dropFirst()
            .sink { [weak chatBridge] msgs in
                chatBridge?.messages = convertMessages(msgs)
            }
            .store(in: &syncCancellables)

        thread.$state
            .sink { [weak chatBridge, weak thread] state in
                let streaming = state == .executing
                chatBridge?.isStreaming = streaming
                chatBridge?.streamingStartDate = streaming ? thread?.executionStartTime : nil
            }
            .store(in: &syncCancellables)
    }
}

// MARK: - Message Conversion (shared)

/// Converts `[AgentMessage]` → `[ChatMessage]`, merging tool-result blocks
/// into their matching tool-use blocks by `toolUseID` so that tool cards
/// display the tool name and input summary (instead of blank).
private func convertMessages(_ agentMessages: [AgentMessage]) -> [ChatMessage] {
    agentMessages.compactMap { am in
        let role: Role
        switch am.role {
        case .user: role = .user
        case .assistant, .system: role = .assistant
        }

        // First pass: collect tool-use and tool-result blocks so
        // results can be merged into their matching tool-use cards.
        var toolUseMap: [String: (name: String, input: [String: ClarcCore.JSONValue])] = [:]
        var toolResultMap: [String: (content: String, isError: Bool)] = [:]
        for block in am.blocks {
            if case .toolUse(let tb) = block {
                toolUseMap[tb.toolUseID] = (tb.toolName, convertInputJSON(tb.rawInput))
            }
            if case .toolResult(let tr) = block {
                toolResultMap[tr.toolUseID] = (tr.content, tr.isError)
            }
        }

        let blocks: [MessageBlock] = am.blocks.compactMap { block in
            switch block {
            case .text(let text):
                return .text(text)
            case .thinking(let text, let id, _):
                return .thinking(text, id: id)
            case .toolUse(let tb):
                let input = convertInputJSON(tb.rawInput)
                let result = toolResultMap[tb.toolUseID]
                return .toolCall(ToolCall(
                    id: tb.toolUseID,
                    name: tb.toolName,
                    input: input,
                    result: result?.content,
                    isError: result?.isError ?? false
                ))
            case .toolResult(let tr):
                // Skip if already merged into a toolUse above (avoids duplicate IDs).
                if toolUseMap[tr.toolUseID] != nil { return nil }
                // Orphan result with no matching tool use — emit as standalone.
                return .toolCall(ToolCall(
                    id: tr.toolUseID,
                    name: "",
                    input: [:],
                    result: tr.content,
                    isError: tr.isError
                ))
            case .systemReminder(let text):
                return .text(text)
            }
        }
        let isComplete = !am.isStreaming && (agentMessages.last?.id == am.id)
        return ChatMessage(
            id: UUID(uuidString: am.id) ?? UUID(),
            role: role,
            blocks: blocks,
            isStreaming: am.isStreaming,
            isResponseComplete: isComplete,
            timestamp: am.timestamp
        )
    }
}

private func convertInputJSON(_ json: SwiftAgentCore.JSONValue?) -> [String: ClarcCore.JSONValue] {
    guard let json else { return [:] }
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    guard let data = try? encoder.encode(json),
          let obj = try? decoder.decode([String: ClarcCore.JSONValue].self, from: data) else {
        return [:]
    }
    return obj
}
