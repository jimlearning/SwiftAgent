import AppKit

// MARK: - ChatTableRowView

/// A single row in the chat table, representing one `AgentMessage`.
///
/// Unlike the old `ChatMessageCell` (which manually laid out subviews in a
/// flipped NSView and had no cell reuse), this view uses Auto Layout via
/// `NSStackView` to stack `ChatBlockView` instances vertically. The outer
/// NSTableView handles cell reuse.
///
/// During streaming, existing block views are updated in-place via
/// `ChatBlockView.updateContent(with:)` if the block structure hasn't changed.
/// If new blocks appear mid-stream, the entire stack is rebuilt.
public final class ChatTableRowView: NSTableCellView {

    // MARK: - Properties

    public private(set) var messageID: String = ""
    public private(set) var role: AgentMessageRole = .user
    private var currentMessage: AgentMessage?
    private var foldState: FoldState?

    /// Vertical stack that holds all block views.
    private let blockStack = NSStackView()

    /// Individual block views currently in the stack.
    private var blockViews: [NSView & ChatBlockView] = []

    /// Called when the user toggles a fold target, so the table can animate
    /// the row height change.
    public var onFoldToggled: (() -> Void)?

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupStack()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStack() {
        clipsToBounds = true

        blockStack.orientation = .vertical
        blockStack.alignment = .leading
        blockStack.distribution = .fill
        blockStack.spacing = kBlockVSpacing
        blockStack.edgeInsets = NSEdgeInsets(
            top: kBlockVSpacing,
            left: kBlockHPadding,
            bottom: kBlockVSpacing,
            right: kBlockHPadding
        )
        blockStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blockStack)

