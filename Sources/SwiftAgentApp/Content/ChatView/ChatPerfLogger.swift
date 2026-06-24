import Foundation
import SwiftUI
import os

/// Lightweight performance debug logger for chat view rendering pipeline.
///
/// Usage: Set `ChatPerfLogger.enabled = true` to activate logging.
/// Each log point includes a high-precision timestamp (ms since launch)
/// and the calling site.
///
/// Bottleneck categories tracked:
///   A: refreshFromThread — message mapping
///   B: MessageListView body — view evaluation + grouping
///   C: View identity — id computation / diffing
///   D: ToolResultView — body + computed properties
///   E: @Observable notification — onChange firing
///   F: Ongoing animation/timer overhead
///   G: ScrollView interaction — geometry + position
///   H: @ObservableObject chain — nested object invalidation
enum ChatPerfLogger {
    nonisolated(unsafe) static var enabled = false

    private static let signpostLog = OSLog(subsystem: "com.swiftagent.chat", category: "Perf")
    private static let startTime = Date()

    private static func now() -> String {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return String(format: "%.1fms", elapsed)
    }

    // MARK: - A: refreshFromThread

    static func refreshBegin(msgCount: Int) {
        guard enabled else { return }
        os_signpost(.begin, log: signpostLog, name: "refreshFromThread", "count=%d", msgCount)
        print("[ChatPerf:\(now())] A-refresh BEGIN — sourceMsgCount=\(msgCount)")
    }

    static func refreshEnd(fullRebuild: Bool, previousCount: Int, newCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        os_signpost(.end, log: signpostLog, name: "refreshFromThread")
        let mode = fullRebuild ? "FULL" : "PARTIAL"
        print("[ChatPerf:\(now())] A-refresh END — \(mode) prev=\(previousCount)→new=\(newCount) took=\(String(format: "%.2f", elapsedMs))ms")
    }

    // MARK: - B: MessageListView body

    static func msgListBodyBegin(settledCount: Int, isStreaming: Bool) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] B-msgListBody BEGIN — settled=\(settledCount) streaming=\(isStreaming)")
    }

    static func msgListBodyEnd(elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 5 {
            print("[ChatPerf:\(now())] B-msgListBody END ⚠️ SLOW — took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - B2: groupMessages

    static func groupMessagesBegin(count: Int) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] B2-groupMessages BEGIN — msgCount=\(count)")
    }

    static func groupMessagesEnd(groupCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 2 {
            print("[ChatPerf:\(now())] B2-groupMessages END — groups=\(groupCount) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - B3: StreamingMessageView body

    static func streamingViewBodyBegin(activeCount: Int) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] B3-streamingView BEGIN — active=\(activeCount)")
    }

    static func streamingViewBodyEnd(elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 3 {
            print("[ChatPerf:\(now())] B3-streamingView END ⚠️ SLOW — took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - B4: rebuildSettledItems

    static func rebuildSettledBegin(totalMsg: Int) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] B4-rebuildSettled BEGIN — totalMessages=\(totalMsg)")
    }

    static func rebuildSettledEnd(settledCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 3 {
            print("[ChatPerf:\(now())] B4-rebuildSettled END — settled=\(settledCount) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - C: View identity / block building

    static func buildBlocksBegin(msgId: String, blockCount: Int) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] C-buildBlocks BEGIN — msgId=\(String(msgId.prefix(8))) blocks=\(blockCount)")
    }

    static func buildBlocksEnd(resultCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 1 {
            print("[ChatPerf:\(now())] C-buildBlocks END — resultBlocks=\(resultCount) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    static func messageInitSlow(msgId: String, blockCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 2 {
            print("[ChatPerf:\(now())] C-msgInit ⚠️ SLOW — msgId=\(String(msgId.prefix(8))) blocks=\(blockCount) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - D: MessageBubbleView body

    static func bubbleBodyBegin(msgId: String, blockCount: Int) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] D-bubbleBody BEGIN — msgId=\(String(msgId.prefix(8))) blocks=\(blockCount)")
    }

    static func bubbleBodyEnd(elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 2 {
            print("[ChatPerf:\(now())] D-bubbleBody END ⚠️ SLOW — took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    static func visibleBlocksCompute(msgId: String, inputCount: Int, outputCount: Int, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 1 {
            print("[ChatPerf:\(now())] D-visibleBlocks — msgId=\(String(msgId.prefix(8))) \(inputCount)→\(outputCount) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - D2: ToolResultView body

    static func toolResultBodyBegin(toolName: String) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] D2-toolResult BEGIN — tool=\(toolName)")
    }

    static func toolResultBodyEnd(toolName: String, elapsedMs: Double) {
        guard enabled else { return }
        if elapsedMs > 1 {
            print("[ChatPerf:\(now())] D2-toolResult END — tool=\(toolName) took=\(String(format: "%.2f", elapsedMs))ms")
        }
    }

    // MARK: - E: onChange / Observable notification

    static func onChangeFired(_ name: String) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] E-onChange FIRED — \(name)")
    }

    // MARK: - F: Animation/timer

    static func timerFired(_ name: String) {
        guard enabled else { return }
        // Only log first few to avoid spam
        print("[ChatPerf:\(now())] F-timer — \(name)")
    }

    // MARK: - G: ScrollView

    static func scrollGeometryChanged(distanceFromBottom: CGFloat) {
        guard enabled else { return }
        // Throttled: only log significant changes to avoid spam
        if distanceFromBottom > 1000 || distanceFromBottom < -100 {
            print("[ChatPerf:\(now())] G-scrollGeo — distFromBottom=\(Int(distanceFromBottom))")
        }
    }

    static func scrollToBottom() {
        guard enabled else { return }
        print("[ChatPerf:\(now())] G-scrollToBottom")
    }

    // MARK: - H: ObservableObject chain invalidation

    static func objectWillChange(_ objectName: String) {
        guard enabled else { return }
        print("[ChatPerf:\(now())] H-objectWillChange — \(objectName)")
    }
}

// MARK: - ViewModifier for body timing

/// Measures elapsed time between body eval and the next main-actor run-loop
/// tick. Uses Task (fires on next run-loop iteration) instead of onAppear
/// (fires on view visibility — misleading for LazyVStack items where body eval
/// and view appearance can be seconds apart, or during UI freezes where onAppear
/// measures freeze duration rather than body eval time).
struct ChatPerfBodyTimer: ViewModifier {
    let label: String
    let thresholdMs: Double

    func body(content: Content) -> some View {
        guard ChatPerfLogger.enabled else { return content }
        let start = Date()
        Task { @MainActor in
            let elapsed = Date().timeIntervalSince(start) * 1000
            if elapsed > thresholdMs {
                print("[ChatPerf:\(ChatPerfLogger.nowString())] \(label) — took=\(String(format: "%.2f", elapsed))ms")
            }
        }
        return content
    }
}

extension View {
    func chatPerfTimer(_ label: String, thresholdMs: Double = 3) -> some View {
        modifier(ChatPerfBodyTimer(label: label, thresholdMs: thresholdMs))
    }
}

extension ChatPerfLogger {
    /// Exposed for ChatPerfBodyTimer and external callers
    static func nowString() -> String {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return String(format: "%.1fms", elapsed)
    }
}
