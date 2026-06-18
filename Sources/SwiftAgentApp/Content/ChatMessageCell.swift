import AppKit

// MARK: - Debug Logging

private let kDebugLayout = true
private func DLog(_ msg: String) {
    if kDebugLayout { print("[ChatCell] \(msg)") }
}

// MARK: - NSColor Design Tokens

extension NSColor {
    static let saBgContent     = NSColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1)  // #1C1C1C
    static let saBgElevated    = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)  // #2A2A2A
    static let saTextPrimary   = NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)  // #F5F5F5
    static let saTextSecondary = NSColor(red: 0.600, green: 0.600, blue: 0.600, alpha: 1)  // #999999
    static let saTextTertiary  = NSColor(red: 0.400, green: 0.400, blue: 0.400, alpha: 1)  // #666666
    static let saAccentPrimary = NSColor(red: 0.200, green: 0.612, blue: 1.000, alpha: 1)  // #339CFF
    static let saSuccess       = NSColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1)  // #3FB950
    static let saDanger        = NSColor(red: 0.973, green: 0.318, blue: 0.286, alpha: 1)  // #F85149
    static let saWarning       = NSColor(red: 0.890, green: 0.702, blue: 0.255, alpha: 1)  // #E3B341
    static let saBorderSubtle  = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)  // #2A2A2A
}

// MARK: - Font Tokens

private nonisolated(unsafe) let saBodyFont    = NSFont.systemFont(ofSize: 13)
private nonisolated(unsafe) let saCaptionFont = NSFont.systemFont(ofSize: 12)
private nonisolated(unsafe) let saSmallFont   = NSFont.systemFont(ofSize: 10)
private nonisolated(unsafe) let saCodeFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

// MARK: - Layout Constants

private let kCellHorizontalPadding: CGFloat = 16
private let kCellVerticalPadding: CGFloat   = 4
private let kBlockSpacing: CGFloat          = 4
private let kUserBubbleMaxWidth: CGFloat    = 320
private let kUserBubbleHPadding: CGFloat    = 14
private let kUserBubbleVPadding: CGFloat    = 10
private let kUserBubbleCornerRadius: CGFloat = 12
private let kToolCardCornerRadius: CGFloat  = 6
private let kToolCardHPadding: CGFloat      = 10
private let kToolCardVPadding: CGFloat      = 6
private let kToolResultLeadingPad: CGFloat  = 28

// MARK: - ChatMessageCell

/// A single chat message cell rendered in AppKit.
///
/// Lays out blocks vertically: user bubbles (right-aligned, rounded),
/// assistant text (left-aligned, selectable), thinking blocks (collapsible),
/// tool-use cards, tool-result cards, and system reminders.
///
/// During streaming, the caller calls `configure(with:isStreaming:)` to
/// update text blocks in-place without recreating subviews.
public final class ChatMessageCell: NSView {

    // MARK: - Properties

    public private(set) var messageID: String = ""
    public private(set) var role: AgentMessageRole = .user
    private var blockViews: [NSView] = []
    private var thinkingToggleButton: NSButton?

    /// Number of block views currently displayed (for diffing during streaming).
    public var blockCount: Int { blockViews.count }

    /// Called when the reasoning toggle is clicked.
    public var onToggleReasoning: (() -> Void)?

    /// Whether reasoning blocks are expanded (driven externally from ThreadViewModel).
    public var reasoningExpanded: Bool = false {
        didSet {
            if oldValue != reasoningExpanded {
                updateReasoningVisibility()
            }
        }
    }

    /// True during streaming — used for "Thinking..." animation text.
    public var isStreaming: Bool = false {
        didSet { updateStreamingState() }
    }

    /// Directly update the thought-time label without rebuilding the cell.
    /// Used by the timer-driven refresh to avoid full layout loops.
    public func updateThoughtTime(_ text: String) {
        for view in blockViews {
            if let tf = view as? NSTextField, tf.identifier?.rawValue == "thoughtTime" {
                tf.stringValue = text
                tf.sizeToFit()
                return
            }
        }
    }

