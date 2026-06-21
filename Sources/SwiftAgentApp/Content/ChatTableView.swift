import AppKit
import Combine

// MARK: - Debug

private let kDebugTable = true
private func TLog(_ msg: String) {
    if kDebugTable { print("[ChatTable] \(msg)") }
}

// MARK: - Scroll Stickiness

private let kScrollStickinessThreshold: CGFloat = 50

// MARK: - ChatTableView

/// NSTableView-based chat view with cell reuse via `makeView(withIdentifier:owner:)`,
/// in-place streaming updates, and multi-level folding support.
///
/// Replaces the old `ChatScrollView` + `ChatDocumentView` + `ChatMessageCell` stack
/// which built all cells upfront without reuse.
///
/// - Row reuse: `ChatTableRowView` cells are recycled via standard NSTableView
///   view-reuse pooling (identifier: `ChatRow`).
/// - Streaming: the last visible row is located and its content is updated in-place
///   via `ChatTableRowView.updateStreamingBlocks(_:)`.
/// - Auto-scroll: suppressed when the user scrolls up, re-engages when they
///   scroll back to the bottom.
/// - Height caching: row heights computed by Auto Layout are cached per message ID.
public final class ChatTableView: NSTableView {
    private var items: [AgentMessage] = []
    private var foldState: FoldState = FoldState()
    private var thoughtTime: String? = nil
    private var lastLayoutWidth: CGFloat = 600

    // Scroll state
    private var suppressAutoScroll: Bool = false

    // Streaming state
    fileprivate var isStreaming: Bool = false
    fileprivate var lastStreamingBlockCount: Int = 0

    // Height cache
    private var cachedRowHeights: [String: CGFloat] = [:]

