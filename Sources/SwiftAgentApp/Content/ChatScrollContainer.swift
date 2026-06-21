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
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let visibleWidth = contentView.bounds.width
        if visibleWidth > 0 {
            chatTableView.updateLayoutWidth(visibleWidth)
        }
    }
}
