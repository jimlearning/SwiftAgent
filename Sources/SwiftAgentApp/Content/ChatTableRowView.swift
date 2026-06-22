import AppKit

// MARK: - ChatTableRowView

/// A single row in the chat table, representing one `AgentMessage`.
///
/// Uses an `NSStackView` to vertically stack `ChatBlockView` instances.
/// The outer `NSTableView` handles cell reuse via `makeView(withIdentifier:owner:)`.
///
/// Each block view that subclasses `ChatCardBlockView` renders as a uniform
/// card with: rounded background + header (icon badge + title + timestamp) +
/// optional body. `TextBlockView` (user bubble / assistant text) is the
/// exception — it has no card shell.
///
/// During streaming, existing block views are updated in-place via
/// `ChatBlockView.updateContent(with:)` when the block structure hasn't changed.
/// If new blocks appear mid-stream, the entire stack is rebuilt.
public final class ChatTableRowView: NSTableCellView {

    // MARK: - Properties

    public private(set) var messageID: String = ""
    public private(set) var role: AgentMessageRole = .user
    private var currentMessage: AgentMessage?
    private var foldState: FoldState?
    private var thoughtTimeString: String?

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
        blockStack.distribution = .gravityAreas
        blockStack.spacing = kBlockVSpacing
        blockStack.edgeInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0
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
        self.thoughtTimeString = thoughtTimeString

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
        // .gravityAreas doesn't auto-resize children when their
        // intrinsicContentSize changes. Force the stack to re-layout so
        // each child gets its updated height.
        blockStack.needsLayout = true
        needsLayout = true
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
                timestamp: message.timestamp,
                onToggle: { [weak self] in
                    self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                }
            )
            return view

        case .toolUse(let toolUse):
            let view = ToolUseBlockView()
            let resultExpanded = !(foldState?.isCollapsed(.toolResult(toolUseID: toolUse.toolUseID)) ?? false)
            view.configure(
                toolUse: toolUse,
                isResultExpanded: resultExpanded,
                layoutWidth: layoutWidth,
                timestamp: message.timestamp,
                onToggle: { [weak self] in
                    self?.handleFoldToggle(.toolResult(toolUseID: toolUse.toolUseID))
                }
            )
            return view

        case .toolResult(let result):
            let view = ToolResultBlockView()
            let expanded = !(foldState?.isCollapsed(.toolResult(toolUseID: result.toolUseID)) ?? false)
            view.configure(
                result: result,
                expanded: expanded,
                layoutWidth: layoutWidth,
                timestamp: message.timestamp
            )
            return view

        case .systemReminder(let text):
            let view = SystemReminderBlockView()
            view.configure(text: text, layoutWidth: layoutWidth, timestamp: message.timestamp)
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
                        thoughtTimeString: thoughtTimeString,
                        layoutWidth: layoutWidth,
                        timestamp: message.timestamp,
                        onToggle: { [weak self] in
                            self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                        }
                    )
                }
            case .toolResult(let result):
                if let resultBlock = view as? ToolResultBlockView {
                    let shouldExpand = !fs.isCollapsed(.toolResult(toolUseID: result.toolUseID))
                    resultBlock.configure(
                        result: result,
                        expanded: shouldExpand,
                        layoutWidth: layoutWidth,
                        timestamp: message.timestamp
                    )
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
    /// Used by `ChatTableView.heightOfRow` to size each row correctly.
    ///
    /// Cards (Thinking, ToolUse, ToolResult, SystemReminder) have a minimum
    /// height of `kCardCollapsedMinHeight` even when collapsed, so the header
    /// row is always visible. This ensures uniform inter-card spacing.
    public static func measureHeight(
        for message: AgentMessage,
        contentWidth: CGFloat,
        foldState: FoldState
    ) -> CGFloat {
        var total: CGFloat = 0
        var lastVisibleHeight: CGFloat = 0

        for (index, block) in message.blocks.enumerated() {
            let h = blockHeight(block, message: message, index: index,
                                contentWidth: contentWidth, foldState: foldState)
            // Hidden blocks (h == 0) are completely invisible — NSStackView
            // skips them entirely. They must not contribute height or break
            // the spacing chain between adjacent visible blocks.
            guard h > 0 else { continue }
            if lastVisibleHeight > 0 {
                total += kBlockVSpacing
            }
            total += h
            lastVisibleHeight = h
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
            if message.role == .user {
                let textH = measureTextHeight(text, font: cbBodyFont,
                                              width: kUserBubbleMaxW - kUserBubbleHPad * 2)
                return textH + kUserBubbleVPad * 2
            }
            return measureTextHeight(text, font: cbBodyFont, width: contentWidth)

        case .thinking(let content, _):
            // Card: header always visible, body conditional
            let headerH = kCardVPad + kIconBadgeSize  // header row height
            let isCollapsed = foldState.isCollapsed(.thinking(messageID: message.id, blockIndex: index))
            if isCollapsed || content.isEmpty {
                return max(headerH + kCardVPad, kCardCollapsedMinHeight)
            }
            let bodyH = measureTextHeight(content, font: NSFont.systemFont(ofSize: 12),
                                          width: contentWidth - kCardHPad * 2)
            return headerH + kCardBodyTopSpacing + bodyH + kCardVPad

        case .toolUse(let toolUse):
            // Card: header + summary body
            let headerH = kCardVPad + kIconBadgeSize
            let summaryH: CGFloat = toolUse.inputSummary.isEmpty ? 0 :
                measureTextHeight(toolUse.inputSummary, font: cbCardBodyFont, width: contentWidth - kCardHPad * 2)
            let bodyH = summaryH > 0 ? kCardBodyTopSpacing + summaryH : 0
            return headerH + bodyH + kCardVPad

        case .toolResult(let result):
            // Completely hidden when collapsed — no header, no card at all
            let isCollapsed = foldState.isCollapsed(.toolResult(toolUseID: result.toolUseID))
            if isCollapsed {
                return 0
            }
            let headerH = kCardVPad + kIconBadgeSize
            let truncated = String(result.content.prefix(500))
            let bodyH = measureTextHeight(truncated, font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                          width: contentWidth - kCardHPad * 2)
            return headerH + kCardBodyTopSpacing + bodyH + kCardVPad

        case .systemReminder(let text):
            // Card: header + body text
            let headerH = kCardVPad + kIconBadgeSize
            let bodyH = measureTextHeight(text, font: cbSmallFont, width: contentWidth - kCardHPad * 2)
            return headerH + (bodyH > 0 ? kCardBodyTopSpacing + bodyH : 0) + kCardVPad
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
