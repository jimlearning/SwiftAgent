import SwiftUI

/// Side chat panel: independent conversation that does NOT pollute the
/// main thread's context. Backed by a per-tab `SideChatViewModel` —
/// created on first appear, kept alive in `RightTabsStore.sideChatStates`.
public struct SideChatPanelView: View {
    let tabID: String
    @StateObject private var model = SideChatViewModel()
    @State private var draft: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)
            messageList
            composer
        }
        .background(Color.bgRightPanel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 12))
                .foregroundColor(.accentPrimary)
            Text("Side chat")
                .font(.uiLabel)
                .foregroundColor(.textPrimary)
            Spacer()
            if !model.messages.isEmpty {
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .help("Clear side chat")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if model.messages.isEmpty {
                        VStack(spacing: 8) {
                            Spacer().frame(height: 30)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(.textTertiary)
                            Text("Side chat is independent")
                                .font(.uiBody)
                                .foregroundColor(.textSecondary)
                            Text("Messages here don't affect the main thread.")
                                .font(.uiCaption)
                                .foregroundColor(.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(model.messages) { msg in
                            SideChatBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask a side question…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.bgInput)
                )
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.bgElevated))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 13, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.appendUserMessage(text)
        draft = ""
        // Placeholder echo — full streaming wired in a follow-up patch.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            model.appendAssistantMessage("Echo: \(text)")
        }
    }
}

private struct SideChatBubble: View {
    let message: SideChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
            Text(message.content)
                .font(.uiBody)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(message.role == .user ? Color.bgElevated : Color.clear)
                )
                .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Per-tab state

@MainActor
public final class SideChatViewModel: ObservableObject {
    @Published public var messages: [SideChatMessage] = []

    public init() {}

    public func appendUserMessage(_ text: String) {
        messages.append(SideChatMessage(role: .user, content: text))
    }

    public func appendAssistantMessage(_ text: String) {
        messages.append(SideChatMessage(role: .assistant, content: text))
    }

    public func clear() {
        messages.removeAll()
    }
}

public struct SideChatMessage: Identifiable, Equatable {
    public let id: String
    public let role: Role
    public let content: String

    public enum Role: Equatable { case user, assistant }

    public init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}
