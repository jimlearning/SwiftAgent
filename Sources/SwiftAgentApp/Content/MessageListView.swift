import SwiftUI

/// Scrollable list of thread messages with auto-scroll on new content.
///
/// Uses `VStack` (NOT `LazyVStack`) — LazyVStack's view recycling triggers
/// a main-thread deadlock inside `ScrollView` during scroll deceleration
/// on macOS 26.0. VStack keeps all views in the hierarchy; the static render
/// cache in MessageBubbleView ensures body re-evaluation is a cheap cache hit.
///
/// Message pagination: by default shows the most recent 50 messages.
/// A "Load earlier messages" button at the top fetches additional history
/// from the database in batches of 50. This keeps the view hierarchy bounded
/// while supporting arbitrarily long conversations.
///
/// `onScrollPhaseChange` is also removed — the API itself corrupts ScrollView
/// internal state during the interacting→decelerating transition.
public struct MessageListView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    /// Number of messages to show initially and per batch.
    private static let batchSize = 50

    public var body: some View {
        if let thread = appViewModel.threadViewModels[threadID] {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        // "Load earlier messages" button — shown when there are more
                        // messages in the database than currently displayed.
                        if thread.hasMoreMessages {
                            loadEarlierButton(thread: thread)
                        }

                        if thread.messages.isEmpty {
                            emptyState
                                .id("empty-state")
                        } else {
                            ForEach(Array(thread.messages)) { agentMsg in
                                MessageBubbleView(
                                    message: agentMsg,
                                    thoughtTimeString: thoughtTimeFor(agentMsg),
                                    reasoningExpanded: thread.reasoningExpanded,
                                    onToggleReasoning: { thread.reasoningExpanded.toggle() }
                                )
                                .id(agentMsg.displayID)
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
                .onChange(of: thread.messages.count) { _, _ in
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

    // MARK: - Load Earlier

    private func loadEarlierButton(thread: ThreadViewModel) -> some View {
        Button {
            thread.loadEarlierMessages(batchSize: Self.batchSize)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 12))
                Text("Load earlier messages")
                    .font(.uiCaption)
            }
            .foregroundColor(.accentPrimary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cellHoverHighlightTight()
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

    private func thoughtTimeFor(_ message: AgentMessage) -> String? {
        guard message.role == .assistant,
              appViewModel.threadViewModels[threadID]?.messages.last?.id == message.id else {
            return nil
        }
        // During streaming: toggle shows "Thinking..." independently.
        if message.isStreaming { return nil }
        // After streaming: show "Thought for Xs" if the message has thinking blocks.
        let hasThinking = message.blocks.contains(where: { $0.thinkingContent != nil })
        guard hasThinking else { return nil }
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
/// `DispatchQueue.main.async` + semaphore. Logs progressively louder
/// warnings at 100ms/500ms/2s thresholds.
///
/// When a 2s+ hard hang is detected, a 1-second `sample` of the process
/// is written to `~/Library/Logs/SwiftAgent/hang-<timestamp>.txt` so the
/// exact blocking call stack can be inspected.
private final class HangDetector: @unchecked Sendable {
    static let shared = HangDetector()
    private let log = Logger(subsystem: "com.swiftagent.app", category: "HangDetector")
    private var started = false
    private let lock = NSLock()

    /// How many hangs have been detected since launch.
    private(set) var hangCount: Int = 0
    private let hangCountLock = NSLock()

    private init() {}

    func start() {
        lock.withLock {
            guard !started else { return }
            started = true
        }

        DispatchQueue.global(qos: .userInteractive).async { [log] in
            let pingInterval: TimeInterval = 0.050
            var iteration: UInt64 = 0

            while true {
                iteration += 1
                let sem = DispatchSemaphore(value: 0)
                let pingSent = CFAbsoluteTimeGetCurrent()

                DispatchQueue.main.async { sem.signal() }
                let waitResult = sem.wait(timeout: .now() + 2.0)

                let roundTrip = (CFAbsoluteTimeGetCurrent() - pingSent) * 1000

                switch waitResult {
                case .success:
                    if roundTrip > 500 {
                        log.warning("[MAIN SLOW] iter=\(iteration) blocked=\(String(format: "%.0f", roundTrip))ms — queue saturated")
                    } else if roundTrip > 100 {
                        // Soft micro-hang — could become worse under load
                    }
                case .timedOut:
                    log.critical("[MAIN HANG] iter=\(iteration) SEMAPHORE TIMEOUT (2s+) — main thread hard-blocked")
                    HangDetector.captureHangSample(iteration: iteration)
                }

                Thread.sleep(forTimeInterval: pingInterval)
            }
        }
    }

    /// Capture a 1-second process sample via `/usr/bin/sample`.
    /// Writes to `~/Library/Logs/SwiftAgent/` for post-mortem analysis.
    private static func captureHangSample(iteration: UInt64) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let logsDir = NSHomeDirectory() + "/Library/Logs/SwiftAgent"
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = dateFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let samplePath = "\(logsDir)/hang-iter\(iteration)-\(timestamp).txt"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(pid)", "1", "-file", samplePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Don't wait — sample runs for 1 second; let it finish in the background
            DispatchQueue.global().async {
                process.waitUntilExit()
                let logger = Logger(subsystem: "com.swiftagent.app", category: "HangDetector")
                if process.terminationStatus == 0 {
                    logger.info("[MAIN HANG] sample captured: \(samplePath, privacy: .public)")
                } else {
                    logger.warning("[MAIN HANG] sample failed (exit \(process.terminationStatus))")
                }
            }
        } catch {
            let logger = Logger(subsystem: "com.swiftagent.app", category: "HangDetector")
            logger.warning("[MAIN HANG] could not launch sample: \(error.localizedDescription)")
        }
    }
}

import OSLog
