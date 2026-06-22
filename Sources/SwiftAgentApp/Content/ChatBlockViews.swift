import AppKit

// MARK: - Design Tokens (shared with existing ChatMessageCell)

extension NSColor {
    static let cbBgContent     = NSColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1)
    static let cbBgElevated    = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
    static let cbTextPrimary   = NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)
    static let cbTextSecondary = NSColor(red: 0.600, green: 0.600, blue: 0.600, alpha: 1)
    static let cbTextTertiary  = NSColor(red: 0.400, green: 0.400, blue: 0.400, alpha: 1)
    static let cbAccent        = NSColor(red: 0.200, green: 0.612, blue: 1.000, alpha: 1)
    static let cbSuccess       = NSColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1)
    static let cbDanger        = NSColor(red: 0.973, green: 0.318, blue: 0.286, alpha: 1)
    static let cbBorder        = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
}

// MARK: - Font Tokens

nonisolated(unsafe) let cbBodyFont    = NSFont.systemFont(ofSize: 15)
nonisolated(unsafe) let cbCaptionFont = NSFont.systemFont(ofSize: 13)
nonisolated(unsafe) let cbSmallFont   = NSFont.systemFont(ofSize: 11)
nonisolated(unsafe) let cbCodeFont    = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
nonisolated(unsafe) let cbToolLabelFont = NSFont.systemFont(ofSize: 12)
nonisolated(unsafe) let cbToolResultFont = NSFont.systemFont(ofSize: 11)
nonisolated(unsafe) let cbToolResultHeaderFont = NSFont.systemFont(ofSize: 12, weight: .medium)

// MARK: - Layout Constants

public let kBlockHPadding: CGFloat = 16
public let kBlockVSpacing: CGFloat = 6
public let kCellSpacing: CGFloat = 6
public let kUserBubbleMaxW: CGFloat = 460
public let kUserBubbleHPad: CGFloat = 14
public let kUserBubbleVPad: CGFloat = 10
public let kUserBubbleRadius: CGFloat = 12
public let kToolCardRadius: CGFloat = 6
public let kToolCardHPad: CGFloat = 10
public let kToolCardVPad: CGFloat = 6
public let kToolResultLeading: CGFloat = 28

// MARK: - Block View Protocol

/// A view that renders a single AgentMessageBlock within a chat cell.
/// Supports in-place text updates for streaming.
public protocol ChatBlockView: NSView {
    /// Update the text content without rebuilding the view.
    /// Returns true if the view supports in-place updates for this block type.
    func updateContent(with block: AgentMessageBlock) -> Bool
    /// The block type this view is currently rendering.
    var blockKind: AgentMessageBlock.BlockKind { get }
}

// MARK: - Block Kind Enum

extension AgentMessageBlock {
    public enum BlockKind: Equatable {
        case text
        case thinking
        case toolUse
        case toolResult
        case systemReminder
    }

    public var kind: BlockKind {
        switch self {
        case .text: return .text
        case .thinking: return .thinking
        case .toolUse: return .toolUse
        case .toolResult: return .toolResult
        case .systemReminder: return .systemReminder
        }
    }
}

// MARK: - TextBlockView

