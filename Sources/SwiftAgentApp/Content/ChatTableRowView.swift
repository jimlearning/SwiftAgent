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
    /// - Parameter message: The AgentMessage to display.
    /// - Parameter foldState: Current folding state.
    /// - Parameter isStreaming: Whether this message is actively streaming.
    /// - Parameter thoughtTimeString: "Thought for Xs" after streaming completes.
    public func configure(
        with message: AgentMessage,
        foldState: FoldState,
        isStreaming: Bool,
        thoughtTimeString: String?
    ) {
        self.messageID = message.id
        self.role = message.role
        self.currentMessage = message
        self.foldState = foldState

        if isStreaming && message.blocks.count == blockViews.count {
            // Same block count — try in-place update
            if !updateBlocksInPlace(for: message) {
                rebuildBlocks(for: message, isStreaming: isStreaming, thoughtTimeString: thoughtTimeString)
            }
        } else {
            rebuildBlocks(for: message, isStreaming: isStreaming, thoughtTimeString: thoughtTimeString)
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
        thoughtTimeString: String?
    ) {
        // Remove old block views
        blockViews.forEach { blockStack.removeView($0) }
        blockViews.removeAll()

        for (index, block) in message.blocks.enumerated() {
            if let view = makeBlockView(for: block, message: message, index: index, isStreaming: isStreaming, thoughtTimeString: thoughtTimeString) {
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
        thoughtTimeString: String?
    ) -> (NSView & ChatBlockView)? {
        switch block {
        case .text(let text):
            let view = TextBlockView()
            view.configure(text: text, role: message.role)
            return view

        case .thinking(let content, _):
            let view = ThinkingBlockView()
            let expanded = !(foldState?.isCollapsed(.thinking(messageID: message.id, blockIndex: index)) ?? false)
            view.configure(
                content: content,
                expanded: expanded,
                isStreaming: isStreaming,
                thoughtTimeString: thoughtTimeString,
                onToggle: { [weak self] in
                    self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                }
            )
            return view

        case .toolUse(let toolUse):
            let view = ToolUseBlockView()
            view.configure(toolUse: toolUse)
            return view

        case .toolResult(let result):
            let view = ToolResultBlockView()
            let expanded = !(foldState?.isCollapsed(.toolResult(messageID: message.id, toolUseID: result.toolUseID)) ?? false)
            view.configure(result: result, expanded: expanded)
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
        onFoldToggled?()
    }

    /// Re-apply fold state to all block views.
    public func applyFoldState() {
        guard let message = currentMessage, let fs = foldState else { return }

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
                        onToggle: { [weak self] in
                            self?.handleFoldToggle(.thinking(messageID: message.id, blockIndex: index))
                        }
                    )
                }
            case .toolResult(let result):
                if let resultBlock = view as? ToolResultBlockView {
                    let shouldExpand = !fs.isCollapsed(.toolResult(messageID: message.id, toolUseID: result.toolUseID))
                    resultBlock.configure(result: result, expanded: shouldExpand)
                }
            case .toolUse(let toolUse):
                if let toolBlock = view as? ToolUseBlockView {
                    // Tool use doesn't have expand/collapse in the new design,
                    // but we keep the status updated
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

    // MARK: - Height Estimation

    /// Estimated row height for incremental layout.
    public static func estimatedHeight(for message: AgentMessage) -> CGFloat {
        let basePerBlock: CGFloat = 24
        return CGFloat(message.blocks.count) * basePerBlock + 20
    }

    // MARK: - Overrides

    public override var isFlipped: Bool { true }
}
