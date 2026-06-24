import AppKit

// MARK: - Design Tokens

extension NSColor {
    // Backgrounds
    static let cbBgContent     = NSColor(red: 0.110, green: 0.110, blue: 0.110, alpha: 1)   // #1C1C1C
    static let cbBgElevated    = NSColor(red: 0.145, green: 0.145, blue: 0.148, alpha: 1)   // #252528 — card background
    static let cbBgCardHover   = NSColor(red: 0.165, green: 0.165, blue: 0.168, alpha: 1)   // #2A2A2C — hover state
    // Text
    static let cbTextPrimary   = NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1)   // #F5F5F5
    static let cbTextSecondary = NSColor(red: 0.700, green: 0.700, blue: 0.720, alpha: 1)   // #B3B3B8
    static let cbTextTertiary  = NSColor(red: 0.500, green: 0.500, blue: 0.520, alpha: 1)   // #808084
    static let cbTextMuted     = NSColor(red: 0.400, green: 0.400, blue: 0.420, alpha: 1)   // #66666A
    // Status
    static let cbAccent        = NSColor(red: 0.200, green: 0.612, blue: 1.000, alpha: 1)   // #339CFF
    static let cbSuccess       = NSColor(red: 0.298, green: 0.824, blue: 0.392, alpha: 1)   // #4CD264
    static let cbDanger        = NSColor(red: 0.969, green: 0.325, blue: 0.306, alpha: 1)   // #F7534E
    static let cbWarning       = NSColor(red: 0.949, green: 0.725, blue: 0.255, alpha: 1)   // #F2B941
    // Borders
    static let cbBorder        = NSColor(red: 0.200, green: 0.200, blue: 0.210, alpha: 1)   // #333335
    static let cbBorderSubtle  = NSColor(red: 0.170, green: 0.170, blue: 0.178, alpha: 1)   // #2B2B2E
    // User bubble
    static let cbUserBubble    = NSColor(red: 0.165, green: 0.165, blue: 0.168, alpha: 1)   // #2A2A2C
}

// MARK: - Font Tokens

nonisolated(unsafe) let cbBodyFont       = NSFont.systemFont(ofSize: 14)
nonisolated(unsafe) let cbCaptionFont    = NSFont.systemFont(ofSize: 13)
nonisolated(unsafe) let cbSmallFont      = NSFont.systemFont(ofSize: 12)
nonisolated(unsafe) let cbCodeFont       = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
nonisolated(unsafe) let cbCardTitleFont  = NSFont.systemFont(ofSize: 13, weight: .semibold)
nonisolated(unsafe) let cbCardBodyFont   = NSFont.systemFont(ofSize: 12)
nonisolated(unsafe) let cbTimestampFont  = NSFont.systemFont(ofSize: 11)
nonisolated(unsafe) let cbIconFont       = NSFont.systemFont(ofSize: 13, weight: .medium)

// MARK: - Card Layout Constants

/// Uniform spacing between all block cards in a row.
public let kBlockVSpacing: CGFloat = 8
/// Horizontal padding inside the table row (outside cards).
public let kBlockHPadding: CGFloat = 16
/// Spacing between table rows (messages).
public let kCellSpacing: CGFloat = 2
/// Card corner radius.
public let kCardCornerRadius: CGFloat = 10
/// Card internal padding.
public let kCardHPad: CGFloat = 14
/// Card internal vertical padding (top/bottom of header row).
public let kCardVPad: CGFloat = 10
/// Icon badge size (width = height).
public let kIconBadgeSize: CGFloat = 22
/// Icon badge corner radius (circle).
public let kIconBadgeRadius: CGFloat = 6
/// Gap between icon badge and title.
public let kIconTitleGap: CGFloat = 8
/// Gap between title and timestamp (min, flex space fills).
public let kHeaderTimestampGap: CGFloat = 8
/// Card body top spacing (below header, above body text).
public let kCardBodyTopSpacing: CGFloat = 6
/// Min height of a collapsed card (header row only).
public let kCardCollapsedMinHeight: CGFloat = 36
/// User bubble constants
public let kUserBubbleMaxW: CGFloat = 480
public let kUserBubbleHPad: CGFloat = 14
public let kUserBubbleVPad: CGFloat = 10
public let kUserBubbleRadius: CGFloat = 14

