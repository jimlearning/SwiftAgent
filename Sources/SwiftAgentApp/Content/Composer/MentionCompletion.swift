import SwiftUI
import AppKit

// MARK: - Mention Completion Popup

/// A floating popup window that displays @-mention autocomplete results.
///
/// Positioned just above the NSTextView's insertion point.
/// Navigable via arrow keys (↑↓), selectable via Enter/Tab, dismissible via Escape.
///
/// ## Keyboard Handling
/// - **↑ / ↓** — move selection up/down, wrapping at boundaries
/// - **Enter / Tab** — confirm selection, insert mention, dismiss
/// - **Escape** — dismiss without inserting
/// - Typing in the parent text view continues filtering
public final class MentionCompletionWindow: NSWindow, @unchecked Sendable {

    // MARK: - State

    private var items: [MentionItem] = []
    private var filteredItems: [MentionItem] = []
    private var selectedIndex: Int = 0
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private let onSelect: @MainActor (MentionItem) -> Void
    private let onDismiss: @MainActor () -> Void

    // MARK: - Sizing

    private let maxVisibleRows = 6
    private let rowHeight: CGFloat = 32
    private let windowWidth: CGFloat = 320

    // MARK: - Init

    /// - Parameters:
    ///   - onSelect: Called with the chosen `MentionItem`.
    ///   - onDismiss: Called when the popup is dismissed without selection.
    public init(onSelect: @escaping @MainActor (MentionItem) -> Void, onDismiss: @escaping @MainActor () -> Void) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss

        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false

        setupTableView()
    }

    // MARK: - Setup

    private func setupTableView() {
        // Scroll view
        scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        // Table view
        tableView = NSTableView(frame: .zero)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = .zero
        tableView.rowHeight = rowHeight

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mention"))
        column.width = windowWidth
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        scrollView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight * CGFloat(maxVisibleRows))
        contentView = scrollView
    }

    // MARK: - Public API

    /// Show the popup with the given items, filtering by the query.
    /// - Parameters:
    ///   - items: All mentionable items.
    ///   - query: The text after `@` (e.g. `"MyFi"` for `@MyFi`).
    ///   - anchorRect: The screen rect to position above (usually the insertion point).
    ///   - parentWindow: The parent window for ordering.
    public func show(
        items: [MentionItem],
        query: String,
        anchorRect: NSRect,
        parentWindow: NSWindow?
    ) {
        self.items = items
        filter(by: query)

        // Calculate size
        let visibleRows = min(filteredItems.count, maxVisibleRows)
        let height = max(CGFloat(visibleRows) * rowHeight, rowHeight)

        let contentRect = NSRect(
            x: anchorRect.minX,
            y: anchorRect.minY - height - 4,
            width: windowWidth,
            height: height
        )

        setFrame(contentRect, display: true)
        tableView.reloadData()

        if let parent = parent {
            parent.addChildWindow(self, ordered: .above)
        }
        makeKeyAndOrderFront(nil)
    }

    /// Update the filter query as the user types.
    public func updateFilter(query: String) {
        filter(by: query)
        tableView.reloadData()
    }

    /// Dismiss the popup.
    public func dismiss() {
        if let parent = parent {
            parent.removeChildWindow(self)
        }
        orderOut(nil)
    }

    // MARK: - Filtering

    private func filter(by query: String) {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if q.isEmpty {
            // Show recent/all items grouped by kind
            filteredItems = items
        } else {
            // Fuzzy-ish match: query characters must appear in order
            filteredItems = items.filter { item in
                let name = item.displayName.lowercased()
                let detail = (item.detail ?? "").lowercased()
                return name.contains(q) || detail.contains(q) || fuzzyMatch(query: q, target: name)
            }
        }

        // Sort: exact prefix match first, then kind grouping, then alphabetical
        filteredItems.sort { a, b in
            let aExact = a.displayName.lowercased().hasPrefix(q)
            let bExact = b.displayName.lowercased().hasPrefix(q)
            if aExact != bExact { return aExact }
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            return a.displayName.lowercased() < b.displayName.lowercased()
        }

        selectedIndex = filteredItems.isEmpty ? -1 : 0
    }

    /// Simple fuzzy match: all query chars must appear in target in order.
    private func fuzzyMatch(query: String, target: String) -> Bool {
        var qi = query.startIndex
        var ti = target.startIndex
        while qi < query.endIndex, ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
            }
            ti = target.index(after: ti)
        }
        return qi == query.endIndex
    }

    // MARK: - Keyboard

    /// Handle key events for navigation and selection.
    /// Called by the parent NSTextView when the popup is visible.
    public func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isVisible else { return false }

        switch Int(event.keyCode) {
        case 125: // ↓
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            } else {
                selectedIndex = 0
            }
            scrollToSelection()
            tableView.reloadData()
            return true

        case 126: // ↑
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else {
                selectedIndex = filteredItems.count - 1
            }
            scrollToSelection()
            tableView.reloadData()
            return true

        case 36, 48: // Enter, Tab
            if selectedIndex >= 0, selectedIndex < filteredItems.count {
                confirmSelection()
            }
            return true

        case 53: // Escape
            dismiss()
            onDismiss()
            return true

        default:
            return false
        }
    }

    private func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < filteredItems.count else { return }
        let item = filteredItems[selectedIndex]
        dismiss()
        onSelect(item)
    }

    private func scrollToSelection() {
        guard selectedIndex >= 0 else { return }
        tableView.scrollRowToVisible(selectedIndex)
    }
}

// MARK: - NSTableViewDataSource

extension MentionCompletionWindow: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    public func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < filteredItems.count else { return nil }
        return filteredItems[row]
    }
}

// MARK: - NSTableViewDelegate

extension MentionCompletionWindow: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }

        let item = filteredItems[row]
        let isSelected = row == selectedIndex

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("mentionCell")

        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: item.iconName, accessibilityDescription: item.kind.rawValue)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.contentTintColor = isSelected ? .white : .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iconView)

        // Name
        let nameLabel = NSTextField(labelWithString: item.displayName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = isSelected ? .white : .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(nameLabel)

        // Detail
        let detailLabel = NSTextField(labelWithString: item.detail ?? "")
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = isSelected ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(detailLabel)

        // Layout
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -10),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 0),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -10),
        ])

        // Selection background
        if isSelected {
            cell.wantsLayer = true
            cell.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            cell.layer?.cornerRadius = 4
        }

        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}
