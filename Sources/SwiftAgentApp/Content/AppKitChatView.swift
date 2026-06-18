import SwiftUI
import AppKit
import Combine

// MARK: - Debug Logging

private let kDebugBridge = true
private func BDLog(_ msg: String) {
    if kDebugBridge { print("[Bridge] \(msg)") }
}

// MARK: - AppKitChatView

/// SwiftUI `NSViewRepresentable` bridge that hosts the AppKit-based chat
/// message list in a SwiftUI layout.
///
/// Observes `ThreadViewModel` messages via Combine and manages a
/// `ChatScrollView` with `ChatMessageCell` views. During streaming,
/// the last cell is updated in-place (no view recreation) for smooth
/// rendering. Auto-scroll is suppressed when the user scrolls up to
/// read history, then re-engages when they scroll back to the bottom.
public struct AppKitChatView: NSViewRepresentable {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    public init(threadID: String) {
        self.threadID = threadID
    }

    public func makeNSView(context: Context) -> ChatScrollView {
        BDLog("makeNSView threadID=\(threadID)")
        let scrollView = ChatScrollView()
        // Don't set translatesAutoresizingMaskIntoConstraints — let SwiftUI
        // manage the frame directly via autoresizing.
        context.coordinator.scrollView = scrollView
        context.coordinator.startObserving()
        return scrollView
    }

    public func updateNSView(_ nsView: ChatScrollView, context: Context) {
        BDLog("updateNSView threadID=\(threadID) current=\(context.coordinator.currentThreadID) frame=\(nsView.frame)")
        if context.coordinator.currentThreadID != threadID {
            BDLog("  thread changed, re-observing")
            context.coordinator.stopObserving()
            context.coordinator.currentThreadID = threadID
            context.coordinator.scrollView = nsView
            context.coordinator.startObserving()
        }
        // After SwiftUI sets the frame, sync layoutWidth and trigger layout if needed.
        // setFrameSize already synced layoutWidth; we just need to ensure the document
        // is laid out at the correct width.
        if nsView.frame.width > 0 && nsView.chatDocument.layoutWidth > 0 {
            nsView.chatDocument.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
            BDLog("updateNSView post-layout docHeight=\(nsView.chatDocument.frame.height)")
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(threadID: threadID, appViewModel: appViewModel)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        fileprivate var currentThreadID: String
        private weak var appViewModel: AppViewModel?
        fileprivate weak var scrollView: ChatScrollView?

        private var messagesCancellable: AnyCancellable?
        private var stateCancellable: AnyCancellable?
        private var reasoningCancellable: AnyCancellable?
        private var thoughtTimeCancellable: AnyCancellable?

        /// Track the last known message count for diffing.
        private var lastMessageCount: Int = 0
        /// Track the last streaming message ID for in-place updates.
        private var lastStreamingMessageID: String?
        /// Track the block count of the streaming message for in-place vs full-rebuild decision.
        private var lastStreamingBlockCount: Int = 0

        init(threadID: String, appViewModel: AppViewModel) {
            self.currentThreadID = threadID
            self.appViewModel = appViewModel
            super.init()
        }

        // NOTE: deinit intentionally omitted — @MainActor Coordinator
        // cannot have a synchronous deinit. AnyCancellable auto-cancels,
        // and stopObserving() is called explicitly on thread switch.

        // MARK: - Observation

        func startObserving() {
            guard let vm = resolveViewModel() else { return }
            stopObserving()

            // Observe messages array
            messagesCancellable = vm.$messages
                .receive(on: DispatchQueue.main)
                .sink { [weak self] messages in
                    self?.handleMessagesChanged(messages)
                }

            // Observe thread state (for scroll reset on send)
            stateCancellable = vm.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.handleStateChanged(state)
                }

            // Observe reasoning expanded toggle
            reasoningCancellable = vm.$reasoningExpanded
                .receive(on: DispatchQueue.main)
                .sink { [weak self] expanded in
                    self?.updateReasoningExpanded(expanded)
                }

            // Observe thought time string
            thoughtTimeCancellable = vm.$thoughtTimeString
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshLastCellIfStreaming()
                }

            // Initial load
            handleMessagesChanged(vm.messages, isInitial: true)
        }

        func stopObserving() {
            messagesCancellable?.cancel()
            stateCancellable?.cancel()
            reasoningCancellable?.cancel()
            thoughtTimeCancellable?.cancel()
            messagesCancellable = nil
            stateCancellable = nil
            reasoningCancellable = nil
            thoughtTimeCancellable = nil
            lastMessageCount = 0
            lastStreamingMessageID = nil
            lastStreamingBlockCount = 0
        }

        // MARK: - State Handlers

        private func handleStateChanged(_ state: ThreadState) {
            BDLog("handleStateChanged: \(state)")
            switch state {
            case .executing:
                // Reset scroll suppression so user sees streaming
                scrollView?.resetScrollSuppression()
            case .done, .failed:
                // Final scroll to bottom
                scrollView?.autoScrollToBottom(animated: true)
            case .idle:
                break
            }
        }

