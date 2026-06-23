import SwiftUI
import AppKit
import Combine

// MARK: - AppKitChatBridge

/// SwiftUI `NSViewRepresentable` that hosts a scrollable `ChatTableView`
/// (NSTableView-based chat with cell reuse, streaming in-place updates,
/// and multi-level folding).
///
/// ## Scroll architecture
///
/// An NSTableView **must** be the `documentView` of an NSScrollView to
	/// actually scroll. This bridge returns `ChatScrollContainer` which hosts
	/// the table inside a standard NSScrollView.
///
/// ## `isNearBottom` sync
///
/// The overlay scroll-to-bottom button in ContentView reads
/// `thread.isNearBottom`. This coordinator observes the clip view's bounds
/// via KVO and pushes the value into the ThreadViewModel so the overlay
/// stays in sync.
///
/// - Observes `ThreadViewModel.messages` via Combine
/// - Creates/mutates rows in `ChatTableView` for each `AgentMessage`
/// - Thread-safe: all mutations on @MainActor
public struct AppKitChatBridge: NSViewRepresentable {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    public init(threadID: String) { self.threadID = threadID }

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> ChatScrollContainer {
        let tableView = ChatTableView()
        let scrollContainer = ChatScrollContainer(tableView: tableView)
        context.coordinator.scrollContainer = scrollContainer
        context.coordinator.tableView = tableView
        context.coordinator.startObserving()
        return scrollContainer
    }

    public func updateNSView(_ nsView: ChatScrollContainer, context: Context) {
        // Sync layout width when SwiftUI resizes us
        let visibleWidth = nsView.contentView.bounds.width
        if visibleWidth > 0 {
            nsView.chatTableView.updateLayoutWidth(visibleWidth)
        }

        guard context.coordinator.currentThreadID != threadID else { return }
        context.coordinator.currentThreadID = threadID
        context.coordinator.scrollContainer = nsView
        context.coordinator.tableView = nsView.chatTableView
        context.coordinator.reloadFromViewModel()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(threadID: threadID, appViewModel: appViewModel)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        fileprivate var currentThreadID: String
        private weak var appViewModel: AppViewModel?
        fileprivate weak var tableView: ChatTableView?
        fileprivate weak var scrollContainer: ChatScrollContainer?

        private var cancellables = Set<AnyCancellable>()
        private var lastMessageCount: Int = 0
        private var lastStreamingBlockCount: Int = 0
        private var isInitialLoad = true
        private let foldState = FoldState()

        /// KVO token for clip-view bounds → `isNearBottom` sync.
        private var clipViewBoundsObserver: NSKeyValueObservation?
        /// Observer for the scroll-to-bottom notification from SwiftUI overlay.
        private var scrollToBottomObserver: NSObjectProtocol?

        fileprivate init(threadID: String, appViewModel: AppViewModel) {
            self.currentThreadID = threadID
            self.appViewModel = appViewModel
            super.init()
        }

        // MARK: - Observation

        fileprivate func startObserving() {
            stopObserving()
            guard let vm = resolveViewModel() else { return }
            lastMessageCount = 0
            lastStreamingBlockCount = 0
            isInitialLoad = true

            // ── Messages ──
            // Throttle to ~60fps — prevents streaming event storms from
            // flooding the main thread with NSTableView layout calls.
            vm.$messages
                .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] messages in self?.handleMessages(messages) }
                .store(in: &cancellables)

            // ── State ──
            vm.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in self?.handleState(state) }
                .store(in: &cancellables)

            // ── isNearBottom KVO ──
            observeNearBottom()

            // ── Scroll-to-bottom notification ──
            scrollToBottomObserver = NotificationCenter.default.addObserver(
                forName: .chatScrollToBottom, object: nil, queue: .main
            ) { [weak self] _ in
                self?.tableView?.autoScrollToBottom(animated: true)
            }
        }

        fileprivate func stopObserving() {
            cancellables.removeAll()
            clipViewBoundsObserver?.invalidate()
            clipViewBoundsObserver = nil
            if let observer = scrollToBottomObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            scrollToBottomObserver = nil
        }

        fileprivate func reloadFromViewModel() {
            stopObserving()
            lastMessageCount = 0
            lastStreamingBlockCount = 0
            isInitialLoad = true
            foldState.reset()
            startObserving()
        }

        // MARK: - isNearBottom Sync

        /// Observe the scroll view's clip view bounds so we can push
        /// `isNearBottom` into the ThreadViewModel for the overlay button.
        private func observeNearBottom() {
            guard let clipView = scrollContainer?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true

            clipViewBoundsObserver = clipView.observe(
                \.bounds, options: [.new, .old]
            ) { [weak self] _, _ in
                guard let self, let vm = self.resolveViewModel() else { return }
                let near = self.tableView?.isNearBottom ?? true
                if vm.isNearBottom != near {
                    vm.isNearBottom = near
                }
            }
        }

        // MARK: - State Handling

        private func handleMessages(_ messages: [AgentMessage]) {
            guard let tv = tableView else { return }

            if isInitialLoad || messages.count == 0 || tv.isEmpty {
                tv.replaceAllMessages(messages, foldState: resolveFoldState(), thoughtTime: resolveThoughtTime())
                lastMessageCount = messages.count
                isInitialLoad = false
                return
            }

            let delta = messages.count - lastMessageCount

            if delta > 0 {
                let newMsgs = Array(messages.suffix(delta))
                for msg in newMsgs {
                    tv.appendMessage(msg, foldState: resolveFoldState(), thoughtTime: resolveThoughtTime())
                    if msg.isStreaming { lastStreamingBlockCount = msg.blocks.count }
                }
                lastMessageCount = messages.count
            } else if delta == 0 {
                if let lastMsg = messages.last, lastMsg.isStreaming {
                    if lastMsg.blocks.count != lastStreamingBlockCount {
                        lastStreamingBlockCount = lastMsg.blocks.count
                        tv.updateMessage(lastMsg, foldState: resolveFoldState(), thoughtTime: resolveThoughtTime())
                    } else {
                        tv.updateLastMessageStreaming(lastMsg)
                    }
                } else if let lastMsg = messages.last {
                    tv.updateMessage(lastMsg, foldState: resolveFoldState(), thoughtTime: resolveThoughtTime())
                }
            } else {
                tv.replaceAllMessages(messages, foldState: resolveFoldState(), thoughtTime: resolveThoughtTime())
                lastMessageCount = messages.count
            }
        }

        private func handleState(_ state: ThreadState) {
            switch state {
            case .executing:
                tableView?.resetScrollSuppression()
            case .done, .failed:
                tableView?.autoScrollToBottom(animated: true)
            case .idle: break
            }
        }

        // MARK: - Helpers

        private func resolveViewModel() -> ThreadViewModel? {
            appViewModel?.threadViewModels[currentThreadID]
        }

        private func resolveFoldState() -> FoldState {
            foldState
        }

        private func resolveThoughtTime() -> String? {
            guard let vm = resolveViewModel() else { return nil }
            guard let lastMsg = vm.messages.last,
                  lastMsg.role == .assistant, !lastMsg.isStreaming,
                  lastMsg.blocks.contains(where: { $0.thinkingContent != nil })
            else { return nil }
            return vm.thoughtTimeString
        }
    }
}
