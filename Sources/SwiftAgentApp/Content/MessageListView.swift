import SwiftUI

/// Scrollable list of thread messages with auto-scroll on new content.
///
/// Uses `VStack` (NOT `LazyVStack`) — LazyVStack's view recycling triggers
/// a main-thread deadlock inside `ScrollView` during scroll deceleration
/// on macOS 26.0. VStack keeps all views in the hierarchy; the static render
/// cache in MessageBubbleView ensures body re-evaluation is a cheap cache hit.
///
/// `onScrollPhaseChange` is also removed — the API itself corrupts ScrollView
/// internal state during the interacting→decelerating transition.
public struct MessageListView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    public var body: some View {
        if let thread = appViewModel.threadViewModels[threadID] {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        if thread.messages.isEmpty {
                            emptyState
                                .id("empty-state")
                        } else {
                            ForEach(thread.messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    thoughtTimeString: thoughtTimeFor(message),
                                    reasoningExpanded: thread.reasoningExpanded,
                                    onToggleReasoning: { thread.reasoningExpanded.toggle() }
                                )
                                .id(message.id)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottomMarker")
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onChange(of: thread.messages.count) { oldCount, newCount in
                    if newCount > oldCount {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: thread.messages.last?.id) { _, _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: thread.messages.last?.content) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: thread.messages.last?.reasoningContent) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: thread.state) { _, newState in
                    if newState == .executing || newState == .done {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
            .onAppear { HangDetector.shared.start() }
        } else {
            Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.textTertiary)
            Text("Send a message to start a conversation")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func thoughtTimeFor(_ message: ThreadMessage) -> String? {
        guard message.role == .assistant,
              message.isStreaming,
              message.content.isEmpty || appViewModel.threadViewModels[threadID]?.messages.last?.id == message.id else {
            return nil
        }
        return appViewModel.threadViewModels[threadID]?.thoughtTimeString
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottomMarker", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomMarker", anchor: .bottom)
        }
    }
}

// MARK: - Main-Thread Hang Detector

/// Background thread that pings the main thread every ~50ms via
/// `DispatchQueue.main.async` + semaphore. Logs a warning if the
/// round-trip exceeds 50ms, or if the main thread is unresponsive
/// for 2+ seconds. Singleton — `.start()` is idempotent.
private final class HangDetector: @unchecked Sendable {
    static let shared = HangDetector()
    private let log = Logger(subsystem: "com.swiftagent.app", category: "HangDetector")
    private var started = false
    private let lock = NSLock()

    private init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true

        DispatchQueue.global(qos: .userInteractive).async { [log] in
            let pingInterval: TimeInterval = 0.050
            let hangThreshold: TimeInterval = 0.050
            var iteration: UInt64 = 0

            while true {
                iteration += 1
                let sem = DispatchSemaphore(value: 0)
                let pingSent = CFAbsoluteTimeGetCurrent()

                DispatchQueue.main.async { sem.signal() }
                let waitResult = sem.wait(timeout: .now() + 2.0)

                let pongReceived = CFAbsoluteTimeGetCurrent()
                let roundTrip = (pongReceived - pingSent) * 1000

                switch waitResult {
                case .success:
                    if roundTrip > hangThreshold {
                        log.warning("[MAIN HANG] iter=\(iteration) blocked=\(String(format: "%.0f", roundTrip))ms")
                    }
                case .timedOut:
                    log.warning("[MAIN HANG] iter=\(iteration) SEMAPHORE TIMEOUT (2s+) — main thread hard-blocked")
                }

                Thread.sleep(forTimeInterval: pingInterval)
            }
        }
    }
}

import OSLog