    /// Called when fold state changes and rows need height recalculation.
    var onFoldToggled: (() -> Void)?

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupTableView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTableView() {
        wantsLayer = true
        backgroundColor = .clear
        headerView = nil
        usesAlternatingRowBackgroundColors = false
        selectionHighlightStyle = .none
        intercellSpacing = NSSize(width: 0, height: kCellSpacing)
        allowsColumnReordering = false
        allowsColumnResizing = false
        allowsColumnSelection = false
        allowsEmptySelection = true
        allowsTypeSelect = false
        rowSizeStyle = .custom

        // Configure column (single-column chat)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ChatColumn"))
        column.width = 600
        column.minWidth = 200
        column.maxWidth = 4000
        column.resizingMask = .autoresizingMask
        addTableColumn(column)

        delegate = self
        dataSource = self

        // Observe scroll
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Data Management

    /// Replace all messages (thread switch or initial load).
    public func replaceAllMessages(_ messages: [AgentMessage], foldState: FoldState, thoughtTime: String?) {
        TLog("replaceAllMessages count=\(messages.count)")
        items = messages
        self.foldState = foldState
        self.thoughtTime = thoughtTime
        suppressAutoScroll = false
        cachedRowHeights.removeAll()
        reloadData()
        scrollToBottom(animated: false)
    }

    /// Append a new message (streaming start or tool result).
    public func appendMessage(_ message: AgentMessage, foldState: FoldState, thoughtTime: String?) {
        TLog("appendMessage id=\(message.id.prefix(8)) role=\(message.role)")
        items.append(message)
        self.foldState = foldState
        self.thoughtTime = thoughtTime
        cachedRowHeights.removeValue(forKey: message.id)

        let newIndex = items.count - 1
        insertRows(at: IndexSet(integer: newIndex), withAnimation: .slideDown)
        autoScrollToBottom(animated: true)
    }

    /// Update an existing message's content (block structure changed).
    public func updateMessage(_ message: AgentMessage, foldState: FoldState, thoughtTime: String?) {
        guard let index = items.firstIndex(where: { $0.id == message.id }) else { return }
        items[index] = message
        self.foldState = foldState
        self.thoughtTime = thoughtTime
        cachedRowHeights[message.id] = nil

        if let cell = view(atColumn: 0, row: index, makeIfNecessary: false) as? ChatTableRowView {
            let colWidth = tableColumns.first?.width ?? lastLayoutWidth
            let layoutWidth = max(colWidth - kBlockHPadding * 2, 100)
            cell.configure(
                with: message,
                foldState: foldState,
                isStreaming: message.isStreaming,
                thoughtTimeString: thoughtTime,
                layoutWidth: layoutWidth
            )
        }
        noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
    }

    /// Update the last row during streaming (in-place text update).
    public func updateLastMessageStreaming(_ message: AgentMessage) {
        let rowIndex = items.count - 1
        guard rowIndex >= 0, rowIndex < items.count else { return }
        items[rowIndex] = message
        isStreaming = true
        lastStreamingBlockCount = message.blocks.count

        // Clear stale height — streaming text grows every frame.
        cachedRowHeights[message.id] = nil

        if let cell = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? ChatTableRowView {
            _ = cell.updateStreamingBlocks(message.blocks)
            noteHeightOfRows(withIndexesChanged: IndexSet(integer: rowIndex))
            autoScrollToBottom(animated: false)
        }
    }

    /// Check if the table is empty.
    public var isEmpty: Bool { items.isEmpty }

    // MARK: - Folding

    public func refreshFoldState(_ newFoldState: FoldState) {
        foldState = newFoldState
        for rowIndex in 0..<items.count {
            if let cell = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? ChatTableRowView {
                cell.refreshFoldState(newFoldState)
            }
        }
        cachedRowHeights.removeAll()
        noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<items.count))
    }

    // MARK: - Layout Width

    public func updateLayoutWidth(_ width: CGFloat) {
        guard width > 0, abs(width - lastLayoutWidth) > 1 else { return }
        lastLayoutWidth = width
        tableColumns.first?.width = width
        for rowIndex in 0..<min(items.count, numberOfRows) {
            if let cell = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? ChatTableRowView {
                cell.updateLayoutWidth(width)
            }
        }
        cachedRowHeights.removeAll()
        noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<items.count))
    }

    public func syncLayoutWidthFromClip() {
        guard let clipWidth = enclosingScrollView?.contentView.bounds.width, clipWidth > 0 else { return }
        updateLayoutWidth(clipWidth)
    }

    // MARK: - Scroll Management

    public func scrollToBottom(animated: Bool = false) {
        let rowCount = items.count
        guard rowCount > 0 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollRowToVisible(rowCount - 1)
            }
        } else {
            scrollRowToVisible(rowCount - 1)
        }
    }

    public func autoScrollToBottom(animated: Bool = true) {
        guard !suppressAutoScroll else { return }
        scrollToBottom(animated: animated)
    }

    public func resetScrollSuppression() {
        suppressAutoScroll = false
        scrollToBottom(animated: false)
    }

    public var isNearBottom: Bool {
        guard let scrollView = enclosingScrollView else { return true }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let docHeight = scrollView.documentView?.frame.height ?? 0
        return (docHeight - visibleRect.maxY) <= kScrollStickinessThreshold
    }

    @objc private func scrollViewDidLiveScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView,
              scrollView == enclosingScrollView else { return }
        let bottomOffset = maxVisibleBottomOffset()
        suppressAutoScroll = bottomOffset > kScrollStickinessThreshold
    }

    private func maxVisibleBottomOffset() -> CGFloat {
        guard let scrollView = enclosingScrollView else { return 0 }
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let visibleRect = scrollView.contentView.documentVisibleRect
        return docHeight - visibleRect.maxY
    }
}

// MARK: - NSTableViewDataSource

extension ChatTableView: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ChatRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ChatTableRowView
            ?? ChatTableRowView(frame: .zero)

        cell.identifier = identifier
        cell.onFoldToggled = { [weak self] in
            self?.cachedRowHeights.removeAll()
            self?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            self?.onFoldToggled?()
        }

        let message = items[row]
        let isLastMessage = (row == items.count - 1)
        let thoughtTimeStr: String? = isLastMessage ? thoughtTime : nil

        // Use column width (not bounds.width from the newly-created cell which is zero).
        let colWidth = tableColumns.first?.width ?? lastLayoutWidth
        let layoutWidth = max(colWidth - kBlockHPadding * 2, 100)

        cell.configure(
            with: message,
            foldState: foldState,
            isStreaming: message.isStreaming,
            thoughtTimeString: thoughtTimeStr,
            layoutWidth: layoutWidth
        )

        return cell
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < items.count else { return 40 }
        let message = items[row]

        // Never cache during streaming — text grows every frame so height is stale immediately.
        if !message.isStreaming, let cached = cachedRowHeights[message.id] {
            return cached
        }

        let width = tableColumns.first?.width ?? lastLayoutWidth
        let contentWidth = max(width - kBlockHPadding * 2, 100)
        let height = ChatTableRowView.measureHeight(
            for: message,
            contentWidth: contentWidth,
            foldState: foldState
        )

        if !message.isStreaming {
            cachedRowHeights[message.id] = height
        }
        return height
    }
}

// MARK: - NSTableViewDelegate

extension ChatTableView: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
