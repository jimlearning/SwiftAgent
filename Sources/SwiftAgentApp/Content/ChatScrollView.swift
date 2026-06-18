import AppKit

// MARK: - Debug Logging

private let kDebugScroll = true
private func SDLog(_ msg: String) {
    if kDebugScroll { print("[ChatScroll] \(msg)") }
}

// MARK: - Scroll Stickiness Threshold

/// Distance from the bottom edge at which we consider the user "at the bottom"
/// and eligible for auto-scroll.
private let kScrollStickinessThreshold: CGFloat = 50

// MARK: - ChatDocumentView

/// Flipped document view that hosts ChatMessageCell views in a vertical stack.
public final class ChatDocumentView: NSView {

    /// The message cells currently in the document, in display order (top to bottom).
    public internal(set) var cells: [ChatMessageCell] = []

    /// The visible width of the scroll view's content area. Must be set by
    /// ChatScrollView before layout — document view bounds.width is always
    /// the content width, not the clip width, so we track it separately.
    public var layoutWidth: CGFloat = 0

    /// Called when the intrinsic content size changes (e.g. streaming).
    var onIntrinsicSizeChanged: (() -> Void)?

    // MARK: - Empty State

    private lazy var emptyStateView: NSView = {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSTextField(labelWithString: "💬")
        imageView.font = NSFont.systemFont(ofSize: 36, weight: .light)
        imageView.textColor = .saTextTertiary
        imageView.alignment = .center
        imageView.isBezeled = false
        imageView.drawsBackground = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        let label = NSTextField(labelWithString: "Send a message to start a conversation")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .saTextSecondary
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }()

    private var emptyStateVisible = false

    private func updateEmptyState() {
        let shouldShow = cells.isEmpty
        guard shouldShow != emptyStateVisible else { return }
        emptyStateVisible = shouldShow

        if shouldShow {
            addSubview(emptyStateView)
        } else {
            emptyStateView.removeFromSuperview()
        }
    }

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        self.layer?.backgroundColor = NSColor.saBgContent.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { true }

    // MARK: - Cell Management

    /// Add a cell for a new message at the bottom.
    func appendCell(_ cell: ChatMessageCell) {
        cells.append(cell)
        addSubview(cell)
        updateEmptyState()
    }

    /// Remove all cells.
    func removeAllCells() {
        cells.forEach { $0.removeFromSuperview() }
        cells.removeAll()
        updateEmptyState()
    }

    /// Return the last cell (the streaming target).
    var lastCell: ChatMessageCell? {
        cells.last
    }

    /// The index of the last cell.
    var lastCellIndex: Int {
        cells.count - 1
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()

        let width = layoutWidth > 0 ? layoutWidth : (bounds.width > 0 ? bounds.width : 600)
        SDLog("layout() layoutWidth=\(layoutWidth) effective=\(width) bounds=\(bounds) cells=\(cells.count)")

        if cells.isEmpty {
            let emptySize = emptyStateView.fittingSize
            emptyStateView.frame = CGRect(
                x: (width - emptySize.width) / 2,
                y: (bounds.height - emptySize.height) / 2,
                width: emptySize.width,
                height: emptySize.height
            )
            frame.size = CGSize(width: width, height: max(bounds.height, 1))
            return
        }

        var y: CGFloat = 12

        for (i, cell) in cells.enumerated() {
            let cellHeight = cell.height(forWidth: width)
            cell.frame = CGRect(x: 0, y: y, width: width, height: cellHeight)
            SDLog("  cell[\(i)] frame=\(cell.frame) height=\(cellHeight)")
            y += cellHeight
        }

        y += 12
        SDLog("layout() totalHeight=\(y) oldHeight=\(frame.size.height)")
        if frame.size.height != y {
            frame.size = CGSize(width: width, height: y)
            onIntrinsicSizeChanged?()
        }
    }

    public override var intrinsicContentSize: CGSize {
        var totalHeight: CGFloat = 24
        let width = layoutWidth > 0 ? layoutWidth : (bounds.width > 0 ? bounds.width : 600)

        for cell in cells {
            totalHeight += cell.height(forWidth: width)
        }

        return CGSize(width: NSView.noIntrinsicMetric, height: totalHeight)
    }
}

// MARK: - ChatScrollView

/// NSScrollView subclass that hosts a ChatDocumentView with scroll-stickiness
/// detection and smooth auto-scroll during streaming.
public final class ChatScrollView: NSScrollView {

    // MARK: - Properties

    /// The document view (typed access).
    public var chatDocument: ChatDocumentView {
        documentView as! ChatDocumentView
    }

    /// Whether auto-scroll should be suppressed because the user scrolled up.
    private var suppressAutoScroll: Bool = false

    /// Observer token for bounds changes.
    private var boundsObserver: NSKeyValueObservation?