        NSLayoutConstraint.activate([
            blockStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            blockStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            blockStack.topAnchor.constraint(equalTo: topAnchor),
            blockStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Configuration

    /// Configure (or reconfigure) this row for a given message.
    ///
    /// - Parameter layoutWidth: Available content width for block views.
    ///   Must be the table column width minus horizontal padding, NOT bounds.width
    ///   (which is zero for newly-created cells).
    public func configure(
        with message: AgentMessage,
        foldState: FoldState,
        isStreaming: Bool,
        thoughtTimeString: String?,
        layoutWidth: CGFloat
    ) {
        self.messageID = message.id
        self.role = message.role
        self.currentMessage = message
        self.foldState = foldState

        if isStreaming && message.blocks.count == blockViews.count {
            if !updateBlocksInPlace(for: message) {
                rebuildBlocks(for: message, isStreaming: isStreaming,
                              thoughtTimeString: thoughtTimeString, layoutWidth: layoutWidth)
            }
        } else {
            rebuildBlocks(for: message, isStreaming: isStreaming,
                          thoughtTimeString: thoughtTimeString, layoutWidth: layoutWidth)
        }
    }

    // MARK: - Streaming Update

    /// Update streaming text in existing blocks without rebuilding.
    /// Returns false if in-place update isn't possible.
    public func updateStreamingBlocks(_ blocks: [AgentMessageBlock]) -> Bool {
        guard blocks.count == blockViews.count else { return false }
        for (i, block) in blocks.enumerated() {
            if !blockViews[i].updateContent(with: block) {
                return false
            }
        }
        return true
    }

    // MARK: - Block Construction

    private func rebuildBlocks(
        for message: AgentMessage,
        isStreaming: Bool,
        thoughtTimeString: String?,
        layoutWidth: CGFloat
    ) {
        blockViews.forEach { blockStack.removeView($0) }
        blockViews.removeAll()

        for (index, block) in message.blocks.enumerated() {
            if let view = makeBlockView(for: block, message: message, index: index,
                                        isStreaming: isStreaming,
                                        thoughtTimeString: thoughtTimeString,
                                        layoutWidth: layoutWidth) {
                blockViews.append(view)
                blockStack.addView(view, in: .bottom)
            }
        }
    }

    private func updateBlocksInPlace(for message: AgentMessage) -> Bool {
        for (i, block) in message.blocks.enumerated() {
            guard i < blockViews.count else { return false }
            if !blockViews[i].updateContent(with: block) {
                return false
            }
        }
        return true
    }

    /// Create the appropriate block view for a given AgentMessageBlock.
    private func makeBlockView(
        for block: AgentMessageBlock,
        message: AgentMessage,
        index: Int,
        isStreaming: Bool,
        thoughtTimeString: String?,
        layoutWidth: CGFloat
    ) -> (NSView & ChatBlockView)? {
        switch block {
        case .text(let text):
            let view = TextBlockView()
            view.configure(text: text, role: message.role, layoutWidth: layoutWidth)
            return view

        case .thinking(let content, _):
            let view = ThinkingBlockView()
            let expanded = !(foldState?.isCollapsed(.thinking(messageID: message.id, blockIndex: index)) ?? false)
            view.configure(
                content: content,
                expanded: expanded,
                isStreaming: isStreaming,
                thoughtTimeString: thoughtTimeString,
                layoutWidth: layoutWidth,
                onToggle: { [weak self] in
                    self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                }
            )
            return view

        case .toolUse(let toolUse):
            let view = ToolUseBlockView()
            let resultExpanded = !(foldState?.isCollapsed(.toolResult(toolUseID: toolUse.toolUseID)) ?? false)
            view.configure(toolUse: toolUse, isResultExpanded: resultExpanded, onToggle: { [weak self] in
                self?.handleFoldToggle(.toolResult(toolUseID: toolUse.toolUseID))
            })
            return view

        case .toolResult(let result):
            let view = ToolResultBlockView()
            let expanded = !(foldState?.isCollapsed(.toolResult(toolUseID: result.toolUseID)) ?? false)
            view.configure(result: result, expanded: expanded, layoutWidth: layoutWidth)
            return view

        case .systemReminder(let text):
            let view = SystemReminderBlockView()
            view.configure(text: text)
            return view
        }
    }

    // MARK: - Fold Handling

    private func handleFoldToggle(_ target: FoldTarget) {
        foldState?.toggle(target)
        applyFoldState()
        // Force immediate layout so status badges etc. are positioned correctly
        // before the table recalculates row heights.
        needsLayout = true
        layoutSubtreeIfNeeded()
        onFoldToggled?()
    }

    /// Re-apply fold state to all block views.
    public func applyFoldState() {
        guard let message = currentMessage, let fs = foldState else { return }
        let layoutWidth = max(bounds.width - kBlockHPadding * 2, 100)

        for (index, view) in blockViews.enumerated() {
            guard index < message.blocks.count else { continue }
            let block = message.blocks[index]

            switch block {
            case .thinking:
                if let thinkingBlock = view as? ThinkingBlockView {
                    let shouldExpand = !fs.isCollapsed(.thinking(messageID: message.id, blockIndex: index))
                    thinkingBlock.configure(
                        content: block.thinkingContent ?? "",
                        expanded: shouldExpand,
                        isStreaming: message.isStreaming,
                        thoughtTimeString: nil,
                        layoutWidth: layoutWidth,
                        onToggle: { [weak self] in
                            self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                        }
                    )
                }
            case .toolResult(let result):
                if let resultBlock = view as? ToolResultBlockView {
                    let shouldExpand = !fs.isCollapsed(.toolResult(toolUseID: result.toolUseID))
                    resultBlock.configure(result: result, expanded: shouldExpand, layoutWidth: layoutWidth)
                }
            case .toolUse(let toolUse):
                if let toolBlock = view as? ToolUseBlockView {
                    let resultExpanded = !fs.isCollapsed(.toolResult(toolUseID: toolUse.toolUseID))
                    toolBlock.updateResultExpanded(resultExpanded)
                    toolBlock.updateStatus(toolUse.status)
                }
            default: break
            }
        }
    }

    /// Refresh fold state without rebuilding block views.
    public func refreshFoldState(_ newFoldState: FoldState) {
        foldState = newFoldState
        applyFoldState()
    }

    // MARK: - Layout Width

    /// Update the maximum layout width for all block views.
    public func updateLayoutWidth(_ width: CGFloat) {
        let contentWidth = width - kBlockHPadding * 2
        for view in blockViews {
            if let textView = view as? TextBlockView {
                textView.frame.size.width = contentWidth
            }
        }
    }

    // MARK: - Height Measurement

    /// Compute the actual row height for a message, given the available content width.
    /// Used by `ChatTableView.heightOfRow` instead of the old rough estimate that
    /// ignored text length and caused cell stacking.
    public static func measureHeight(
        for message: AgentMessage,
        contentWidth: CGFloat,
        foldState: FoldState
    ) -> CGFloat {
        // Stack edge insets: top + bottom = kBlockVSpacing * 2
        var total: CGFloat = kBlockVSpacing * 2

        for (index, block) in message.blocks.enumerated() {
            total += blockHeight(block, message: message, index: index,
                                 contentWidth: contentWidth, foldState: foldState)
            // NSStackView.spacing between arranged views
            if index < message.blocks.count - 1 {
                total += kBlockVSpacing
            }
        }

        return max(total, 36)
    }

    /// Height of a single block, accounting for its type and fold state.
    private static func blockHeight(
        _ block: AgentMessageBlock,
        message: AgentMessage,
        index: Int,
        contentWidth: CGFloat,
        foldState: FoldState
    ) -> CGFloat {
        switch block {
        case .text(let text):
            let role: AgentMessageRole = message.role
            if role == .user {
                let textH = measureTextHeight(text, font: cbBodyFont,
                                              width: kUserBubbleMaxW - kUserBubbleHPad * 2)
                return textH + kUserBubbleVPad * 2
            }
            return measureTextHeight(text, font: cbBodyFont, width: contentWidth)

        case .thinking(let content, _):
            let headerH: CGFloat = 24
            let isCollapsed = foldState.isCollapsed(.thinking(messageID: message.id, blockIndex: index))
            if isCollapsed || content.isEmpty {
                return headerH
            }
            return headerH + kBlockVSpacing + measureTextHeight(content, font: cbCaptionFont, width: contentWidth - 16)

        case .toolUse(let toolUse):
            // Always full card: icon+name row + summary row
            let headerH = measureTextHeight(toolUse.toolName, font: NSFont.systemFont(ofSize: 12, weight: .semibold), width: contentWidth)
            let summaryH = measureTextHeight(toolUse.inputSummary, font: cbSmallFont, width: contentWidth)
            return kToolCardVPad * 2 + headerH + 2 + summaryH

        case .toolResult(let result):
            let isCollapsed = foldState.isCollapsed(.toolResult(toolUseID: result.toolUseID))
            if isCollapsed {
                return 0
            }
            let headerH: CGFloat = measureTextHeight("Result", font: cbToolResultHeaderFont, width: contentWidth)
            let truncated = String(result.content.prefix(500))
            let textH = measureTextHeight(truncated, font: cbToolResultFont, width: contentWidth)
            return headerH + 4 + textH

        case .systemReminder(let text):
            return measureTextHeight(text, font: cbSmallFont, width: contentWidth) + 4
        }
    }

    /// Measure the height of a string when rendered with the given font and width.
    private static let _sizingLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        return tf
    }()

    private static func measureTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 0 }
        _sizingLabel.font = font
        _sizingLabel.stringValue = text
        _sizingLabel.preferredMaxLayoutWidth = width
        let fit = _sizingLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return ceil(fit.height)
    }

    // MARK: - Overrides

    public override var isFlipped: Bool { true }
}
