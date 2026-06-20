import SwiftUI
import AppKit

// MARK: - ComposerTextView

/// `NSTextView` subclass for the agent composer input area.
///
/// Provides a native text editing experience with:
/// - Enter to send, Shift+Enter for newline
/// - Placeholder text when empty
/// - Delegate callbacks for slash command detection and @-mention triggers
/// - Configurable maximum height with auto-grow
///
/// Phase 2 hooks (not yet wired):
/// - `onMentionTriggered` — fired when `@` is typed
/// - `onSlashCommandChanged` — fired when `/` is typed
/// - Image paste via `NSImageView` attachment
/// - Syntax highlighting via custom `NSTextStorage` subclass
public final class ComposerTextView: NSTextView {

    // MARK: - Callbacks

    /// Called when the user presses Enter (without Shift) — the view should send the text.
    public var onSend: (() -> Void)?

    /// Called when the text content changes.
    public var onTextChanged: ((String) -> Void)?

    /// Called when `@` is typed — passes the query text after `@` and the screen rect for positioning.
    /// Set this to show the mention autocomplete popup.
    public var onMentionQueryChanged: ((_ query: String, _ anchorRect: NSRect) -> Void)?

    /// Called when the mention context ends (space typed, @ deleted, popup dismissed).
    public var onMentionDismiss: (() -> Void)?

    /// The placeholder string shown when the text is empty.
    public var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    // MARK: - Mention State

    /// The insertion position where the `@` was typed.
    private var mentionStartIndex: Int?

    /// Whether the mention popup is currently visible.
    private var isMentionActive: Bool = false

    // MARK: - Sizing

    /// Maximum height before scrolling kicks in.
    public var maxHeight: CGFloat = 120 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Minimum height (one line).
    public var minHeight: CGFloat = 28 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// The line height used for height calculation.
    private var lineHeight: CGFloat {
        font?.boundingRectForFont.height ?? 16
    }

    // MARK: - Init

    override public init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        delegate = self
        isRichText = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false

        // Styling
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textColor = .labelColor
        backgroundColor = .clear
        drawsBackground = false

        // Text container
        textContainerInset = NSSize(width: 4, height: 6)
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0

        // No scroll bar — size grows with content
        isVerticallyResizable = true
        isHorizontallyResizable = false
    }

    // MARK: - Intrinsic Content Size

    override public var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
        }

        manager.ensureLayout(for: container)
        let usedHeight = manager.usedRect(for: container).height + textContainerInset.height * 2
        let clampedHeight = min(max(usedHeight, minHeight), maxHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: clampedHeight)
    }

    override public func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        onTextChanged?(string)
        detectMention()
    }

    // MARK: - Mention Detection

    /// Scan backward from the cursor for an `@` trigger.
    private func detectMention() {
        let text = string as NSString
        let cursor = selectedRange().location

        // Walk backward from cursor looking for @
        var i = min(cursor, text.length)
        var foundAt = false
        var atIndex = 0

        while i > 0 {
            i -= 1
            let char = Character(UnicodeScalar(text.character(at: i))!)
            if char == "@" {
                foundAt = true
                atIndex = i
                break
            }
            if char == " " || char == "\n" || char == "\t" {
                break
            }
        }

        if foundAt {
            let queryStart = atIndex + 1
            let queryLength = cursor - queryStart
            let query = queryLength > 0 ? text.substring(with: NSRange(location: queryStart, length: queryLength)) : ""

            // Only trigger if there's no space between @ and cursor
            if cursor >= queryStart {
                mentionStartIndex = atIndex
                isMentionActive = true

                // Calculate anchor rect at the @ position
                if let anchorRect = rectForCharacterIndex(atIndex) {
                    onMentionQueryChanged?(query, anchorRect)
                }
            }
        } else if isMentionActive {
            dismissMention()
        }
    }

    /// Calculate the screen rect for a character position (for popup positioning).
    private func rectForCharacterIndex(_ index: Int) -> NSRect? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = window else { return nil }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect = convert(rect, to: nil)
        rect = window.convertToScreen(rect)
        return rect
    }

    /// Insert the selected mention text, replacing the `@query` text.
    public func insertMention(_ mentionText: String) {
        guard let startIndex = mentionStartIndex else { return }

        let cursor = selectedRange().location
        let replaceRange = NSRange(location: startIndex, length: cursor - startIndex)

        if shouldChangeText(in: replaceRange, replacementString: mentionText) {
            textStorage?.replaceCharacters(in: replaceRange, with: mentionText)
            didChangeText()
        }

        dismissMention()
    }

    /// Dismiss the mention popup and reset state.
    public func dismissMention() {
        guard isMentionActive else { return }
        isMentionActive = false
        mentionStartIndex = nil
        onMentionDismiss?()
    }

    /// Whether a mention autocomplete is currently active.
    public var isShowingMention: Bool {
        isMentionActive
    }

    // MARK: - Drawing

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder text
        if string.isEmpty, !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let placeholderRect = NSRect(
                x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: textContainerInset.height,
                width: bounds.width - textContainerInset.width * 2,
                height: bounds.height - textContainerInset.height * 2
            )
            (placeholderString as NSString).draw(
                in: placeholderRect,
                withAttributes: attrs
            )
        }
    }

    // MARK: - Public

    /// Clear the text and reset height.
    public func clear() {
        string = ""
        didChangeText()
    }

    /// The current text content.
    public var text: String {
        get { string }
        set {
            string = newValue
            didChangeText()
        }
    }
}