    /// Update streaming text in-place without rebuilding the entire cell.
    /// Finds the last NSTextField text block (not thoughtTime, not thinking content)
    /// and sets its stringValue directly. Returns true if text was updated.
    @discardableResult
    public func updateStreamingText(_ text: String) -> Bool {
        // Find the last text block that isn't a special label
        for view in blockViews.reversed() {
            guard let tf = view as? NSTextField else { continue }
            let id = tf.identifier?.rawValue ?? ""
            if id == "thoughtTime" || id == "thinkingContent" { continue }
            tf.stringValue = text
            return true
        }
        return false
    }

    /// Update a specific message block's text in-place.
    /// Skips decorative views (thoughtTime, toggle button) to map
    /// message block indices to the correct NSTextField subviews.
    public func updateBlockText(at messageBlockIndex: Int, text: String) -> Bool {
        // Find the messageBlockIndex-th text-bearing view, skipping decorators
        var skipCount = 0
        for view in blockViews {
            // Skip decorative views
            if let tf = view as? NSTextField {
                let id = tf.identifier?.rawValue ?? ""
                if id == "thoughtTime" { continue }
                if id == "thinkingContent" {
                    if skipCount == messageBlockIndex {
                        tf.stringValue = text
                        return true
                    }
                    skipCount += 1
                    continue
                }
                // Regular text block or spacer
                if skipCount == messageBlockIndex {
                    tf.stringValue = text
                    return true
                }
                skipCount += 1
                continue
            }
            if view is NSButton {
                // Thinking toggle button — skip
                continue
            }
            // For containers like UserBubbleView, check subviews
            for sub in view.subviews {
                if let tf = sub as? NSTextField {
                    if skipCount == messageBlockIndex {
                        tf.stringValue = text
                        return true
                    }
                    skipCount += 1
                    break
                }
            }
        }
        return false
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

    // MARK: - Configuration

    /// Reconfigure the cell for a new or updated message.
    /// - Parameters:
    ///   - message: The message to display.
    ///   - isStreaming: Whether this message is currently streaming.
    ///   - thoughtTimeString: Optional "Thought for Xs" status text.
    ///   - reasoningExpanded: Whether thinking blocks should be expanded.
    public func configure(
        with message: AgentMessage,
        isStreaming: Bool,
        thoughtTimeString: String?,
        reasoningExpanded: Bool
    ) {
        self.messageID = message.id
        self.role = message.role
        self.isStreaming = isStreaming
        self.reasoningExpanded = reasoningExpanded

        let oldHeight = frame.height
        DLog("configure() role=\(role) blocks=\(message.blocks.count) streaming=\(isStreaming) oldHeight=\(oldHeight)")

        // Remove old block views
        blockViews.forEach { $0.removeFromSuperview() }
        blockViews.removeAll()
        thinkingToggleButton = nil

        // Build new block views
        var subviews: [NSView] = []

        // Thought time status row (streaming assistant, before any text)
        if role == .assistant, isStreaming, let thoughtTime = thoughtTimeString {
            let statusLabel = makeLabel(
                thoughtTime,
                font: saCaptionFont,
                color: .saTextSecondary
            )
            statusLabel.alignment = .left
            statusLabel.identifier = NSUserInterfaceItemIdentifier("thoughtTime")
            subviews.append(statusLabel)
        }

        for block in message.blocks {
            switch block {
            case .text(let text):
                if role == .user {
                    subviews.append(makeUserBubble(text))
                } else {
                    subviews.append(makeAssistantText(text))
                }

            case .thinking(let text, let isExpanded):
                let thinkingViews = makeThinkingBlock(text, isExpanded: isExpanded)
                subviews.append(contentsOf: thinkingViews)

            case .toolUse(let toolUse):
                subviews.append(makeToolUseCard(toolUse))

            case .toolResult(let result):
                subviews.append(makeToolResultCard(result))

            case .systemReminder(let text):
                subviews.append(makeSystemReminder(text))
            }
        }

        // Add to view hierarchy
        for view in subviews {
            addSubview(view)
        }
        blockViews = subviews

        DLog("configure() done — \(blockViews.count) block views added")
        needsLayout = true
    }

    // MARK: - Layout

    public override var isFlipped: Bool { true }

    /// Compute the cell height for a given available width.
    /// Uses `NSTextField.sizeThatFits(_:)` for text views so wrapping
    /// is measured correctly (unlike `fittingSize` which ignores
    /// preferredMaxLayoutWidth).
    public func height(forWidth width: CGFloat) -> CGFloat {
        let contentWidth = width - kCellHorizontalPadding * 2
        guard !blockViews.isEmpty else {
            DLog("height(forWidth:\(width)) → EMPTY, returning \(kCellVerticalPadding * 2)")
            return kCellVerticalPadding * 2
        }

        DLog("height(forWidth:\(width)) contentWidth=\(contentWidth) role=\(role) blocks=\(blockViews.count)")
        var totalHeight: CGFloat = kCellVerticalPadding

        for (i, view) in blockViews.enumerated() {
            let itemWidth: CGFloat
            if view is UserBubbleView {
                itemWidth = min(contentWidth, kUserBubbleMaxWidth)
            } else if view is ToolResultCardView {
                itemWidth = contentWidth - kToolResultLeadingPad
            } else {
                itemWidth = contentWidth
            }

            let textMaxWidth = view is UserBubbleView
                ? itemWidth - kUserBubbleHPadding * 2
                : itemWidth

            let size = measuredSize(of: view, maxWidth: textMaxWidth)
            DLog("  block[\(i)] type=\(type(of: view)) itemWidth=\(itemWidth) textMaxWidth=\(textMaxWidth) measured=\(size)")
            totalHeight += max(size.height, 1) + kBlockSpacing
        }

        totalHeight -= kBlockSpacing
        let result = totalHeight + kCellVerticalPadding
        DLog("height(forWidth:\(width)) → \(result)")
        return result
    }

    /// Measure a view: for containers with their own intrinsicContentSize
    /// (UserBubbleView, ToolResultCardView), use fittingSize which includes
    /// padding. For bare NSTextField use cellSize(forBounds:). Falls back
    /// to fittingSize for everything else.
    private func measuredSize(of view: NSView, maxWidth: CGFloat) -> CGSize {
        // Containers with their own size logic — use fittingSize after setting widths
        if view is UserBubbleView {
            setMaxLayoutWidth(on: view, maxWidth: maxWidth)
            let fs = view.fittingSize
            DLog("    measuredSize UserBubbleView fittingSize=\(fs) maxWidth=\(maxWidth)")
            return fs
        }
        if view is ToolResultCardView {
            setMaxLayoutWidth(on: view, maxWidth: maxWidth)
            let fs = view.fittingSize
            DLog("    measuredSize ToolResultCardView fittingSize=\(fs) maxWidth=\(maxWidth)")
            return fs
        }
        if view is ToolUseCardView {
            setMaxLayoutWidth(on: view, maxWidth: maxWidth)
            let fs = view.fittingSize
            DLog("    measuredSize ToolUseCardView fittingSize=\(fs)")
            return fs
        }
        // Bare NSTextField — use cellSize for correct wrapping measurement
        if let tf = view as? NSTextField, tf.maximumNumberOfLines != 1, maxWidth > 0,
           let cell = tf.cell {
            cell.usesSingleLineMode = false
            cell.wraps = true
            let bounds = NSRect(x: 0, y: 0, width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
            let size = cell.cellSize(forBounds: bounds)
            DLog("    measuredSize NSTextField maxWidth=\(maxWidth) cellSize=\(size) string='\(tf.stringValue.prefix(40))'")
            return size
        }
        // Simple containers or NSButton — use fittingSize
        let fs = view.fittingSize
        DLog("    measuredSize fittingSize=\(fs) type=\(type(of: view))")
        return fs
    }

    public override func layout() {
        super.layout()

        var y: CGFloat = kCellVerticalPadding
        let contentWidth = bounds.width - kCellHorizontalPadding * 2
        DLog("layout() bounds=\(bounds) contentWidth=\(contentWidth) blocks=\(blockViews.count)")
        guard !blockViews.isEmpty else { return }

        for (i, view) in blockViews.enumerated() {
            let itemWidth: CGFloat
            if view is UserBubbleView {
                itemWidth = min(contentWidth, kUserBubbleMaxWidth)
            } else if view is ToolResultCardView {
                itemWidth = contentWidth - kToolResultLeadingPad
            } else if view is SystemReminderView {
                itemWidth = contentWidth
            } else {
                itemWidth = contentWidth
            }

            let textMaxWidth = view is UserBubbleView
                ? itemWidth - kUserBubbleHPadding * 2
                : itemWidth

            let size = measuredSize(of: view, maxWidth: textMaxWidth)
            let height = max(size.height, 1)

            // Also set preferredMaxLayoutWidth so rendering uses wrapped layout
            setMaxLayoutWidth(on: view, maxWidth: textMaxWidth)

            let frame: CGRect
            if view is UserBubbleView {
                let bubbleWidth = min(size.width, kUserBubbleMaxWidth)
                let x = bounds.width - kCellHorizontalPadding - bubbleWidth
                frame = CGRect(x: x, y: y, width: bubbleWidth, height: height)
            } else if view is ToolResultCardView {
                frame = CGRect(
                    x: kCellHorizontalPadding + kToolResultLeadingPad,
                    y: y,
                    width: itemWidth,
                    height: height
                )
            } else if view is SystemReminderView {
                frame = CGRect(
                    x: kCellHorizontalPadding,
                    y: y,
                    width: contentWidth,
                    height: height
                )
            } else {
                frame = CGRect(
                    x: kCellHorizontalPadding,
                    y: y,
                    width: itemWidth,
                    height: height
                )
            }
            view.frame = frame
            DLog("  block[\(i)] \(type(of: view)) frame=\(frame) textMaxWidth=\(textMaxWidth)")

            y += height + kBlockSpacing
        }
        DLog("layout() DONE — total cell height=\(y - kBlockSpacing + kCellVerticalPadding) (y ends at \(y))")
    }

    /// Recursively set `preferredMaxLayoutWidth` on NSTextField descendants
    /// so the text field actually renders wrapped text.
    private func setMaxLayoutWidth(on view: NSView, maxWidth: CGFloat) {
        if let tf = view as? NSTextField, tf.maximumNumberOfLines != 1 {
            tf.preferredMaxLayoutWidth = max(maxWidth, 0)
            DLog("    setMaxLayoutWidth NSTextField maxWidth=\(maxWidth) prefMax=\(tf.preferredMaxLayoutWidth)")
        }
        for sub in view.subviews {
            setMaxLayoutWidth(on: sub, maxWidth: maxWidth)
        }
    }

    // MARK: - Block Builders

    private func makeLabel(_ text: String, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) -> NSTextField {
        let tf = NSTextField()
        tf.font = font
        tf.textColor = color
        tf.isSelectable = true
        tf.allowsEditingTextAttributes = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        tf.cell?.wraps = true
        tf.cell?.usesSingleLineMode = false
        tf.stringValue = text
        if let maxWidth = maxWidth {
            tf.preferredMaxLayoutWidth = maxWidth
        }
        return tf
    }

    // MARK: User Bubble

    private func makeUserBubble(_ text: String) -> NSView {
        let bubble = UserBubbleView()
        bubble.configure(text: text)
        return bubble
    }

    // MARK: Assistant Text

    private func makeAssistantText(_ text: String) -> NSView {
        if text.isEmpty && isStreaming {
            let tf = NSTextField()
            tf.font = saBodyFont
            tf.textColor = .saTextPrimary
            tf.isSelectable = true
            tf.isBezeled = false
            tf.drawsBackground = false
            tf.isEditable = false
            tf.lineBreakMode = .byWordWrapping
            tf.maximumNumberOfLines = 0
            tf.cell?.wraps = true
            tf.cell?.usesSingleLineMode = false
            tf.stringValue = " "
            return tf
        }

        let tf = NSTextField()
        tf.font = saBodyFont
        tf.textColor = .saTextPrimary
        tf.isSelectable = true
        tf.allowsEditingTextAttributes = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        tf.cell?.wraps = true
        tf.cell?.usesSingleLineMode = false
        tf.stringValue = text
        return tf
    }

    // MARK: Thinking Block

    private func makeThinkingBlock(_ content: String, isExpanded: Bool) -> [NSView] {
        var views: [NSView] = []

        // Toggle button
        let btn = NSButton(frame: .zero)
        btn.title = ""
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.imagePosition = .imageLeading
        btn.target = self
        btn.action = #selector(thinkingToggled)
        btn.attributedTitle = makeThinkingToggleTitle(expanded: reasoningExpanded)
        btn.sizeToFit()
        thinkingToggleButton = btn
        views.append(btn)

        // Always create content view; show/hide based on expansion state
        if !content.isEmpty {
            let contentLabel = makeLabel(content, font: saCaptionFont, color: .saTextTertiary)
            contentLabel.identifier = NSUserInterfaceItemIdentifier("thinkingContent")
            contentLabel.isHidden = !reasoningExpanded
            views.append(contentLabel)
        }

        return views
    }

    private func makeThinkingToggleTitle(expanded: Bool) -> NSAttributedString {
        let icon = expanded ? "▾" : "▸"
        let thinkingText = isStreaming ? "Thinking..." : "Thinking"
        let fullText = "\(icon)  \(thinkingText)"

        let attr = NSMutableAttributedString(string: fullText)
        let range = NSRange(location: 0, length: fullText.utf16.count)
        attr.addAttribute(.font, value: saCaptionFont, range: range)
        attr.addAttribute(.foregroundColor, value: NSColor.saTextSecondary, range: range)
        return attr
    }

    @objc private func thinkingToggled() {
        let oldHeight = frame.height
        DLog("🔘 thinkingToggled — old cell height=\(oldHeight) reasoningExpanded=\(reasoningExpanded)")
        onToggleReasoning?()
        // Height will update when configure() is called next
    }

    private func updateReasoningVisibility() {
        guard let btn = thinkingToggleButton else { return }
        let oldHeight = frame.height
        btn.attributedTitle = makeThinkingToggleTitle(expanded: reasoningExpanded)

        let contentID = NSUserInterfaceItemIdentifier("thinkingContent")
        for view in blockViews where view.identifier == contentID {
            view.isHidden = !reasoningExpanded
        }

        DLog("🔘 updateReasoningVisibility expanded=\(reasoningExpanded) oldHeight=\(oldHeight) — marking dirty")
        needsLayout = true
        superview?.needsLayout = true
    }

    private func updateStreamingState() {
        guard let btn = thinkingToggleButton else { return }
        btn.attributedTitle = makeThinkingToggleTitle(expanded: reasoningExpanded)
    }

    // MARK: Tool Use Card

    private func makeToolUseCard(_ toolUse: ToolUseBlock) -> NSView {
        let card = ToolUseCardView()
        card.configure(toolUse: toolUse)
        return card
    }

    // MARK: Tool Result Card

    private func makeToolResultCard(_ result: ToolResultBlock) -> NSView {
        let card = ToolResultCardView()
        card.configure(result: result)
        return card
    }

    // MARK: System Reminder

    private func makeSystemReminder(_ text: String) -> NSView {
        let reminder = SystemReminderView()
        reminder.configure(text: text)
        return reminder
    }
}

// MARK: - UserBubbleView

/// Right-aligned rounded bubble for user messages.
final class UserBubbleView: NSView {
    private let label: NSTextField = {
        let tf = NSTextField()
        tf.font = saBodyFont
        tf.textColor = .saTextPrimary
        tf.isSelectable = true
        tf.allowsEditingTextAttributes = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        tf.cell?.wraps = true
        tf.cell?.usesSingleLineMode = false
        return tf
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = kUserBubbleCornerRadius
        layer?.backgroundColor = NSColor.saBgElevated.cgColor
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = kUserBubbleMaxWidth - kUserBubbleHPadding * 2
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let pad = kUserBubbleHPadding
        label.frame = CGRect(
            x: pad,
            y: kUserBubbleVPadding,
            width: bounds.width - pad * 2,
            height: bounds.height - kUserBubbleVPadding * 2
        )
    }

    override var intrinsicContentSize: CGSize {
        let maxContentWidth: CGFloat = kUserBubbleMaxWidth - kUserBubbleHPadding * 2
        label.preferredMaxLayoutWidth = maxContentWidth
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        let cellSize = label.cell?.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: maxContentWidth, height: CGFloat.greatestFiniteMagnitude
        )) ?? label.intrinsicContentSize
        // ceil the width so the bubble is always >=1px wider than the text,
        // preventing edge-case wrap-to-next-line from floating-point precision.
        let textWidth = ceil(cellSize.width)
        return CGSize(
            width: min(textWidth, kUserBubbleMaxWidth) + kUserBubbleHPadding * 2,
            height: cellSize.height + kUserBubbleVPadding * 2
        )
    }
}