        private func handleMessagesChanged(_ messages: [AgentMessage], isInitial: Bool = false) {
            guard let scrollView = scrollView else { return }
            let doc = scrollView.chatDocument

            if isInitial || messages.count == 0 || doc.cells.isEmpty {
                // Full rebuild
                rebuildAllCells(messages: messages)
                lastMessageCount = messages.count
                return
            }

            let delta = messages.count - lastMessageCount

            if delta > 0 {
                // New messages added
                let newMessages = Array(messages.suffix(delta))
                for msg in newMessages {
                    let cell = makeCell(for: msg)
                    scrollView.appendCell(cell)
                    if msg.isStreaming {
                        lastStreamingBlockCount = msg.blocks.count
                    }
                }
                lastMessageCount = messages.count

            } else if delta == 0 {
                // Same count — streaming update to last message
                if let lastMsg = messages.last, lastMsg.isStreaming {
                    updateStreamingCell(lastMsg)
                } else {
                    // Non-streaming update — could be a block structure change
                    // (e.g., tool results added). Rebuild the last cell.
                    if let lastMsg = messages.last {
                        let cell = makeCell(for: lastMsg)
                        replaceLastCell(cell)
                    }
                }

            } else {
                // Messages removed (shouldn't happen in normal flow, but handle)
                rebuildAllCells(messages: messages)
                lastMessageCount = messages.count
            }
        }

        // MARK: - Cell Operations

        private func makeCell(for message: AgentMessage) -> ChatMessageCell {
            let cell = ChatMessageCell()
            let vm = resolveViewModel()
            configureCell(cell, with: message, vm: vm)
            return cell
        }

        private func configureCell(
            _ cell: ChatMessageCell,
            with message: AgentMessage,
            vm: ThreadViewModel?
        ) {
            let thoughtTime: String? = {
                guard message.role == .assistant,
                      message.isStreaming,
                      message.blocks.allSatisfy({ $0.textContent?.isEmpty ?? true }),
                      vm?.messages.last?.id == message.id else {
                    return nil
                }
                return vm?.thoughtTimeString
            }()

            cell.configure(
                with: message,
                isStreaming: message.isStreaming,
                thoughtTimeString: thoughtTime,
                reasoningExpanded: vm?.reasoningExpanded ?? false
            )

            cell.onToggleReasoning = { [weak vm] in
                vm?.reasoningExpanded.toggle()
            }
        }

        private func rebuildAllCells(messages: [AgentMessage]) {
            guard let scrollView = scrollView else { return }
            let vm = resolveViewModel()
            let cells: [ChatMessageCell] = messages.map { msg in
                let cell = ChatMessageCell()
                configureCell(cell, with: msg, vm: vm)
                return cell
            }
            scrollView.replaceAllCells(with: cells)
        }

        private func updateStreamingCell(_ message: AgentMessage) {
            guard let scrollView = scrollView,
                  let lastCell = scrollView.chatDocument.lastCell else { return }
            let vm = resolveViewModel()

            // Compare message block count (not cell view count — cell adds
            // extra views like thought-time label and spacer).
            if message.blocks.count == lastStreamingBlockCount {
                // Block structure unchanged — update text in-place
                for (i, block) in message.blocks.enumerated() {
                    if case .text(let text) = block {
                        _ = lastCell.updateBlockText(at: i, text: text)
                    } else if case .thinking(let text, _) = block {
                        _ = lastCell.updateBlockText(at: i, text: text)
                    }
                }
                // Synchronous layout needed: text width change → cell height change
                // → document height change. Without this, autoScrollToBottom uses
                // stale document dimensions and the UI shows mismatched frames.
                lastCell.needsLayout = true
                scrollView.chatDocument.needsLayout = true
                scrollView.layoutSubtreeIfNeeded()
                scrollView.autoScrollToBottom(animated: false)
                return
            }

            // Block structure changed (new thinking, tool use, etc.) — full rebuild
            lastStreamingBlockCount = message.blocks.count
            configureCell(lastCell, with: message, vm: vm)
            scrollView.relayoutDocument()
        }

        private func replaceLastCell(_ cell: ChatMessageCell) {
            guard let scrollView = scrollView else { return }
            scrollView.updateLastCell(cell)
        }

        private func refreshLastCellIfStreaming() {
            guard let scrollView = scrollView,
                  let lastCell = scrollView.chatDocument.lastCell,
                  let vm = resolveViewModel(),
                  let lastMsg = vm.messages.last,
                  lastMsg.isStreaming else { return }
            // Only update the thought-time label directly — no full rebuild.
            // The thought timer fires every second; full configure() + layout
            // on every tick causes an infinite visual refresh loop.
            if let thoughtTime = vm.thoughtTimeString {
                lastCell.updateThoughtTime(thoughtTime)
            }
        }

        private func updateReasoningExpanded(_ expanded: Bool) {
            guard let scrollView = scrollView else { return }
            for cell in scrollView.chatDocument.cells {
                cell.reasoningExpanded = expanded
            }
            scrollView.chatDocument.needsLayout = true
            scrollView.needsLayout = true
        }

        // MARK: - Helpers

        private func resolveViewModel() -> ThreadViewModel? {
            appViewModel?.threadViewModels[currentThreadID]
        }
    }
}