// MARK: - Relative Time Formatter

func chatRelativeTime(from date: Date) -> String {
    let now = Date()
    let interval = now.timeIntervalSince(date)
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    return "\(Int(interval / 86400))d"
}

// MARK: - Tool Card Style

/// Maps tool names to their visual style: SF Symbol icon, tint color, and fallback emoji.
struct ToolCardStyle {
    let symbolName: String
    let color: NSColor
    let fallbackIcon: String

    /// Default style for unknown tools.
    static let fallback = ToolCardStyle(
        symbolName: "wrench.fill", color: .cbTextTertiary, fallbackIcon: "🔧"
    )

    /// Look up the visual style for a tool by name.
    static func forTool(_ name: String) -> ToolCardStyle {
        switch name {
        // Shell / execution
        case "Bash", "PowerShell":
            return ToolCardStyle(
                symbolName: "terminal.fill",
                color: NSColor(red: 0.298, green: 0.824, blue: 0.392, alpha: 1), // green
                fallbackIcon: ">_"
            )
        // File read
        case "Read", "FileRead":
            return ToolCardStyle(
                symbolName: "doc.text",
                color: NSColor(red: 0.376, green: 0.647, blue: 0.969, alpha: 1), // blue
                fallbackIcon: "📄"
            )
        // File write
        case "Write", "FileWrite":
            return ToolCardStyle(
                symbolName: "doc.badge.plus",
                color: NSColor(red: 0.376, green: 0.647, blue: 0.969, alpha: 1), // blue
                fallbackIcon: "✎"
            )
        // File edit
        case "Edit", "FileEdit":
            return ToolCardStyle(
                symbolName: "pencil",
                color: NSColor(red: 0.298, green: 0.824, blue: 0.392, alpha: 1), // green
                fallbackIcon: "✏️"
            )
        // Search
        case "Grep":
            return ToolCardStyle(
                symbolName: "magnifyingglass",
                color: NSColor(red: 0.949, green: 0.725, blue: 0.255, alpha: 1), // amber
                fallbackIcon: "⌕"
            )
        case "Glob":
            return ToolCardStyle(
                symbolName: "folder.fill",
                color: NSColor(red: 0.545, green: 0.529, blue: 0.749, alpha: 1), // violet
                fallbackIcon: "📁"
            )
        // Web
        case "WebFetch", "WebSearch":
            return ToolCardStyle(
                symbolName: "globe",
                color: NSColor(red: 0.376, green: 0.647, blue: 0.969, alpha: 1), // blue
                fallbackIcon: "🌐"
            )
        // Tasks
        case "Task", "TaskCreate", "TaskGet", "TaskList", "TaskStop", "TaskUpdate", "TaskOutput":
            return ToolCardStyle(
                symbolName: "checklist",
                color: NSColor(red: 0.376, green: 0.647, blue: 0.969, alpha: 1), // blue
                fallbackIcon: "📋"
            )
        // Agent / sub-agent
        case "Agent":
            return ToolCardStyle(
                symbolName: "brain.head.profile",
                color: NSColor(red: 0.698, green: 0.533, blue: 0.969, alpha: 1), // violet
                fallbackIcon: "🤖"
            )
        // Skill
        case "Skill":
            return ToolCardStyle(
                symbolName: "bolt.fill",
                color: NSColor(red: 0.949, green: 0.725, blue: 0.255, alpha: 1), // amber
                fallbackIcon: "⚡"
            )
        // Todo
        case "TodoWrite":
            return ToolCardStyle(
                symbolName: "checkmark.circle.fill",
                color: NSColor(red: 0.298, green: 0.824, blue: 0.392, alpha: 1), // green
                fallbackIcon: "✅"
            )
        // LSP
        case "LSP":
            return ToolCardStyle(
                symbolName: "text.badge.gearshape",
                color: NSColor(red: 0.545, green: 0.529, blue: 0.749, alpha: 1), // violet
                fallbackIcon: "⚙️"
            )
        default:
            return .fallback
        }
    }

    /// Style for result cards (always neutral gray).
    static let result = ToolCardStyle(
        symbolName: "checkmark.circle.fill",
        color: NSColor(red: 0.500, green: 0.500, blue: 0.520, alpha: 1), // gray
        fallbackIcon: "✓"
    )