// MARK: - NSTextViewDelegate

extension ComposerTextView: NSTextViewDelegate {

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Enter → send or mention select
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // If mention is active, Enter selects the current mention item
            if isMentionActive {
                // The MentionCompletionWindow handles Enter via keyDown forwarding
                return false
            }
            // Check for Shift modifier
            if let event = NSApp.currentEvent,
               event.type == .keyDown,
               event.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            onSend?()
            return true
        }
        return false
    }

    public func textDidChange(_ notification: Notification) {
        invalidateIntrinsicContentSize()
    }

    // MARK: - Keyboard Event Forwarding

    /// When the mention popup is visible, forward navigation keys to it.
    /// Called from the parent's key event handling.
    @discardableResult
    public func forwardKeyEventToMention(_ event: NSEvent) -> Bool {
        // This is handled by the mention popup window directly since it's a child window.
        // Return false to let the event continue to the text view.
        return false
    }
}

// MARK: - NSViewRepresentable Wrapper

/// SwiftUI wrapper for `ComposerTextView`.
public struct ComposerTextViewWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: Bool
    var onSend: () -> Void
    var onTextChanged: ((String) -> Void)?

    /// @-mention items for autocomplete. When non-nil and non-empty, the mention
    /// popup will appear when `@` is typed.
    var mentionItems: [MentionItem] = []

    public init(
        text: Binding<String>,
        placeholder: String = "",
        isFocused: Bool = false,
        onSend: @escaping () -> Void,
        onTextChanged: ((String) -> Void)? = nil,
        mentionItems: [MentionItem] = []
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.onSend = onSend
        self.onTextChanged = onTextChanged
        self.mentionItems = mentionItems
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ComposerTextView()
        textView.placeholderString = placeholder
        textView.string = text
        textView.onSend = { [weak textView] in
            if let tv = textView {
                context.coordinator.parent.text = tv.string
            }
            onSend()
        }
        textView.onTextChanged = { newText in
            context.coordinator.parent.text = newText
            onTextChanged?(newText)
        }
        textView.onMentionQueryChanged = { query, anchorRect in
            context.coordinator.showMentionPopup(query: query, anchorRect: anchorRect, textView: textView)
        }
        textView.onMentionDismiss = {
            context.coordinator.dismissMentionPopup()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }

        // Update text if changed externally
        if textView.string != text {
            textView.string = text
        }

        // Update mention items
        context.coordinator.mentionItems = mentionItems

        // Focus management: only use FocusState for programmatic focus
        // (auto-focus after agent response). Never steal focus when the
        // user has clicked into the text view — SwiftUI's @FocusState
        // doesn't track AppKit first-responder changes on NSViewRepresentable.
        if isFocused, let window = scrollView.window, window.firstResponder != textView {
            window.makeFirstResponder(textView)
        }
    }

    public class Coordinator: @unchecked Sendable {
        let parent: ComposerTextViewWrapper
        weak var textView: ComposerTextView?
        var mentionItems: [MentionItem] = []
        private var mentionWindow: MentionCompletionWindow?

        init(_ parent: ComposerTextViewWrapper) {
            self.parent = parent
        }

        func showMentionPopup(query: String, anchorRect: NSRect, textView: ComposerTextView) {
            guard !mentionItems.isEmpty else { return }

            if mentionWindow == nil {
                mentionWindow = MentionCompletionWindow(
                    onSelect: { [weak self, weak textView] item in
                        textView?.insertMention(item.mentionText + " ")
                        self?.mentionWindow = nil
                    },
                    onDismiss: { [weak self] in
                        self?.mentionWindow = nil
                    }
                )
            }

            mentionWindow?.show(
                items: mentionItems,
                query: query,
                anchorRect: anchorRect,
                parentWindow: textView.window
            )
        }

        func dismissMentionPopup() {
            mentionWindow?.dismiss()
            mentionWindow = nil
        }
    }
}