    /// Observer token for live scroll detection.
    private var isUserScrolling = false

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)

        let docView = ChatDocumentView()
        docView.onIntrinsicSizeChanged = { [weak self] in
            self?.invalidateIntrinsicContentSize()
        }
        self.documentView = docView

        hasVerticalScroller = true
        hasHorizontalScroller = false
        drawsBackground = false
        borderType = .noBorder
        verticalScrollElasticity = .allowed
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero

        // Observe content view bounds to detect user-initiated scroll-up
        boundsObserver = contentView.postsBoundsChangedNotifications
            ? nil : nil  // We'll use scroll wheel events instead

        // Track scroll wheel events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: self
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Overrides

    public override var isFlipped: Bool { true }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let visibleWidth = contentView.bounds.width
        if visibleWidth > 0 && visibleWidth != chatDocument.layoutWidth {
            chatDocument.layoutWidth = visibleWidth
            SDLog("setFrameSize \(newSize) layoutWidth=\(visibleWidth)")
        } else {
            SDLog("setFrameSize \(newSize) layoutWidth unchanged=\(visibleWidth)")
        }
        // Mark dirty only — never call layoutSubtreeIfNeeded() from setFrameSize.
        // AppKit may call this during an active layout pass; re-entrant layout
        // causes the infinite refresh loop.
        chatDocument.needsLayout = true
    }

    public override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)

        // Detect scroll direction
        if event.scrollingDeltaY < 0 {
            // User scrolled up: check if they moved away from bottom
            let bottomOffset = maxVisibleBottomOffset()
            if bottomOffset > kScrollStickinessThreshold {
                suppressAutoScroll = true
            }
        } else if event.scrollingDeltaY > 0 {
            // User scrolled down: check if they reached the bottom
            let bottomOffset = maxVisibleBottomOffset()
            if bottomOffset <= 0 {
                suppressAutoScroll = false
            }
        }
    }

    @objc private func scrollViewDidLiveScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView,
              scrollView == self else { return }

        let bottomOffset = maxVisibleBottomOffset()
        if bottomOffset <= kScrollStickinessThreshold {
            suppressAutoScroll = false
        } else {
            suppressAutoScroll = true
        }
    }

    // MARK: - Scroll Stickiness

    /// Distance from the bottom of the content to the bottom of the visible rect.
    /// Positive = user has scrolled up; 0 or negative = at or past the bottom.
    private func maxVisibleBottomOffset() -> CGFloat {
        let docHeight = chatDocument.frame.height
        let visibleRect = contentView.documentVisibleRect
        let visibleBottom = visibleRect.maxY
        return docHeight - visibleBottom
    }

    /// Whether the user is currently at/near the bottom of the scroll view.
    public var isNearBottom: Bool {
        return maxVisibleBottomOffset() <= kScrollStickinessThreshold
    }

    // MARK: - Public API

    /// Scroll to the bottom, optionally animated.
    public func scrollToBottom(animated: Bool = false) {
        let docHeight = chatDocument.frame.height
        let clipHeight = contentView.bounds.height
        let maxY = max(0, docHeight - clipHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().setBoundsOrigin(
                    NSPoint(x: 0, y: maxY)
                )
            }
        } else {
            contentView.scroll(to: NSPoint(x: 0, y: maxY))
        }
    }

    /// Auto-scroll to bottom if the user hasn't scrolled away.
    public func autoScrollToBottom(animated: Bool = true) {
        guard !suppressAutoScroll else { return }
        scrollToBottom(animated: animated)
    }

    /// Reset scroll suppression (e.g. on new message send).
    public func resetScrollSuppression() {
        suppressAutoScroll = false
        scrollToBottom(animated: false)
    }

    // MARK: - Cell Management

    /// Synchronise layoutWidth from the clip view before layout.
    private func syncLayoutWidth() {
        let visibleWidth = contentView.bounds.width
        if visibleWidth > 0 && visibleWidth != chatDocument.layoutWidth {
            chatDocument.layoutWidth = visibleWidth
            SDLog("syncLayoutWidth → \(visibleWidth)")
        }
    }

    /// Replace all cells with a new set. Used on thread switch.
    public func replaceAllCells(with cells: [ChatMessageCell]) {
        SDLog("replaceAllCells count=\(cells.count)")
        let doc = chatDocument
        doc.removeAllCells()
        for cell in cells {
            doc.appendCell(cell)
        }
        suppressAutoScroll = false
        syncLayoutWidth()
        doc.needsLayout = true
        layoutSubtreeIfNeeded()
        scrollToBottom(animated: false)
    }

    /// Append a new cell at the bottom.
    public func appendCell(_ cell: ChatMessageCell) {
        SDLog("appendCell role=\(cell.role) id=\(cell.messageID.prefix(8))")
        chatDocument.appendCell(cell)
        syncLayoutWidth()
        chatDocument.needsLayout = true
        layoutSubtreeIfNeeded()
        autoScrollToBottom(animated: true)
    }

    /// Update the last cell in-place (streaming) and auto-scroll if needed.
    public func updateLastCell(_ cell: ChatMessageCell) {
        let doc = chatDocument
        guard !doc.cells.isEmpty else { return }
        let lastIdx = doc.cells.count - 1
        let existing = doc.cells[lastIdx]

        if existing.messageID != cell.messageID {
            SDLog("updateLastCell replacing cell[\(lastIdx)] oldID=\(existing.messageID.prefix(8)) newID=\(cell.messageID.prefix(8))")
            existing.removeFromSuperview()
            doc.cells[lastIdx] = cell
            doc.addSubview(cell)
        } else {
            SDLog("updateLastCell same cell[\(lastIdx)] id=\(cell.messageID.prefix(8))")
        }

        syncLayoutWidth()
        doc.needsLayout = true
        layoutSubtreeIfNeeded()

        if !suppressAutoScroll {
            scrollToBottom(animated: false)
        }
    }

    /// Relayout the document. Call after updating cell content without replacing it.
    public func relayoutDocument() {
        SDLog("relayoutDocument")
        syncLayoutWidth()
        chatDocument.needsLayout = true
        layoutSubtreeIfNeeded()
        autoScrollToBottom(animated: false)
    }
}