    /// Style for error result cards.
    static let error = ToolCardStyle(
        symbolName: "exclamationmark.triangle.fill",
        color: NSColor(red: 0.969, green: 0.325, blue: 0.306, alpha: 1), // red
        fallbackIcon: "⚠"
    )

    /// Style for thinking cards.
    static let thinking = ToolCardStyle(
        symbolName: "brain.head.profile",
        color: NSColor(red: 0.500, green: 0.500, blue: 0.520, alpha: 1), // gray
        fallbackIcon: "💭"
    )

    /// Style for system reminder cards.
    static let system = ToolCardStyle(
        symbolName: "info.circle.fill",
        color: NSColor(red: 0.500, green: 0.500, blue: 0.520, alpha: 1), // gray
        fallbackIcon: "ℹ️"
    )
}

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

// MARK: - ChatCardBlockView (Base Class)

/// Base class for card-styled block views. Provides the uniform card shell:
/// rounded background + header (icon badge + title + timestamp) + body area.
///
/// Subclasses override `configureCardBody()` and `bodyHeight()` to add
/// block-specific content below the header.
public class ChatCardBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .text

    // MARK: - Subviews

    /// Card background layer view (rounded rect).
    /// Uses flipped coordinate system to match parent's top-left origin,
    /// so header subviews at y=kCardVPad render at the TOP, not the bottom.
    private class CardBgView: NSView {
        override var isFlipped: Bool { true }
    }
    private let cardBg = CardBgView()

    /// Icon badge: colored circle with SF Symbol or emoji.
    private let iconBadge = NSView()
    private let iconLabel = NSTextField(labelWithString: "")

    /// Title label (colored by tool type).
    private let titleLabel = NSTextField(labelWithString: "")

    /// Timestamp label (relative time).
    private let timestampLabel = NSTextField(labelWithString: "")

    /// Clickable overlay for the entire card.
    private let clickOverlay = NSButton()

    // MARK: - State

    private var layoutWidth: CGFloat = 600
    private var cardStyle: ToolCardStyle = .fallback
    private var timestamp: String = ""
    private var _onToggle: (() -> Void)?

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupCardViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCardViews() {
        // Card background
        cardBg.wantsLayer = true
        cardBg.layer?.cornerRadius = kCardCornerRadius
        cardBg.layer?.backgroundColor = NSColor.cbBgElevated.cgColor
        cardBg.layer?.borderWidth = 0.5
        cardBg.layer?.borderColor = NSColor.cbBorderSubtle.cgColor
        addSubview(cardBg)

        // Icon badge
        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = kIconBadgeRadius
        cardBg.addSubview(iconBadge)

        iconLabel.font = cbIconFont
        iconLabel.isBezeled = false
        iconLabel.drawsBackground = false
        iconLabel.alignment = .center
        iconBadge.addSubview(iconLabel)

        // Title
        titleLabel.font = cbCardTitleFont
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        cardBg.addSubview(titleLabel)

        // Timestamp
        timestampLabel.font = cbTimestampFont
        timestampLabel.textColor = .cbTextMuted
        timestampLabel.isBezeled = false
        timestampLabel.drawsBackground = false
        timestampLabel.alignment = .right
        timestampLabel.lineBreakMode = .byClipping
        cardBg.addSubview(timestampLabel)

        // Click overlay
        clickOverlay.isBordered = false
        clickOverlay.isTransparent = true
        clickOverlay.title = ""
        clickOverlay.target = self
        clickOverlay.action = #selector(cardClicked)
        cardBg.addSubview(clickOverlay)
    }

    // MARK: - Configuration

    /// Configure the card header. Subclasses call this from their own `configure(...)`.
    func configureCard(
        blockKind: AgentMessageBlock.BlockKind,
        toolStyle: ToolCardStyle,
        title: String,
        timestamp: String,
        layoutWidth: CGFloat,
        onToggle: (() -> Void)?
    ) {
        self.blockKind = blockKind
        self.cardStyle = toolStyle
        self.timestamp = timestamp
        self.layoutWidth = layoutWidth
        self._onToggle = onToggle

        // Icon badge
        iconLabel.stringValue = toolStyle.fallbackIcon
        iconLabel.textColor = toolStyle.color
        iconBadge.layer?.backgroundColor = toolStyle.color.withAlphaComponent(0.15).cgColor

        // Try SF Symbol
        if let img = NSImage(systemSymbolName: toolStyle.symbolName, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = img
            let attrStr = NSAttributedString(attachment: attachment)
            iconLabel.attributedStringValue = attrStr
        }

        // Title
        titleLabel.stringValue = title
        titleLabel.textColor = toolStyle.color

        // Timestamp
        timestampLabel.stringValue = timestamp
        timestampLabel.isHidden = timestamp.isEmpty

        invalidateIntrinsicContentSize()
    }

    // MARK: - Subclass Hooks

    /// Override to add body content below the header. Called during layout.
    /// Return the height of the body content, or 0 if no body.
    public func layoutCardBody(in rect: CGRect) -> CGFloat {
        return 0
    }

    /// Override to return the body content height for sizing.
    public func bodyHeight(forWidth width: CGFloat) -> CGFloat {
        return 0
    }

    /// Override to update body content for streaming.
    public func updateCardBody(with block: AgentMessageBlock) -> Bool {
        return false
    }

    // MARK: - Actions

    @objc private func cardClicked() {
        _onToggle?()
    }

    // MARK: - ChatBlockView

    public func updateContent(with block: AgentMessageBlock) -> Bool {
        return updateCardBody(with: block)
    }

    // MARK: - Layout

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()

        let w = bounds.width
        let h = bounds.height

        // Card background fills the entire view
        cardBg.frame = bounds

        // --- Header Row ---
        // Icon badge: left-aligned, vertically centered in header
        iconBadge.frame = CGRect(
            x: kCardHPad,
            y: kCardVPad,
            width: kIconBadgeSize,
            height: kIconBadgeSize
        )
        iconLabel.frame = iconBadge.bounds

        // Timestamp: right-aligned
        timestampLabel.sizeToFit()
        let tsW = min(timestampLabel.bounds.width, 60)
        timestampLabel.frame = CGRect(
            x: w - kCardHPad - tsW,
            y: kCardVPad + 1,
            width: tsW,
            height: timestampLabel.bounds.height
        )

        // Title: between icon and timestamp
        let titleX = iconBadge.frame.maxX + kIconTitleGap
        let titleMaxW = timestampLabel.frame.minX - kHeaderTimestampGap - titleX
        titleLabel.sizeToFit()
        let titleW = min(titleLabel.bounds.width, max(titleMaxW, 40))
        titleLabel.frame = CGRect(
            x: titleX,
            y: kCardVPad + (kIconBadgeSize - titleLabel.bounds.height) / 2,
            width: titleW,
            height: titleLabel.bounds.height
        )

        // --- Body ---
        let headerBottom = kCardVPad + kIconBadgeSize
        let bodyY = headerBottom + kCardBodyTopSpacing
        let bodyW = w - kCardHPad * 2
        let bodyRect = CGRect(x: kCardHPad, y: bodyY, width: bodyW, height: h - bodyY - kCardVPad)
        let bodyH = layoutCardBody(in: bodyRect)

        // Click overlay covers the entire card
        clickOverlay.frame = bounds
        // NOTE: Do NOT call invalidateIntrinsicContentSize() here — it
        // triggers a recursive layout pass when the computed height differs
        // from bounds.height, causing height instability. NSTableView
        // manages row heights via heightOfRow, not intrinsicContentSize.
    }

    public override var intrinsicContentSize: CGSize {
        let headerH = kCardVPad + kIconBadgeSize
        let bodyH = bodyHeight(forWidth: layoutWidth - kCardHPad * 2)
        let totalH = headerH + (bodyH > 0 ? kCardBodyTopSpacing + bodyH : 0) + kCardVPad
        return CGSize(width: layoutWidth, height: max(totalH, kCardCollapsedMinHeight))
    }
}