/// Renders assistant text or a user bubble. Supports in-place text updates
/// for streaming. User text is right-aligned in a rounded bubble;
/// assistant text is left-aligned, selectable.
public final class TextBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .text
    private var role: AgentMessageRole = .assistant
    private var layoutWidth: CGFloat = 600

    private let label = NSTextField(labelWithString: "")
    private let bubbleBg = NSView()

    public override init(frame: NSRect) {
        super.init(frame: frame)

        bubbleBg.wantsLayer = true
        bubbleBg.layer?.cornerRadius = kUserBubbleRadius
        bubbleBg.layer?.backgroundColor = NSColor.cbBgElevated.cgColor
        bubbleBg.isHidden = true
        addSubview(bubbleBg)

        label.isBezeled = false
        label.drawsBackground = false
        label.isSelectable = true
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(text: String, role: AgentMessageRole, layoutWidth: CGFloat = 600) {
        self.role = role
        self.layoutWidth = layoutWidth
        label.stringValue = text
        bubbleBg.isHidden = (role != .user)

        switch role {
        case .user:
            label.font = cbBodyFont
            label.textColor = .cbTextPrimary
            label.alignment = .left
            label.preferredMaxLayoutWidth = kUserBubbleMaxW - kUserBubbleHPad * 2
        case .assistant, .system:
            label.font = cbBodyFont
            label.textColor = .cbTextPrimary
            label.alignment = .left
            label.preferredMaxLayoutWidth = layoutWidth
        }

        invalidateIntrinsicContentSize()
    }

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        guard case .text(let text) = block else { return false }
        label.stringValue = text
        invalidateIntrinsicContentSize()
        return true
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        if role == .user {
            let maxTextW = kUserBubbleMaxW - kUserBubbleHPad * 2
            let fit = label.sizeThatFits(CGSize(width: maxTextW, height: CGFloat.greatestFiniteMagnitude))
            let bubbleW = fit.width + kUserBubbleHPad * 2
            let bubbleH = fit.height + kUserBubbleVPad * 2
            bubbleBg.frame = CGRect(x: bounds.width - bubbleW, y: 0,
                                    width: bubbleW, height: bubbleH)
            bubbleBg.isHidden = false
            label.frame = CGRect(x: bounds.width - bubbleW + kUserBubbleHPad,
                                 y: kUserBubbleVPad,
                                 width: fit.width, height: fit.height)
        } else {
            bubbleBg.isHidden = true
            let fit = label.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
            label.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fit.height)
        }
    }

    public override var intrinsicContentSize: CGSize {
        switch role {
        case .user:
            let maxTextW = kUserBubbleMaxW - kUserBubbleHPad * 2
            let fit = label.sizeThatFits(CGSize(width: maxTextW, height: CGFloat.greatestFiniteMagnitude))
            // Fill the full stack width so the bubble can right-align within it.
            return CGSize(width: layoutWidth, height: fit.height + kUserBubbleVPad * 2)
        case .assistant, .system:
            let fit = label.sizeThatFits(CGSize(width: layoutWidth, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: layoutWidth, height: fit.height)
        }
    }
}

// MARK: - ThinkingBlockView

/// Collapsible thinking/reasoning display with chevron toggle.
/// Shows "Thinking..." during streaming, "Thought for Xs" after completion.
public final class ThinkingBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .thinking

    private let toggleButton = NSButton()
    private let contentLabel = NSTextField(labelWithString: "")
    private let container = NSView()

    private var isExpanded: Bool = false
    private var layoutWidth: CGFloat = 600
    private var onToggle: (() -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)

        // Toggle button
        toggleButton.bezelStyle = .inline
        toggleButton.isBordered = false
        toggleButton.font = cbCaptionFont
        toggleButton.target = self
        toggleButton.action = #selector(togglePressed)
        addSubview(toggleButton)

        // Content label (indented, only shown when expanded)
        contentLabel.isBezeled = false
        contentLabel.drawsBackground = false
        contentLabel.isSelectable = true
        contentLabel.font = cbCaptionFont
        contentLabel.textColor = .cbTextTertiary
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.preferredMaxLayoutWidth = layoutWidth - 16
        contentLabel.isHidden = true
        addSubview(contentLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configure or reconfigure the thinking block.
    public func configure(
        content: String,
        expanded: Bool,
        isStreaming: Bool,
        thoughtTimeString: String?,
        layoutWidth: CGFloat = 600,
        onToggle: @escaping () -> Void
    ) {
        self.isExpanded = expanded
        self.layoutWidth = layoutWidth
        self.onToggle = onToggle

        let title: String
        if isStreaming {
            title = "Thinking..."
        } else if let thoughtTime = thoughtTimeString {
            title = thoughtTime
        } else {
            title = "Thinking"
        }

        let chevron = expanded ? "▾" : "▸"
        toggleButton.title = "  \(chevron)  \(title)"
        toggleButton.sizeToFit()

        contentLabel.stringValue = content
        contentLabel.preferredMaxLayoutWidth = layoutWidth - 16
        contentLabel.isHidden = !expanded || content.isEmpty

        invalidateIntrinsicContentSize()
    }

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        guard case .thinking(let text, let expanded) = block else { return false }
        self.isExpanded = expanded
        contentLabel.stringValue = text
        contentLabel.isHidden = !expanded || text.isEmpty
        invalidateIntrinsicContentSize()
        return true
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        toggleButton.sizeToFit()
        toggleButton.frame.origin = .zero

        if isExpanded {
            let y = toggleButton.frame.maxY + kBlockVSpacing
            let fit = contentLabel.sizeThatFits(
                CGSize(width: bounds.width - 16, height: CGFloat.greatestFiniteMagnitude)
            )
            contentLabel.frame = CGRect(x: 16, y: y, width: bounds.width - 16, height: fit.height)
        } else {
            contentLabel.frame = .zero
        }
    }

    public override var intrinsicContentSize: CGSize {
        toggleButton.sizeToFit()
        var h = toggleButton.bounds.height

        if isExpanded && !contentLabel.stringValue.isEmpty {
            let w = max(layoutWidth - 16, 100)
            let fit = contentLabel.sizeThatFits(
                CGSize(width: w, height: CGFloat.greatestFiniteMagnitude)
            )
            h += kBlockVSpacing + fit.height
        }

        return CGSize(width: layoutWidth, height: h)
    }
}

