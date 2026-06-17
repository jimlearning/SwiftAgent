import SwiftUI

/// Renders a single message bubble.
/// User messages: rounded bubble, right-aligned, bgElevated background, 4pt corner radius.
/// Assistant messages: no bubble, text directly on bgContent, left-aligned.
/// Status rows: small gray text (per §5.1).
public struct MessageBubbleView: View {
    let message: ThreadMessage
    let thoughtTimeString: String?
    let reasoningExpanded: Bool
    let onToggleReasoning: () -> Void

    /// Cached rendered AttributedString so we don't re-parse markdown + re-run
    /// regex syntax highlighting on every SwiftUI body evaluation during scroll.
    @State private var cachedRenderContent: String = ""
    @State private var cachedRenderResult: AttributedString?

    public var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            // Status row for assistant messages
            if message.role == .assistant, let thoughtTime = thoughtTimeString, message.isStreaming {
                statusRow(thoughtTime)
            }

            // Reasoning block (R1 thinking chain)
            if message.role == .assistant, let reasoning = message.reasoningContent, !reasoning.isEmpty {
                reasoningBlock(reasoning)
            }

            // Message content
            if message.role == .user {
                userBubble
            } else {
                assistantContent
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        Text(message.content)
            .font(.uiBody)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .fill(Color.bgElevated)
            )
            .frame(maxWidth: 320, alignment: .trailing)
    }

    // MARK: - Assistant Content (markdown rendered)

    private var assistantContent: some View {
        Text(renderedAssistantContent())
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    /// Returns the cached render if content hasn't changed; otherwise re-renders.
    /// Eliminates the per-frame markdown parse + regex highlight cost during scroll.
    private func renderedAssistantContent() -> AttributedString {
        if message.content.isEmpty && message.isStreaming {
            return AttributedString(" ")
        }
        if let cached = cachedRenderResult, cachedRenderContent == message.content {
            return cached
        }
        // Reuse a single renderer to avoid recompiling regex grammars every time.
        let renderer = Self.markdownRenderer
        let result = renderer.render(message.content)
        cachedRenderContent = message.content
        cachedRenderResult = result
        return result
    }

    /// Shared MarkdownRenderer — avoids re-initializing RegexSyntaxHighlighter
    /// (which compiles language grammars) on every cache miss.
    private static let markdownRenderer = MarkdownRenderer(
        baseFont: .uiBody,
        codeFont: .codeMono,
        foregroundColor: .textPrimary
    )

    // MARK: - Status Row

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(.uiCaption)       // 12pt
            .foregroundColor(.textSecondary)  // small gray text
            .padding(.leading, 4)
    }

    // MARK: - Reasoning Block

    private func reasoningBlock(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggleReasoning) {
                HStack(spacing: 4) {
                    Image(systemName: reasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Thinking...")
                        .font(.uiCaption)
                }
                .foregroundColor(.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cellHoverHighlightTight()

            if reasoningExpanded {
                Text(content)
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.leading, 16)
                    .textSelection(.enabled)
            }
        }
    }
}

#if DEBUG
struct MessageBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            MessageBubbleView(
                message: ThreadMessage(role: .user, content: "Hello, DeepSeek!"),
                thoughtTimeString: nil,
                reasoningExpanded: false,
                onToggleReasoning: {}
            )
            MessageBubbleView(
                message: ThreadMessage(role: .assistant, content: "Hello! How can I help you today?"),
                thoughtTimeString: "Thought for 3s",
                reasoningExpanded: false,
                onToggleReasoning: {}
            )
        }
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
    }
}
#endif
