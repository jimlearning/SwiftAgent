import AppKit

// MARK: - ChatScrollContainer

/// NSScrollView that hosts a `ChatTableView` as its document view.
///
/// NSTableView **must** live inside an NSScrollView to get scrolling,
/// column headers, and proper clip-view management. Without it, the table
/// grows unbounded and can never scroll — exactly the bug where content
/// pushes the bottom downward and the top stays pinned in the middle of
/// the SwiftUI layout.
///
/// This container is minimal: it configures the scroll view, sets the
/// table as `documentView`, and exposes a typed `chatTableView` property
/// for the bridge coordinator.
public final class ChatScrollContainer: NSScrollView {

    /// Typed access to the managed ChatTableView.
    public var chatTableView: ChatTableView {
        documentView as! ChatTableView
    }

    /// Create a scroll container with a new ChatTableView inside.
    /// - Parameter tableView: Optional pre-configured table. If nil, a new one is created.
    public init(tableView: ChatTableView = ChatTableView()) {
        super.init(frame: .zero)

        hasVerticalScroller = true
        hasHorizontalScroller = false
        drawsBackground = false
        borderType = .noBorder
        verticalScrollElasticity = .allowed
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero
        scrollerStyle = .overlay
        scrollerKnobStyle = .light

        documentView = tableView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Frame Sync

    /// NSScrollView does **not** call `setFrameSize(_:)` on its document view
    /// when the scroll view itself is resized. We override `setFrameSize` to
    /// forward the visible clip width to the table so it can update column
    /// widths and re-layout cells.
    ///
    /// **Important:** `updateLayoutWidth` triggers `noteHeightOfRows` which is a
    /// layout operation. Calling it synchronously from `setFrameSize` (which
    /// runs during AppKit's active layout pass) causes the re-entrant layout
    /// loop described in `ChatScrollView.swift:236-248`. The fix: defer to the
    /// next runloop iteration so layout completes before we re-measure.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard contentView.bounds.width > 0 else { return }
        // Read width inside the async — by the time it fires the bounds are
        // stable, avoiding intermediate animation-frame widths.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let w = self.contentView.bounds.width
            if w > 0 { self.chatTableView.updateLayoutWidth(w) }
        }
    }
}