// MARK: - ToolUseBlockView

/// Card showing a tool invocation (icon, name, summary, status).
/// Clicking toggles the associated tool result below.
/// The card itself is always fully visible; the chevron indicates
/// whether the result block is expanded (▾) or collapsed (▸).
public final class ToolUseBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .toolUse

    private let iconLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let statusView = NSView()
    private let chevronLabel = NSTextField(labelWithString: "")

    private var toolUseID: String = ""
    private var isResultExpanded: Bool = true
    private var onToggle: (() -> Void)?

    /// Transparent overlay button that handles clicks for the entire card.
    /// Placed as the last (topmost) subview so it always receives mouse events,
    /// regardless of which child label the user clicks on.
    private let clickButton = NSButton()

    public override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = kToolCardRadius
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.cbBorder.cgColor
        layer?.backgroundColor = NSColor.cbBgElevated.withAlphaComponent(0.6).cgColor

        iconLabel.font = cbToolLabelFont
        iconLabel.textColor = .cbTextSecondary
        iconLabel.isBezeled = false
        iconLabel.drawsBackground = false
        addSubview(iconLabel)

        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .cbTextSecondary
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        addSubview(nameLabel)

        summaryLabel.font = cbSmallFont
        summaryLabel.textColor = .cbTextTertiary
        summaryLabel.isBezeled = false
        summaryLabel.drawsBackground = false
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        addSubview(summaryLabel)

        statusView.wantsLayer = true
        addSubview(statusView)

        chevronLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        chevronLabel.textColor = .cbTextTertiary
        chevronLabel.isBezeled = false
        chevronLabel.drawsBackground = false
        chevronLabel.stringValue = "▾"
        chevronLabel.sizeToFit()
        addSubview(chevronLabel)

        clickButton.isBordered = false
        clickButton.isTransparent = true
        clickButton.title = ""
        clickButton.target = self
        clickButton.action = #selector(cardClicked)
        addSubview(clickButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `isResultExpanded` controls the chevron direction and is driven by
    /// the FoldTarget.toolResult state in the message-level FoldState.
    public func configure(toolUse: ToolUseBlock, isResultExpanded: Bool = true, onToggle: (() -> Void)? = nil) {
        self.toolUseID = toolUse.toolUseID
        self.isResultExpanded = isResultExpanded
        self.onToggle = onToggle

        iconLabel.stringValue = toolIcon(for: toolUse.toolName)
        nameLabel.stringValue = toolUse.toolName
        summaryLabel.stringValue = toolUse.inputSummary

        chevronLabel.stringValue = isResultExpanded ? "▾" : "▸"
        chevronLabel.sizeToFit()

        updateStatusBadge(toolUse.status)

        iconLabel.sizeToFit()
        nameLabel.sizeToFit()
        summaryLabel.sizeToFit()

        invalidateIntrinsicContentSize()
    }

    public func updateResultExpanded(_ expanded: Bool) {
        isResultExpanded = expanded
        chevronLabel.stringValue = expanded ? "▾" : "▸"
        chevronLabel.sizeToFit()
        needsLayout = true
    }

    public func updateStatus(_ status: ToolUseStatus) {
        updateStatusBadge(status)
        needsLayout = true
    }

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        guard case .toolUse(let toolUse) = block else { return false }
        updateStatusBadge(toolUse.status)
        needsLayout = true
        return true
    }

    @objc private func cardClicked() {
        onToggle?()
    }

    private func updateStatusBadge(_ status: ToolUseStatus) {
        statusView.subviews.forEach { $0.removeFromSuperview() }

        switch status {
        case .pending:
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.cbTextTertiary.cgColor
            dot.layer?.cornerRadius = 3
            statusView.addSubview(dot)
            statusView.frame.size = CGSize(width: 6, height: 6)

        case .executing:
            let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            statusView.addSubview(spinner)
            statusView.frame.size = CGSize(width: 14, height: 14)

        case .completed:
            let check = NSTextField(labelWithString: "✓")
            check.font = cbBodyFont
            check.textColor = .cbSuccess
            check.isBezeled = false
            check.drawsBackground = false
            check.sizeToFit()
            statusView.addSubview(check)
            statusView.frame = check.bounds

        case .error(let msg):
            let err = NSTextField(labelWithString: "✕ \(msg.truncated(to: 40))")
            err.font = cbSmallFont
            err.textColor = .cbDanger
            err.isBezeled = false
            err.drawsBackground = false
            err.lineBreakMode = .byTruncatingTail
            err.maximumNumberOfLines = 1
            err.sizeToFit()
            statusView.addSubview(err)
            statusView.frame = err.bounds
        }
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        iconLabel.sizeToFit()
        iconLabel.frame.origin = CGPoint(x: kToolCardHPad, y: kToolCardVPad)

        chevronLabel.sizeToFit()
        chevronLabel.frame.origin = CGPoint(
            x: bounds.width - kToolCardHPad - chevronLabel.bounds.width,
            y: kToolCardVPad + 1
        )

        nameLabel.sizeToFit()
        nameLabel.frame.origin = CGPoint(x: iconLabel.frame.maxX + 8, y: kToolCardVPad)

        statusView.frame.origin = CGPoint(
            x: chevronLabel.frame.minX - statusView.bounds.width - 8,
            y: kToolCardVPad
        )

        summaryLabel.frame = CGRect(
            x: iconLabel.frame.minX,
            y: max(iconLabel.frame.maxY, nameLabel.frame.maxY) + 2,
            width: bounds.width - kToolCardHPad * 2,
            height: summaryLabel.bounds.height
        )

        clickButton.frame = bounds
    }

    public override var intrinsicContentSize: CGSize {
        iconLabel.sizeToFit()
        nameLabel.sizeToFit()
        summaryLabel.sizeToFit()

        let headerH = max(iconLabel.bounds.height, nameLabel.bounds.height)
        let totalH = kToolCardVPad * 2 + headerH + 2 + summaryLabel.bounds.height

        return CGSize(width: 400, height: totalH)
    }

    private func toolIcon(for toolName: String) -> String {
        switch toolName {
        case "Bash", "PowerShell": return ">_"
        case "Read", "FileRead": return "📄"
        case "Write", "FileWrite": return "✎"
        case "Edit", "FileEdit": return "✏️"
        case "Grep": return "⌕"
        case "Glob": return "📁"
        case "WebFetch", "WebSearch": return "🌐"
        case "Task", "TaskCreate", "TaskGet", "TaskList", "TaskStop": return "📋"
        case "Agent": return "🤖"
        case "Skill": return "⚡"
        case "TodoWrite": return "✅"
        default: return "🔧"
        }
    }
}

