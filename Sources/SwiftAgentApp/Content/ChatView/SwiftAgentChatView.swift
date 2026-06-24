import SwiftUI

/// Top-level chat view: messageScrollView + InputBarView + StatusLineView.
/// Replaces the old AppKit NSTableView-based chat with a pure SwiftUI
/// architecture modeled on ClarcChatKit's `ChatView`.
public struct SwiftAgentChatView<InputAccessory: View>: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var chatBridge: ChatBridge

    private let inputAccessory: InputAccessory

    public init(@ViewBuilder inputAccessory: () -> InputAccessory) {
        self.inputAccessory = inputAccessory()
        _chatBridge = State(initialValue: ChatBridge(appViewModel: AppViewModel()))
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageScrollView

            InputBarView(accessory: ComposerAccessoryView()) {
                EmptyView()
            }

            StatusLineView()
        }
        .background(ChatTheme.background)
        .onAppear {
            chatBridge = ChatBridge(appViewModel: appViewModel)
            chatBridge.selectedThread = appViewModel.selectedThread
            chatBridge.syncWithAppViewModel()
        }
        .onChange(of: appViewModel.focusMode) { _, _ in
            chatBridge.syncWithAppViewModel()
        }
        .onChange(of: appViewModel.selectedThreadID) { _, newID in
            ChatPerfLogger.onChangeFired("selectedThreadID → \(newID != nil ? "set" : "nil")")
            chatBridge.selectedThread = appViewModel.selectedThread
            if newID != nil { chatBridge.refreshFromThread() }
        }
        .onChange(of: appViewModel.selectedThread?.messages.count) { _, newCount in
            ChatPerfLogger.onChangeFired("messages.count → \(newCount)")
            chatBridge.refreshFromThread()
        }
        .onChange(of: appViewModel.selectedThread?.state) { _, newState in
            ChatPerfLogger.onChangeFired("thread.state → \(String(describing: newState))")
            chatBridge.refreshFromThread()
        }
        .environment(chatBridge)
        .environmentObject(appViewModel)
    }

    // MARK: - Messages

    private var messageScrollView: some View {
        MessageListView()
    }
}

public extension SwiftAgentChatView where InputAccessory == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}