// MARK: - TextBlockView

/// Renders assistant text (plain, left-aligned, selectable) or user bubble
/// (right-aligned, rounded background). No card shell — text blocks are not cards.
public final class TextBlockView: NSView, ChatBlockView {
    public private(set) var blockKind: AgentMessageBlock.BlockKind = .text
    private var role: AgentMessageRole = .assistant
    private var layoutWidth: CGFloat = 600

    private let label = NSTextField(labelWithString: "")
    private let bubbleBg = NSView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        bubbleBg.wantsLayer = true
        bubbleBg.layer?.cornerRadius = kUserBubbleRadius
        bubbleBg.layer?.backgroundColor = NSColor.cbUserBubble.cgColor
        bubbleBg.isHidden = true
        addSubview(bubbleBg)

        label.isBezeled = false
        label.drawsBackground = false
        label.isSelectable = true
        label.font = cbBodyFont
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        addSubview(label)
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
            return CGSize(width: layoutWidth, height: fit.height + kUserBubbleVPad * 2)
        case .assistant, .system:
            let fit = label.sizeThatFits(CGSize(width: layoutWidth, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: layoutWidth, height: fit.height)
        }
    }
}

// MARK: - ThinkingBlockView

/// Collapsible thinking/reasoning card with brain icon.
/// Collapsed: shows header only (icon + "Thinking..." / "Thought for Xs").
/// Expanded: shows header + thinking text content.
public final class LegacyThinkingBlockView: ChatCardBlockView {

    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private var isExpanded: Bool = false
    private var content: String = ""

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupBody()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody() {
        bodyLabel.font = NSFont.systemFont(ofSize: 12)
        bodyLabel.textColor = .cbTextTertiary
        bodyLabel.isBezeled = false
        bodyLabel.drawsBackground = false
        bodyLabel.isSelectable = true
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.preferredMaxLayoutWidth = 400
        bodyLabel.isHidden = true
        addSubview(bodyLabel)
    }

