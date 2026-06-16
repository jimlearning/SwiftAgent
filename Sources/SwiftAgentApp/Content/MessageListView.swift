import SwiftUI

/// Scrollable list of thread messages with auto-scroll on new content.
///
/// Looks up the live `ThreadViewModel` from `AppViewModel` on every render via
/// `@EnvironmentObject`. This is what makes the list update the instant the user
/// hits Send: the SwiftUI runtime subscribes this view to `AppViewModel`'s
/// `objectWillChange`, and any nested `@Published` mutation on the thread
/// (e.g. `messages.append`, `thoughtTimeString` updates during streaming) flows
/// through `AppViewModel.selectedThread` re-evaluations.
///
/// Accepting a `threadID: String` (instead of a `ThreadViewModel` reference)
/// also fixes a stale-capture issue: the previous design passed the thread by
/// reference from `ContentView.body`, and that reference would be captured by
/// child callbacks and modifiers — leading to the "send a message, nothing
/// updates until I click a sidebar row" symptom. The id-based lookup goes
/// through `AppViewModel.threadViewModels[id]` on every render, so the view
/// always observes the live instance.
public struct MessageListView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    let threadID: String

    @State private var isPaused: Bool = false
    @State private var lastSeenCount: Int = 0
    @State private var lastSeenLastID: String?

    public var body: some View {
        if let thread = appViewModel.threadViewModels[threadID] {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: []) {
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

                        // Invisible marker at the bottom for auto-scroll detection
                        Color.clear
                            .frame(height: 1)
                            .id("bottomMarker")
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if newPhase == .interacting {
                        isPaused = true
                    } else if newPhase == .idle {
                        // Resume auto-scroll shortly after the user stops interacting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isPaused = false
                        }
                    }
                }
                .onChange(of: thread.messages.count) { oldCount, newCount in
                    lastSeenCount = newCount
                    if !isPaused || newCount > oldCount {
                        // New message arrived — always scroll to it
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: thread.messages.last?.id) { _, newID in
                    lastSeenLastID = newID
                    if !isPaused {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: thread.messages.last?.content) { _, _ in
                    if !isPaused {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: thread.messages.last?.reasoningContent) { _, _ in
                    if !isPaused {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: thread.state) { _, newState in
                    // When the assistant starts/finishes streaming, snap to bottom
                    if newState == .executing || newState == .done {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
        } else {
            // Thread not in memory — render an empty placeholder
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
