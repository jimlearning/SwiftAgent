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

    /// Static render cache keyed by message ID + content length.
    /// A plain Dictionary — NOT @State — so writes don't trigger SwiftUI
    /// "Modifying state during view update" warnings and re-render spirals.
    /// All access is main-actor-only (body evaluation), so no lock needed.
    private static var renderCache: [String: AttributedString] = [:]
    private static let maxCacheEntries = 300

    public var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if message.role == .assistant, let thoughtTime = thoughtTimeString, message.isStreaming {
                statusRow(thoughtTime)
            }

            if message.role == .assistant, let reasoning = message.reasoningContent, !reasoning.isEmpty {
                reasoningBlock(reasoning)
            }

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
    /// Uses a static dictionary cache (not @State) to avoid triggering
    /// "Modifying state during view update" warnings during body evaluation.
    private func renderedAssistantContent() -> AttributedString {
        if message.content.isEmpty && message.isStreaming {
            return AttributedString(" ")
        }
        let cacheKey = "\(message.id):\(message.content.count)"
        if let cached = Self.renderCache[cacheKey] {
            return cached
        }
        let result = Self.markdownRenderer.render(message.content)
        if Self.renderCache.count >= Self.maxCacheEntries {
            Self.renderCache.removeAll(keepingCapacity: true)
        }
        Self.renderCache[cacheKey] = result
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
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
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