    public func configure(
        content: String,
        expanded: Bool,
        isStreaming: Bool,
        thoughtTimeString: String?,
        layoutWidth: CGFloat = 600,
        timestamp: Date = Date(),
        onToggle: @escaping () -> Void
    ) {
        self.isExpanded = expanded
        self.content = content

        let title: String
        if isStreaming {
            title = "Thinking..."
        } else if let thoughtTime = thoughtTimeString {
            title = thoughtTime
        } else {
            title = "Thinking"
        }

        configureCard(
            blockKind: .thinking,
            toolStyle: .thinking,
            title: title,
            timestamp: chatRelativeTime(from: timestamp),
            layoutWidth: layoutWidth,
            onToggle: onToggle
        )

        bodyLabel.stringValue = content
        bodyLabel.preferredMaxLayoutWidth = layoutWidth - kCardHPad * 2
        bodyLabel.isHidden = !expanded || content.isEmpty
        invalidateIntrinsicContentSize()
    }

    // MARK: - ChatCardBlockView Overrides

    public override func layoutCardBody(in rect: CGRect) -> CGFloat {
        guard isExpanded, !content.isEmpty else {
            bodyLabel.frame = .zero
            return 0
        }
        bodyLabel.isHidden = false
        let fit = bodyLabel.sizeThatFits(CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude))
        bodyLabel.frame = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: fit.height)
        return fit.height
    }

    public override func bodyHeight(forWidth width: CGFloat) -> CGFloat {
        guard isExpanded, !content.isEmpty else { return 0 }
        let fit = bodyLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return fit.height
    }

    public override func updateCardBody(with block: AgentMessageBlock) -> Bool {
        guard case .thinking(let text, _) = block else { return false }
        // Preserve isExpanded from configure() (driven by FoldState).
        // The block's stored isExpanded is always false during streaming;
        // overwriting it here would hide the body on every streaming tick.
        self.content = text
        bodyLabel.stringValue = text
        bodyLabel.isHidden = !isExpanded || text.isEmpty
        invalidateIntrinsicContentSize()
        return true
    }
}

// MARK: - ToolUseBlockView

/// Card showing a tool invocation: icon badge + tool name + status + chevron.
/// Clicking toggles the associated tool result card.
public final class ToolUseBlockView: ChatCardBlockView {

    private let statusView = NSView()
    private let chevronLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")

    private var toolUseID: String = ""
    private var isResultExpanded: Bool = true
    private var currentStatus: ToolUseStatus = .pending

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupToolBody()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolBody() {
        // Summary line below header (the command or file path)
        summaryLabel.font = cbCardBodyFont
        summaryLabel.textColor = .cbTextSecondary
        summaryLabel.isBezeled = false
        summaryLabel.drawsBackground = false
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.maximumNumberOfLines = 2
        addSubview(summaryLabel)

        // Status badge (spinner / check / error)
        statusView.wantsLayer = true
        addSubview(statusView)

        // Chevron (▸/▾)
        chevronLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        chevronLabel.textColor = .cbTextMuted
        chevronLabel.isBezeled = false
        chevronLabel.drawsBackground = false
        chevronLabel.stringValue = "▾"
        chevronLabel.sizeToFit()
        addSubview(chevronLabel)
    }

