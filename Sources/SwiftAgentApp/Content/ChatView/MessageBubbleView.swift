import SwiftUI

/// Renders a single message bubble with native block support.
/// Ported from ClarcChatKit's `MessageBubble`.
struct MessageBubbleView: View {
    @Environment(ChatBridge.self) private var chatBridge
    let message: ChatDisplayMessage
    @State private var isCopied = false
    @State private var cursorVisible = true
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isEditFocused: Bool
    @State private var isLongTextExpanded = false
    @State private var hoveredBlockId: String? = nil
    @State private var isHoveringUserBubble = false

    private static let longTextThreshold = 500

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if !message.attachmentPaths.isEmpty {
                    attachmentPreview
                }

                if message.role == .user {
                    if !message.content.isEmpty {
                        userTextBubble
                    }
                } else if message.isCompactBoundary {
                    compactBoundaryBubble
                } else if message.isError {
                    errorBubble
                } else {
                    let blocksStart = Date()
                    let hidden = message.isStreaming ? [] : message.blocks.compactMap(\.toolCall).filter { isTransientTool($0) && $0.hasNonEmptyResult }
                    let visibleBlocks = Self.mergeAdjacentTextBlocks(
                        in: message.blocks.filter { block in
                            if let text = block.text { return !text.isEmpty }
                            if let toolCall = block.toolCall {
                                if message.isStreaming { return true }
                                if isTransientTool(toolCall) { return false }
                                if toolCall.isKeepAlways { return true }
                                return toolCall.result != nil || toolCall.isError
                            }
                            if block.isThinking { return true }
                            return false
                        }
                    )
                    let _ = ChatPerfLogger.visibleBlocksCompute(
                        msgId: message.id,
                        inputCount: message.blocks.count,
                        outputCount: visibleBlocks.count,
                        elapsedMs: Date().timeIntervalSince(blocksStart) * 1000
                    )

                    if !hidden.isEmpty {
                        transientToolSummary(hidden: hidden)
                    }

                    ForEach(visibleBlocks) { block in
                        if let text = block.text, !text.isEmpty {
                            assistantTextBubble(text: text, blockId: block.id, hasHiddenTools: !hidden.isEmpty)
                        }
                        if let toolCall = block.toolCall {
                            if toolCall.name == "AskUserQuestion" {
                                EmptyView() // Stub
                            } else {
                                ToolResultView(toolCall: toolCall, isMessageStreaming: message.isStreaming)
                            }
                        }
                        if block.isThinking {
                            ThinkingBlockView(
                                block: block,
                                isMessageStreaming: message.isStreaming
                            )
                        }
                    }
                }

