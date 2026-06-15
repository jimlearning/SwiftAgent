import SwiftUI

/// Scrollable list of thread messages with auto-scroll on new content.
/// Pauses auto-scroll when user manually scrolls up.
public struct MessageListView: View {
    @ObservedObject var thread: ThreadViewModel
    @State private var isPaused: Bool = false

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(thread.messages) { message in
                        MessageBubbleView(
                            message: message,
                            thoughtTimeString: thoughtTimeFor(message),
                            reasoningExpanded: thread.reasoningExpanded,
                            onToggleReasoning: { thread.reasoningExpanded.toggle() }
                        )
                        .id(message.id)
                    }

                    // Invisible marker at the bottom for auto-scroll detection
                    Color.clear
                        .frame(height: 1)
                        .id("bottomMarker")
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).maxY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                // If content bottom is above the visible bottom, user scrolled up
                // We don't have direct frame, so use a simplified approach:
                // just detect any scroll gesture via onScrollPhaseChange
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting {
                    isPaused = true
                } else if newPhase == .idle {
                    // Resume auto-scroll after user stops interacting for a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isPaused = false
                    }
                }
            }
            .onChange(of: thread.messages.count) { _, _ in
                if !isPaused { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: thread.messages.last?.content) { _, _ in
                if !isPaused { scrollToBottom(proxy: proxy) }
            }
            .onChange(of: thread.messages.last?.reasoningContent) { _, _ in
                if !isPaused { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func thoughtTimeFor(_ message: ThreadMessage) -> String? {
        guard message.role == .assistant,
              message.isStreaming,
              message.content.isEmpty || thread.messages.last?.id == message.id else {
            return nil
        }
        return thread.thoughtTimeString
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottomMarker", anchor: .bottom)
        }
    }
}

/// Preference key for scroll offset tracking.
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