// MARK: - ToolUseCardView

final class ToolUseCardView: NSView {
    private let iconView = NSTextField(labelWithString: "")
    private let toolNameLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let statusDot = StatusDotView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = kToolCardCornerRadius
        layer?.backgroundColor = NSColor.saBgElevated.withAlphaComponent(0.6).cgColor
        layer?.borderColor = NSColor.saBorderSubtle.cgColor
        layer?.borderWidth = 0.5

        iconView.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        iconView.textColor = .saTextSecondary
        iconView.isBezeled = false
        iconView.drawsBackground = false
        iconView.isSelectable = false
        addSubview(iconView)

        toolNameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        toolNameLabel.textColor = .saTextSecondary
        toolNameLabel.isBezeled = false
        toolNameLabel.drawsBackground = false
        toolNameLabel.isSelectable = false
        toolNameLabel.lineBreakMode = .byTruncatingTail
        addSubview(toolNameLabel)

        summaryLabel.font = saSmallFont
        summaryLabel.textColor = .saTextTertiary
        summaryLabel.isBezeled = false
        summaryLabel.drawsBackground = false
        summaryLabel.isSelectable = false
        summaryLabel.lineBreakMode = .byTruncatingTail
        addSubview(summaryLabel)

        addSubview(statusDot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(toolUse: ToolUseBlock) {
        iconView.stringValue = toolIcon(for: toolUse.toolName)
        toolNameLabel.stringValue = toolUse.toolName
        summaryLabel.stringValue = toolUse.inputSummary
        statusDot.configure(status: toolUse.status)
        invalidateIntrinsicContentSize()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let pad = kToolCardHPadding
        let vPad = kToolCardVPadding

        iconView.sizeToFit()
        iconView.frame.origin = CGPoint(x: pad, y: vPad + 2)

        let textX = iconView.frame.maxX + 8
        let textWidth = max(0, bounds.width - textX - pad - 24)

        toolNameLabel.frame = CGRect(x: textX, y: vPad, width: textWidth, height: 16)
        summaryLabel.frame = CGRect(x: textX, y: vPad + 16, width: textWidth, height: 14)

        statusDot.frame.size = statusDot.intrinsicContentSize
        statusDot.frame.origin = CGPoint(
            x: bounds.width - pad - statusDot.bounds.width,
            y: vPad + CGFloat((40 - statusDot.bounds.height) / 2)
        )
    }

    override var intrinsicContentSize: CGSize {
        // Fixed height for tool cards
        return CGSize(width: 400, height: 40)
    }

    private func toolIcon(for toolName: String) -> String {
        switch toolName {
        case "Bash", "PowerShell": return ">_"
        case "Read", "FileRead": return "📄"
        case "Write", "FileWrite": return "📝"
        case "Edit", "FileEdit": return "✏️"
        case "Grep": return "🔍"
        case "Glob": return "📁"
        case "WebFetch", "WebSearch": return "🌐"
        case "Task", "TaskCreate", "TaskGet", "TaskList", "TaskStop": return "📋"
        case "Agent": return "🤖"
        case "Skill": return "✨"
        case "TodoWrite": return "✅"
        case "NotebookEdit": return "📓"
        default: return "🔧"
        }
    }
}

// MARK: - StatusDotView

final class StatusDotView: NSView {
    private var status: ToolUseStatus = .pending
    private var spinner: NSProgressIndicator?

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.frame.size = CGSize(width: 14, height: 14)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(status: ToolUseStatus) {
        self.status = status
        spinner?.removeFromSuperview()
        spinner = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()

        if case .executing = status {
            let spin = NSProgressIndicator(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
            spin.style = .spinning
            spin.controlSize = .small
            spin.isIndeterminate = true
            spin.startAnimation(nil)
            addSubview(spin)
            spinner = spin
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch status {
        case .pending:
            NSColor.saTextTertiary.setFill()
            let path = NSBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 6, height: 6))
            path.fill()
        case .completed:
            NSColor.saSuccess.setFill()
            let checkImg = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            checkImg?.draw(in: bounds)
        case .error:
            NSColor.saDanger.setFill()
            let xImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            xImg?.draw(in: bounds)
        case .executing:
            break // spinner handles this
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 14, height: 14)
    }
}

// MARK: - ToolResultCardView

final class ToolResultCardView: NSView {
    private let headerIcon = NSTextField(labelWithString: "")
    private let headerLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        headerIcon.font = saSmallFont
        headerIcon.textColor = .saTextTertiary
        headerIcon.isBezeled = false
        headerIcon.drawsBackground = false
        headerIcon.isSelectable = false
        addSubview(headerIcon)

        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        headerLabel.textColor = .saTextTertiary
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        headerLabel.isSelectable = false
        addSubview(headerLabel)