    public func configure(
        toolUse: ToolUseBlock,
        isResultExpanded: Bool = true,
        layoutWidth: CGFloat = 600,
        timestamp: Date = Date(),
        onToggle: (() -> Void)? = nil
    ) {
        self.toolUseID = toolUse.toolUseID
        self.isResultExpanded = isResultExpanded
        self.currentStatus = toolUse.status

        let style = ToolCardStyle.forTool(toolUse.toolName)
        configureCard(
            blockKind: .toolUse,
            toolStyle: style,
            title: toolUse.toolName,
            timestamp: chatRelativeTime(from: timestamp),
            layoutWidth: layoutWidth,
            onToggle: onToggle
        )

        summaryLabel.stringValue = toolUse.inputSummary
        summaryLabel.isHidden = toolUse.inputSummary.isEmpty

        chevronLabel.stringValue = isResultExpanded ? "▾" : "▸"
        chevronLabel.sizeToFit()

        updateStatusBadge(toolUse.status)
        invalidateIntrinsicContentSize()
    }

    public func updateResultExpanded(_ expanded: Bool) {
        isResultExpanded = expanded
        chevronLabel.stringValue = expanded ? "▾" : "▸"
        chevronLabel.sizeToFit()
        needsLayout = true
    }

    public func updateStatus(_ status: ToolUseStatus) {
        currentStatus = status
        updateStatusBadge(status)
        needsLayout = true
    }

    // MARK: - ChatCardBlockView Overrides

    public override func layoutCardBody(in rect: CGRect) -> CGFloat {
        guard !summaryLabel.stringValue.isEmpty else {
            summaryLabel.frame = .zero
            return 0
        }
        summaryLabel.isHidden = false
        let fit = summaryLabel.sizeThatFits(CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude))
        summaryLabel.frame = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: fit.height)

        // Position status + chevron to the right of the header row (overlaid)
        statusView.frame.origin = CGPoint(
            x: bounds.width - kCardHPad - chevronLabel.bounds.width - 8 - statusView.bounds.width,
            y: kCardVPad + (kIconBadgeSize - statusView.bounds.height) / 2
        )
        chevronLabel.frame.origin = CGPoint(
            x: bounds.width - kCardHPad - chevronLabel.bounds.width,
            y: kCardVPad + (kIconBadgeSize - chevronLabel.bounds.height) / 2
        )

        return fit.height
    }

    public override func bodyHeight(forWidth width: CGFloat) -> CGFloat {
        guard !summaryLabel.stringValue.isEmpty else { return 0 }
        let fit = summaryLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return fit.height
    }

    public override func updateCardBody(with block: AgentMessageBlock) -> Bool {
        guard case .toolUse(let toolUse) = block else { return false }
        updateStatusBadge(toolUse.status)
        needsLayout = true
        return true
    }

    // MARK: - Status Badge

    private func updateStatusBadge(_ status: ToolUseStatus) {
        statusView.subviews.forEach { $0.removeFromSuperview() }

        switch status {
        case .pending:
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.cbTextMuted.cgColor
            dot.layer?.cornerRadius = 4
            statusView.addSubview(dot)
            statusView.frame.size = CGSize(width: 8, height: 8)

        case .executing:
            let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            statusView.addSubview(spinner)
            statusView.frame.size = CGSize(width: 14, height: 14)

        case .completed:
            // Color on the card title already indicates success — no icon needed.
            statusView.frame.size = .zero

        case .error(let msg):
            // Color on the card title already indicates error — no icon needed.
            // Tooltip provides detail on hover.
            statusView.frame.size = .zero
            if !msg.isEmpty {
                self.toolTip = msg
            }
        }
    }
}

// MARK: - ToolResultBlockView

/// Card showing tool output. Visibility toggled by clicking the tool card above.
/// Collapsed: shows header only (icon + "Result" / "Error").
/// Expanded: shows header + content text.
public final class ToolResultBlockView: ChatCardBlockView {