// MARK: - ToolResultBlockView

/// Tool result display block. Visibility toggled by clicking the tool card above.
/// The header row (icon + label) is always visible; content is hidden when collapsed.
/// No chevron or click handler — the tool card controls expand/collapse.
public final class ToolResultBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .toolResult

    private let headerIcon = NSTextField(labelWithString: "")
    private let headerLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(wrappingLabelWithString: "")

    private var isExpanded: Bool = true
    private var layoutWidth: CGFloat = 400
    private var toolUseID: String = ""

    public override init(frame: NSRect) {
        super.init(frame: frame)

        headerIcon.font = cbToolResultHeaderFont
        headerIcon.isBezeled = false
        headerIcon.drawsBackground = false
        addSubview(headerIcon)

        headerLabel.font = cbToolResultHeaderFont
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        headerLabel.textColor = .cbTextTertiary
        addSubview(headerLabel)

        contentLabel.font = cbToolResultFont
        contentLabel.textColor = .cbTextTertiary
        contentLabel.isBezeled = false
        contentLabel.drawsBackground = false
        contentLabel.isSelectable = true
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.preferredMaxLayoutWidth = layoutWidth
        addSubview(contentLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(result: ToolResultBlock, expanded: Bool, layoutWidth: CGFloat = 400) {
        self.toolUseID = result.toolUseID
        self.isExpanded = expanded
        self.layoutWidth = layoutWidth

        if result.isError {
            headerIcon.stringValue = "✕"
            headerIcon.textColor = .cbDanger
            headerLabel.stringValue = "Error"
            headerLabel.textColor = .cbDanger
        } else {
            headerIcon.stringValue = "↩"
            headerIcon.textColor = .cbTextTertiary
            headerLabel.stringValue = "Result"
            headerLabel.textColor = .cbTextTertiary
        }

        headerIcon.isHidden = !expanded
        headerLabel.isHidden = !expanded

        let truncated = String(result.content.prefix(500))
        contentLabel.stringValue = truncated
        contentLabel.preferredMaxLayoutWidth = layoutWidth
        contentLabel.isHidden = !expanded

        headerIcon.sizeToFit()
        headerLabel.sizeToFit()

        invalidateIntrinsicContentSize()
    }

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        guard case .toolResult(let result) = block else { return false }
        let truncated = String(result.content.prefix(500))
        contentLabel.stringValue = truncated
        invalidateIntrinsicContentSize()
        return true
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        if !isExpanded {
            headerIcon.frame = .zero
            headerLabel.frame = .zero
            contentLabel.frame = .zero
            return
        }
        headerIcon.sizeToFit()
        headerIcon.frame.origin = .zero

        headerLabel.sizeToFit()
        headerLabel.frame.origin = CGPoint(x: headerIcon.frame.maxX + 4, y: 0)

        let contentY = max(headerIcon.frame.maxY, headerLabel.frame.maxY) + 4
        let fit = contentLabel.sizeThatFits(
            CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        )
        contentLabel.frame = CGRect(x: 0, y: contentY, width: bounds.width, height: fit.height)
    }

    public override var intrinsicContentSize: CGSize {
        if !isExpanded {
            return CGSize(width: layoutWidth, height: 0)
        }
        headerIcon.sizeToFit()
        headerLabel.sizeToFit()
        let headerH = max(headerIcon.bounds.height, headerLabel.bounds.height)

        let fit = contentLabel.sizeThatFits(
            CGSize(width: layoutWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: layoutWidth, height: headerH + 4 + fit.height)
    }
}

// MARK: - SystemReminderBlockView

/// Centered muted text for system reminders.
public final class SystemReminderBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .systemReminder

    private let label = NSTextField(labelWithString: "")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = cbSmallFont
        label.textColor = .cbTextTertiary.withAlphaComponent(0.6)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isSelectable = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(text: String) {
        label.stringValue = text
        invalidateIntrinsicContentSize()
    }

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        guard case .systemReminder(let text) = block else { return false }
        label.stringValue = text
        invalidateIntrinsicContentSize()
        return true
    }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame = CGRect(x: 0, y: 2, width: bounds.width, height: label.bounds.height)
    }

    public override var intrinsicContentSize: CGSize {
        label.sizeToFit()
        return CGSize(width: label.bounds.width, height: label.bounds.height + 4)
    }
}