        contentLabel.font = saSmallFont
        contentLabel.textColor = .saTextTertiary
        contentLabel.isSelectable = true
        contentLabel.isBezeled = false
        contentLabel.drawsBackground = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 6
        addSubview(contentLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(result: ToolResultBlock) {
        if result.isError {
            headerIcon.stringValue = "✕"
            headerIcon.textColor = .saDanger
            headerLabel.stringValue = "Error"
            headerLabel.textColor = .saDanger
        } else {
            headerIcon.stringValue = "↩"
            headerIcon.textColor = .saTextTertiary
            headerLabel.stringValue = "Result"
            headerLabel.textColor = .saTextTertiary
        }

        let truncated = String(result.content.prefix(500))
        contentLabel.stringValue = truncated
        contentLabel.maximumNumberOfLines = result.isExpanded ? 0 : 6

        invalidateIntrinsicContentSize()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()

        headerIcon.sizeToFit()
        headerIcon.frame.origin = CGPoint(x: 0, y: 0)

        headerLabel.sizeToFit()
        headerLabel.frame.origin = CGPoint(x: headerIcon.frame.maxX + 4, y: 0)

        let contentY = max(headerIcon.frame.maxY, headerLabel.frame.maxY) + 4
        let contentFit = contentLabel.sizeThatFits(
            CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        )
        contentLabel.frame = CGRect(
            x: 0,
            y: contentY,
            width: bounds.width,
            height: contentFit.height
        )
    }

    override var intrinsicContentSize: CGSize {
        headerIcon.sizeToFit()
        headerLabel.sizeToFit()
        let headerHeight = max(headerIcon.bounds.height, headerLabel.bounds.height)

        let contentFit = contentLabel.sizeThatFits(
            CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        )

        return CGSize(
            width: 400,
            height: headerHeight + 4 + contentFit.height
        )
    }
}

// MARK: - SystemReminderView

final class SystemReminderView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = saSmallFont
        label.textColor = .saTextTertiary.withAlphaComponent(0.6)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isSelectable = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        label.stringValue = text
        invalidateIntrinsicContentSize()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame = CGRect(
            x: 0,
            y: 2,
            width: bounds.width,
            height: label.bounds.height
        )
    }

    override var intrinsicContentSize: CGSize {
        label.sizeToFit()
        return CGSize(width: label.bounds.width, height: label.bounds.height + 4)
    }
}