    private let contentLabel = NSTextField(wrappingLabelWithString: "")
    private var isExpanded: Bool = true
    private var toolUseID: String = ""

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupBody()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody() {
        contentLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        contentLabel.textColor = .cbTextSecondary
        contentLabel.isBezeled = false
        contentLabel.drawsBackground = false
        contentLabel.isSelectable = true
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.preferredMaxLayoutWidth = 400
        contentLabel.isHidden = true
        addSubview(contentLabel)
    }

    public func configure(
        result: ToolResultBlock,
        expanded: Bool,
        layoutWidth: CGFloat = 400,
        timestamp: Date = Date()
    ) {
        self.toolUseID = result.toolUseID
        self.isExpanded = expanded

        let style: ToolCardStyle = result.isError ? .error : .result
        let title: String = result.isError ? "Error" : "Result"

        configureCard(
            blockKind: .toolResult,
            toolStyle: style,
            title: title,
            timestamp: chatRelativeTime(from: timestamp),
            layoutWidth: layoutWidth,
            onToggle: nil  // ToolResult cards are not directly clickable
        )

        let truncated = String(result.content.prefix(500))
        contentLabel.stringValue = truncated
        contentLabel.preferredMaxLayoutWidth = layoutWidth - kCardHPad * 2
        contentLabel.isHidden = !expanded

        // When collapsed, hide the ENTIRE card — no header, no card at all.
        isHidden = !expanded

        invalidateIntrinsicContentSize()
    }

    // MARK: - ChatCardBlockView Overrides

    public override func layoutCardBody(in rect: CGRect) -> CGFloat {
        guard isExpanded else {
            contentLabel.frame = .zero
            return 0
        }
        contentLabel.isHidden = false
        let fit = contentLabel.sizeThatFits(CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude))
        contentLabel.frame = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: fit.height)
        return fit.height
    }

    public override func bodyHeight(forWidth width: CGFloat) -> CGFloat {
        guard isExpanded else { return 0 }
        let fit = contentLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return fit.height
    }

    public override func updateCardBody(with block: AgentMessageBlock) -> Bool {
        guard case .toolResult(let result) = block else { return false }
        let truncated = String(result.content.prefix(500))
        contentLabel.stringValue = truncated
        invalidateIntrinsicContentSize()
        return true
    }
}

// MARK: - SystemReminderBlockView

/// Card-styled system reminder. Uses a muted, subtle card.
public final class SystemReminderBlockView: ChatCardBlockView {

    private let bodyLabel = NSTextField(wrappingLabelWithString: "")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupBody()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBody() {
        bodyLabel.font = cbSmallFont
        bodyLabel.textColor = .cbTextTertiary
        bodyLabel.isBezeled = false
        bodyLabel.drawsBackground = false
        bodyLabel.isSelectable = true
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.preferredMaxLayoutWidth = 400
        addSubview(bodyLabel)
    }

    public func configure(text: String, layoutWidth: CGFloat = 600, timestamp: Date = Date()) {
        configureCard(
            blockKind: .systemReminder,
            toolStyle: .system,
            title: "System",
            timestamp: chatRelativeTime(from: timestamp),
            layoutWidth: layoutWidth,
            onToggle: nil
        )

        bodyLabel.stringValue = text
        bodyLabel.preferredMaxLayoutWidth = layoutWidth - kCardHPad * 2
        invalidateIntrinsicContentSize()
    }

    // MARK: - ChatCardBlockView Overrides

    public override func layoutCardBody(in rect: CGRect) -> CGFloat {
        guard !bodyLabel.stringValue.isEmpty else {
            bodyLabel.frame = .zero
            return 0
        }
        let fit = bodyLabel.sizeThatFits(CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude))
        bodyLabel.frame = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: fit.height)
        return fit.height
    }

    public override func bodyHeight(forWidth width: CGFloat) -> CGFloat {
        guard !bodyLabel.stringValue.isEmpty else { return 0 }
        let fit = bodyLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return fit.height
    }

    public override func updateCardBody(with block: AgentMessageBlock) -> Bool {
        guard case .systemReminder(let text) = block else { return false }
        bodyLabel.stringValue = text
        invalidateIntrinsicContentSize()
        return true
    }
}
