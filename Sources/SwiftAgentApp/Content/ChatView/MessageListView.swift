import SwiftUI

/// Message scroll area — extracted from ChatView to isolate dependencies on `messages`.
struct MessageListView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @State private var scrollPosition = ScrollPosition()
    @State private var settledItems: [ChatDisplayMessage] = []
    @State private var scrollTask: Task<Void, Never>?
    @State private var isOlderCollapsed = true
    @State private var isSessionReady = false

    /// Reference-type holder for scroll-to-bottom state — NOT @State.
    /// `.onScrollGeometryChange` fires during layout, and writing @State
    /// during layout triggers "Modifying state during view update" →
    /// immediate body re-eval → AttributeGraph cycle.
    /// Since `onStructureChanged` is recreated every body eval, the closure
    /// always captures the latest value — reactivity is not needed here.
    private let _nearBottomRef = NearBottomRef()

    private final class NearBottomRef: @unchecked Sendable {
        var value: Bool = true
    }

    private let foldThreshold = 30

    /// Reference-type holder for body eval rate tracking — must NOT be @State
    /// because modifying @State during body eval causes SwiftUI to re-enter the
    /// update cycle, leading to infinite loops and UI freezes.
    private let _evalState = EvalState()

    private final class EvalState: @unchecked Sendable {
        var count: Int = 0
        var lastLogTime: Date = .distantPast
    }

    var body: some View {
        // Track body eval rate WITHOUT modifying @State (which causes "Modifying state
        // during view update" → infinite render loop → UI freeze).
        let _ = trackBodyEval()

        ScrollView {
            LazyVStack(spacing: 16) {
                if settledItems.count > foldThreshold {
                    let hiddenCount = settledItems.count - foldThreshold

                    if !isOlderCollapsed {
                        messageRows(settledItems.prefix(hiddenCount))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOlderCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Group {
                                if isOlderCollapsed {
                                    Text("Show \(hiddenCount) earlier messages")
                                } else {
                                    Text("Collapse earlier messages")
                                }
                            }
                            .font(.system(size: ChatTheme.size(12), weight: .medium))
                            Image(systemName: isOlderCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: ChatTheme.size(10), weight: .medium))
                        }
                        .foregroundStyle(ChatTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall)
                                .fill(ChatTheme.surfacePrimary.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)

                    messageRows(settledItems.suffix(foldThreshold))
                } else {
                    messageRows(settledItems[...])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Streaming view is outside VStack — text deltas don't affect settled layout
            VStack(spacing: 16) {
                if !chatBridge.focusMode {
                    StreamingMessageView {
                        rebuildSettledItems()
                        if _nearBottomRef.value { scrollToBottomDebounced() }
                    }
                }

                if !chatBridge.isStreaming && !settledItems.isEmpty {
                    WebPreviewButton(messages: settledItems)
                        .id("web-preview")
                }
            }
            .padding(.horizontal, 20)
            .animation(.none, value: chatBridge.currentSessionId)

            Color.clear.frame(height: 1)
                .padding(.bottom, chatBridge.isStreaming ? 60 : 16)
        }
        .opacity(isSessionReady ? 1 : 0)
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geo in
            let distanceFromBottom = geo.contentSize.height - geo.visibleRect.maxY
            ChatPerfLogger.scrollGeometryChanged(distanceFromBottom: distanceFromBottom)
            return distanceFromBottom < 120
        } action: { _, nearBottom in
            _nearBottomRef.value = nearBottom
        }
        .task(id: chatBridge.currentSessionId) {
            isSessionReady = false
            scrollTask?.cancel()
            isOlderCollapsed = true
            scrollPosition = ScrollPosition()
            rebuildSettledItems()
            guard !settledItems.isEmpty else {
                isSessionReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(16))
            scrollPosition.scrollTo(edge: .bottom)
            _nearBottomRef.value = true
            try? await Task.sleep(for: .milliseconds(32))
            withAnimation(.easeIn(duration: 0.15)) { isSessionReady = true }
        }
        .onChange(of: chatBridge.isStreaming) { old, new in
            if old && !new {
                ChatPerfLogger.onChangeFired("chatBridge.isStreaming → stopped")
                rebuildSettledItems()
                scrollToBottomDebounced()
            }
        }
        .overlay {
            if settledItems.isEmpty && !chatBridge.isStreaming && chatBridge.currentSessionId == nil {
                EmptySessionView()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if chatBridge.isStreaming {
                HStack(alignment: .top, spacing: 0) {
                    StreamingIndicatorView(
                        isThinking: chatBridge.isThinking,
                        startDate: chatBridge.streamingStartDate
                    )
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .onAppear { _ = ChatPerfLogger.msgListBodyEnd(elapsedMs: 0) }
        .task { await monitorBodyEvalRate() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func messageRows(_ messages: some RandomAccessCollection<ChatDisplayMessage>) -> some View {
        let groupStart = Date()
        let groups = groupMessages(Array(messages))
        let _ = ChatPerfLogger.groupMessagesEnd(
            groupCount: groups.count,
            elapsedMs: Date().timeIntervalSince(groupStart) * 1000
        )
        ForEach(groups) { group in
            if group.isTransientGroup {
                TransientGroupSummaryView(messages: group.messages)
                    .id(group.id)
            } else if let message = group.messages.first {
                MessageBubbleView(message: message)
                    .id(message.id)
            }
        }
    }

    private func rebuildSettledItems() {
        let start = Date()
        ChatPerfLogger.rebuildSettledBegin(totalMsg: chatBridge.messages.count)
        let msgs = settledOnlyMessages(from: chatBridge.messages)
        ChatPerfLogger.rebuildSettledEnd(
            settledCount: msgs.count,
            elapsedMs: Date().timeIntervalSince(start) * 1000
        )
        var t = Transaction()
        t.animation = nil
        withTransaction(t) { settledItems = msgs }
    }

    private func settledOnlyMessages(from messages: [ChatDisplayMessage]) -> [ChatDisplayMessage] {
        var settled: [ChatDisplayMessage]
        if messages.last?.isStreaming == true {
            let boundary = streamingBoundaryIndex(in: messages)
            settled = Array(messages[..<boundary]).filter { !$0.isStreaming }
        } else {
            settled = messages.filter { !$0.isStreaming }
        }
        if chatBridge.focusMode {
            settled = settled.filter { $0.role == .user || $0.isResponseComplete || $0.isCompactBoundary }
        }
        return settled
    }

    private func trackBodyEval() {
        _evalState.count += 1
    }

    private func monitorBodyEvalRate() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if _evalState.count > 0 && chatBridge.isStreaming {
                let rate = Double(_evalState.count) / 2.0
                if rate > 5 {
                    print("[ChatPerf:\(ChatPerfLogger.nowString())] ⚠️ H-BODY-RATE — MessageListView body evaluated \(_evalState.count) times in 2s (rate=\(String(format: "%.1f", rate))/s) — possible @ObservableObject cascading invalidation")
                }
                _evalState.count = 0
            }
        }
    }

    private func scrollToBottomDebounced() {
        ChatPerfLogger.scrollToBottom()
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}

// MARK: - Message Grouping Helpers

fileprivate func partitionByStreaming(_ messages: [ChatDisplayMessage]) -> (settled: [ChatDisplayMessage], streaming: [ChatDisplayMessage]) {
    var settled: [ChatDisplayMessage] = []
    var streaming: [ChatDisplayMessage] = []
    for m in messages { if m.isStreaming { streaming.append(m) } else { settled.append(m) } }
    return (settled, streaming)
}

fileprivate struct MessageGroup: Identifiable, Equatable {
    let id: String
    let messages: [ChatDisplayMessage]
    let isTransientGroup: Bool

    static func == (lhs: MessageGroup, rhs: MessageGroup) -> Bool {
        lhs.id == rhs.id && lhs.messages.map(\.id) == rhs.messages.map(\.id)
            && lhs.isTransientGroup == rhs.isTransientGroup
    }
}

fileprivate func isPureTransientMessage(_ message: ChatDisplayMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary else { return false }
    let hasVisibleText = message.blocks.contains {
        guard let text = $0.text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if hasVisibleText { return false }
    let toolCalls = message.blocks.compactMap(\.toolCall)
    guard !toolCalls.isEmpty else { return false }
    let hasNonTransient = toolCalls.contains { !ToolCategory(toolName: $0.name).isTransient }
    if hasNonTransient { return false }
    return true
}

fileprivate func isInvisibleMessage(_ message: ChatDisplayMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary, !message.isStreaming else { return false }
    return message.blocks.isEmpty
}

fileprivate func groupMessages(_ messages: [ChatDisplayMessage], minGroupSize: Int = 2) -> [MessageGroup] {
    ChatPerfLogger.groupMessagesBegin(count: messages.count)
    var result: [MessageGroup] = []
    var accumulator: [ChatDisplayMessage] = []

    func flushAccumulator() {
        guard !accumulator.isEmpty else { return }
        if accumulator.count >= minGroupSize {
            result.append(MessageGroup(id: accumulator[0].id, messages: accumulator, isTransientGroup: true))
        } else {
            for m in accumulator {
                result.append(MessageGroup(id: m.id, messages: [m], isTransientGroup: false))
            }
        }
        accumulator = []
    }

    for message in messages {
        if isPureTransientMessage(message) {
            accumulator.append(message)
        } else if isInvisibleMessage(message) {
            continue
        } else {
            flushAccumulator()
            result.append(MessageGroup(id: message.id, messages: [message], isTransientGroup: false))
        }
    }
    flushAccumulator()

    return result
}

private func streamingBoundaryIndex(in messages: [ChatDisplayMessage]) -> Int {
    var idx = messages.count - 1
    while idx >= 0 && messages[idx].role == .assistant && !messages[idx].isError {
        idx -= 1
    }
    return idx + 1
}

// MARK: - Streaming Message (isolated view)

struct StreamingMessageView: View {
    @Environment(ChatBridge.self) private var chatBridge
    var onStructureChanged: () -> Void

    var body: some View {
        let bodyStart = Date()
        let messages = chatBridge.messages
        let activeMessages = activeResponseMessages(from: messages)
        let (settledActive, streamingActive) = partitionByStreaming(activeMessages)
        let _ = ChatPerfLogger.streamingViewBodyBegin(activeCount: activeMessages.count)

        Group {
            if !activeMessages.isEmpty {
                if !streamingActive.isEmpty {
                    let groups = groupMessages(settledActive, minGroupSize: 1)
                    ForEach(groups) { group in
                        if group.isTransientGroup {
                            TransientGroupSummaryView(messages: group.messages)
                                .id(group.id)
                        } else if let message = group.messages.first {
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                } else {
                    ForEach(settledActive, id: \.id) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }

                ForEach(streamingActive, id: \.id) { message in
                    MessageBubbleView(message: message)
                        .id(message.id)
                }
            }
        }
        .onChange(of: messages.count) { _, _ in
            onStructureChanged()
        }
        .onAppear {
            ChatPerfLogger.streamingViewBodyEnd(
                elapsedMs: Date().timeIntervalSince(bodyStart) * 1000
            )
        }
    }

    private func activeResponseMessages(from messages: [ChatDisplayMessage]) -> [ChatDisplayMessage] {
        guard messages.last?.isStreaming == true else { return [] }
        return Array(messages[streamingBoundaryIndex(in: messages)...])
    }
}

// MARK: - Transient Group Summary

struct TransientGroupSummaryView: View {
    let messages: [ChatDisplayMessage]
    @State private var isExpanded = false

    private var allToolCalls: [ChatToolCall] {
        messages.flatMap { $0.blocks.compactMap(\.toolCall) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: ChatTheme.size(11)))
                            .foregroundStyle(ChatTheme.textTertiary)
                        Text("\(allToolCalls.count) tools executed")
                            .font(.system(size: ChatTheme.size(12)))
                            .foregroundStyle(ChatTheme.textTertiary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ChatTheme.size(9)))
                            .foregroundStyle(ChatTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(allToolCalls, id: \.id) { toolCall in
                        ToolResultView(toolCall: toolCall, isMessageStreaming: false)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Empty Session

struct EmptySessionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: ChatTheme.size(36)))
                .foregroundStyle(ChatTheme.textTertiary)

            Text("How can I help you?")
                .font(.system(size: ChatTheme.size(18), weight: .medium))
                .foregroundStyle(ChatTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicatorView: View {
    let isThinking: Bool
    var startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            PulseRingView()
                .id("pulse")

            Group {
                if isThinking {
                    Text("Thinking...")
                } else {
                    Text("Generating response...")
                }
            }
            .font(.system(size: ChatTheme.size(13)))
            .foregroundStyle(ChatTheme.textSecondary)

            Spacer()

            if let startDate {
                ElapsedTimeView(startDate: startDate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ChatTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusMedium))
    }
}

// MARK: - Elapsed Time

struct ElapsedTimeView: View {
    let startDate: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsed.formattedDuration)
            .font(.system(size: ChatTheme.size(12), design: .monospaced))
            .foregroundStyle(ChatTheme.textTertiary)
            .onAppear {
                elapsed = Date().timeIntervalSince(startDate)
            }
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
    }
}

// MARK: - WebPreviewButton stub

struct WebPreviewButton: View {
    let messages: [ChatDisplayMessage]

    var body: some View {
        EmptyView() // Stub — DeepSeek doesn't generate web artifacts
    }
}