                if message.role == .assistant && !message.isStreaming,
                   let duration = message.duration {
                    HStack(spacing: 4) {
                        if message.isResponseComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: ChatTheme.size(11)))
                                .foregroundStyle(ChatTheme.statusSuccess)
                        }
                        Text(duration.formattedDuration)
                            .font(.system(size: ChatTheme.size(11), design: .monospaced))
                            .foregroundStyle(ChatTheme.textTertiary)
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .chatPerfTimer("D-bubbleBody msgId=\(String(message.id.prefix(8)))", thresholdMs: 5)
    }

    // MARK: - Compact Boundary

    private var compactBoundaryBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: ChatTheme.size(12), weight: .medium))
                .foregroundStyle(ChatTheme.textTertiary)
            Text(message.content)
                .font(.system(size: ChatTheme.size(13), weight: .medium))
                .foregroundStyle(ChatTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall).fill(ChatTheme.surfacePrimary))
        .overlay(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall).strokeBorder(ChatTheme.border, lineWidth: 0.5))
    }

    // MARK: - Error

    private var errorBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ChatTheme.size(13)))
                .foregroundStyle(ChatTheme.statusWarning)
            Text(message.content)
                .font(.system(size: ChatTheme.size(14)))
                .foregroundStyle(ChatTheme.textPrimary)
                .textSelection(.enabled)
        }
        .bubbleStyle(.error)
    }

    // MARK: - User Text

    @ViewBuilder
    private var userTextBubble: some View {
        let isLong = message.content.count > Self.longTextThreshold
        VStack(alignment: .trailing, spacing: 6) {
            Text(message.content)
                .font(.system(size: ChatTheme.size(14)))
                .foregroundStyle(ChatTheme.userBubbleText)
                .textSelection(.enabled)
                .lineLimit(isLong && !isLongTextExpanded ? 5 : nil)
            if isLong {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isLongTextExpanded.toggle() }
                } label: {
                    Text(isLongTextExpanded ? "Collapse" : "Show more")
                }
                .font(.system(size: ChatTheme.size(12), weight: .medium))
                .foregroundStyle(ChatTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .bubbleStyle(.user)
        .overlay(alignment: .bottomTrailing) {
            if isHoveringUserBubble {
                HStack(spacing: 3) {
                    userActionButton(systemName: isCopied ? "checkmark" : "doc.on.doc") {
                        copyToClipboard(message.content, feedback: $isCopied)
                    }
                }
                .padding(5)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onHover { isHoveringUserBubble = $0 }
    }

    // MARK: - Assistant Text

    private func assistantTextBubble(text: String, blockId: String, hasHiddenTools: Bool = false) -> some View {
        let lastText = message.blocks.last(where: \.isText)
        let isLastBlock = lastText?.id == blockId && lastText?.text == text

        return HStack(alignment: .bottom, spacing: 0) {
            Text(text)
                .font(.system(size: ChatTheme.size(15)))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if message.isStreaming && isLastBlock {
                Text("|")
                    .font(.system(size: ChatTheme.size(15), weight: .light))
                    .foregroundStyle(ChatTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                    .onAppear { cursorVisible = false }
            }
        }
        .foregroundStyle(ChatTheme.textPrimary)
        .bubbleStyle(.assistant)
        .overlay(alignment: .bottomTrailing) {
            if hoveredBlockId == blockId && !message.isStreaming {
                HStack(spacing: 4) {
                    copyButton(for: text)
                }
                .padding(6)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onHover { hoveredBlockId = $0 ? blockId : nil }
    }

    // MARK: - Copy Button

    @ViewBuilder
    private func copyButton(for text: String) -> some View {
        Button {
            copyToClipboard(text, feedback: $isCopied)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: ChatTheme.size(11), weight: .medium))
                .foregroundStyle(ChatTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(ChatTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ChatTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func userActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ChatTheme.size(11), weight: .medium))
                .foregroundStyle(ChatTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(ChatTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ChatTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .opacity(0.8)
    }

    // MARK: - Transient Tool Helpers

    private func isTransientTool(_ toolCall: ChatToolCall) -> Bool {
        ToolCategory(toolName: toolCall.name).isTransient
    }

    private static func mergeAdjacentTextBlocks(in blocks: [ChatMessageBlock]) -> [ChatMessageBlock] {
        var result: [ChatMessageBlock] = []
        for block in blocks {
            if block.isText,
               let lastIdx = result.indices.last,
               result[lastIdx].isText {
                let prev = result[lastIdx].text ?? ""
                let curr = block.text ?? ""
                let needsSpace = !(prev.last?.isWhitespace ?? true) && !(curr.first?.isWhitespace ?? true)
                let joined = needsSpace ? prev + " " + curr : prev + curr
                result[lastIdx] = .text(joined, id: result[lastIdx].id)
            } else {
                result.append(block)
            }
        }
        return result
    }

    @State private var showTransientTools = false

    private func transientToolSummary(hidden: [ChatToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTransientTools.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: ChatTheme.size(11)))
                        .foregroundStyle(ChatTheme.textTertiary)
                    Text("\(hidden.count) tools executed")
                        .font(.system(size: ChatTheme.size(12)))
                        .foregroundStyle(ChatTheme.textTertiary)
                    Image(systemName: showTransientTools ? "chevron.up" : "chevron.down")
                        .font(.system(size: ChatTheme.size(9)))
                        .foregroundStyle(ChatTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTransientTools {
                ForEach(hidden, id: \.id) { toolCall in
                    ToolResultView(toolCall: toolCall, isMessageStreaming: false)
                }
            }
        }
    }

    private var attachmentPreview: some View {
        HStack(spacing: 6) {
            ForEach(message.attachmentPaths, id: \.path) { info in
                HStack(spacing: 4) {
                    Image(systemName: info.isImage ? "photo" : "doc")
                        .font(.system(size: ChatTheme.size(14)))
                        .foregroundStyle(ChatTheme.accent)
                    Text(info.name)
                        .font(.caption)
                        .foregroundStyle(ChatTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(ChatTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
            }
        }
    }
}

// MARK: - Bubble Style

enum BubbleVariant {
    case user, assistant, error, tool, toolError
}

struct BubbleStyle: ViewModifier {
    let variant: BubbleVariant

    static let contentPadding = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    static let toolPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background, in: shape)
            .overlay(border)
    }

    private var padding: EdgeInsets {
        switch variant {
        case .tool, .toolError: return Self.toolPadding
        default: return Self.contentPadding
        }
    }

    private var background: some ShapeStyle {
        switch variant {
        case .user: return AnyShapeStyle(ChatTheme.userBubble)
        case .assistant: return AnyShapeStyle(ChatTheme.assistantBubble)
        case .error: return AnyShapeStyle(ChatTheme.statusError.opacity(0.08))
        case .tool: return AnyShapeStyle(ChatTheme.surfacePrimary)
        case .toolError: return AnyShapeStyle(ChatTheme.statusError.opacity(0.06))
        }
    }

    @ViewBuilder
    private var border: some View {
        switch variant {
        case .user: EmptyView()
        case .error:
            shape.strokeBorder(ChatTheme.statusError.opacity(0.3), lineWidth: 0.5)
        case .toolError:
            shape.strokeBorder(ChatTheme.statusError.opacity(0.3), lineWidth: 0.5)
        default:
            shape.strokeBorder(ChatTheme.border, lineWidth: 0.5)
        }
    }

    private var shape: some InsettableShape {
        switch variant {
        case .user:
            AnyInsettableShape(UnevenRoundedRectangle(
                topLeadingRadius: ChatTheme.cornerRadiusLarge,
                bottomLeadingRadius: ChatTheme.cornerRadiusLarge,
                bottomTrailingRadius: 4,
                topTrailingRadius: ChatTheme.cornerRadiusLarge
            ))
        case .assistant:
            AnyInsettableShape(UnevenRoundedRectangle(
                topLeadingRadius: ChatTheme.cornerRadiusLarge,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: ChatTheme.cornerRadiusLarge,
                topTrailingRadius: ChatTheme.cornerRadiusLarge
            ))
        case .error:
            AnyInsettableShape(UnevenRoundedRectangle(
                topLeadingRadius: ChatTheme.cornerRadiusLarge,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: ChatTheme.cornerRadiusLarge,
                topTrailingRadius: ChatTheme.cornerRadiusLarge
            ))
        case .tool, .toolError:
            AnyInsettableShape(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
        }
    }
}

extension View {
    func bubbleStyle(_ variant: BubbleVariant) -> some View {
        modifier(BubbleStyle(variant: variant))
    }
}

private struct AnyInsettableShape: InsettableShape, @unchecked Sendable {
    private let _path: (CGRect) -> Path
    private let _inset: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        _path = { shape.path(in: $0) }
        _inset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { _path(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { _inset(amount) }
}

// MARK: - Thinking Block

struct ThinkingBlockView: View {
    let block: ChatMessageBlock
    let isMessageStreaming: Bool

    @State private var userToggle: Bool? = nil
    @State private var isCopied = false
    @State private var isHovering = false

    private var isThisBlockStreaming: Bool {
        isMessageStreaming && block.thinkingDuration == nil && !block.isThinkingRedacted
    }

    private var isExpanded: Bool {
        userToggle ?? isThisBlockStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded { bodyContent }
        }
        .background(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall).fill(ChatTheme.surfacePrimary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall).strokeBorder(ChatTheme.border, lineWidth: 0.5))
        .onHover { isHovering = $0 }
        .onChange(of: block.thinkingDuration) { _, newValue in
            if newValue != nil && userToggle == nil {
                userToggle = false
            }
        }
    }

    private var thinkingText: String { block.thinking ?? "" }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { userToggle = !isExpanded }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: block.isThinkingRedacted ? "lock.fill" : "brain")
                    .font(.system(size: ChatTheme.size(11)))
                    .foregroundStyle(ChatTheme.textSecondary)
                headerLabel
                    .font(.system(size: ChatTheme.size(12), weight: .medium))
                    .foregroundStyle(ChatTheme.textSecondary)
                Spacer(minLength: 6)
                if !block.isThinkingRedacted {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: ChatTheme.size(9), weight: .semibold))
                        .foregroundStyle(ChatTheme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(block.isThinkingRedacted)
    }

    @ViewBuilder
    private var headerLabel: some View {
        if block.isThinkingRedacted {
            Text("Encrypted thought (redacted)")
        } else if isThisBlockStreaming {
            Text("Thinking...")
        } else if let duration = block.thinkingDuration {
            Text("Thought for \(duration.formattedDuration)")
        } else {
            Text("Thought")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if thinkingText.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(ChatTheme.border)
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(ChatTheme.border)
                        .frame(width: 2)
                        .padding(.vertical, 2)
                    Text(thinkingText)
                        .font(.system(size: ChatTheme.size(12)))
                        .italic()
                        .foregroundStyle(ChatTheme.textSecondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovering && !isMessageStreaming {
                    Button {
                        copyToClipboard(thinkingText, feedback: $isCopied)
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: ChatTheme.size(11), weight: .medium))
                            .foregroundStyle(ChatTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(ChatTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ChatTheme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
        }
    }
}
