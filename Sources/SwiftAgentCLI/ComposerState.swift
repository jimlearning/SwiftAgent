import Foundation

// MARK: - ComposerState

/// Manages the inline popup completion engine state independently of line editing.
/// The "Composer" is Claude Code's term for the input subsystem that combines
/// text editing with slash-command and @-mention popups.
///
/// ComposerState owns: EditorMode (normal vs popup), the PopupState, the InlinePopup
/// engine, and all popup data sources. The LineEditor delegates popup decisions
/// to ComposerState but retains ownership of the text buffer.
public struct ComposerState {
    // MARK: - Editor mode

    /// Distinguishes normal line editing from the inline popup overlay.
    public enum EditorMode {
        case normal
        case popup(PopupState)

        public var isPopup: Bool {
            if case .popup = self { return true }
            return false
        }
    }

    /// Mutable state for the inline popup while it is active.
    public struct PopupState {
        /// The trigger character that opened the popup (`@` or `/`).
        public var trigger: Character
        /// Position of the trigger character in the input buffer.
        public var triggerPos: Int
        /// The popup interaction engine.
        public var popup: InlinePopup
        /// Whether this is a sub-menu popup (opened after a command was committed).
        public var isSubMenu: Bool = false

        public init(trigger: Character, triggerPos: Int, popup: InlinePopup, isSubMenu: Bool = false) {
            self.trigger = trigger
            self.triggerPos = triggerPos
            self.popup = popup
            self.isSubMenu = isSubMenu
        }
    }

    // MARK: - State

    /// Current editing mode — normal or popup overlay.
    public var mode: EditorMode = .normal

    /// Data sources for popup completions.
    private var slashDataSource: PopupDataSource?
    private var atDataSource: PopupDataSource?

    // MARK: - Init

    public init(slashDataSource: PopupDataSource? = nil, atDataSource: PopupDataSource? = nil) {
        self.slashDataSource = slashDataSource
        self.atDataSource = atDataSource
    }

    // MARK: - Configuration

    public mutating func setDataSources(slash: PopupDataSource?, at: PopupDataSource?) {
        self.slashDataSource = slash
        self.atDataSource = at
    }

    // MARK: - Queries

    /// Whether typing `char` at `buffer` position `cursorPos` should trigger the popup.
    public func shouldTriggerPopup(char: Character, buffer: TextBuffer) -> Bool {
        guard char == "@" || char == "/" else { return false }
        guard slashDataSource != nil || atDataSource != nil else { return false }
        // Word boundary: start of line, or preceded by space / newline
        if buffer.cursor == 0 { return true }
        let prevIdx = buffer.content.index(buffer.content.startIndex, offsetBy: buffer.cursor - 1)
        let prev = buffer.content[prevIdx]
        return prev == " " || prev == "\n"
    }

    /// The currently selected item in the active popup, or nil.
    public var selectedItem: PopupItem? {
        guard case .popup(let state) = mode,
              state.popup.selectedIndex < state.popup.items.count else { return nil }
        return state.popup.items[state.popup.selectedIndex]
    }

    // MARK: - Popup lifecycle

    /// Open the popup for the given trigger character and trigger position in buffer.
    /// Returns the updated buffer (with trigger char inserted) and ComposerState.
    public mutating func openPopup(trigger: Character, triggerPos: Int, buffer: inout TextBuffer) {
        let ds: PopupDataSource?
        switch trigger {
        case "/": ds = slashDataSource
        case "@": ds = atDataSource
        default:  ds = nil
        }
        guard let dataSource = ds else { return }

        var popup = InlinePopup(dataSource: dataSource)
        popup.refresh()
        mode = .popup(PopupState(trigger: trigger, triggerPos: triggerPos, popup: popup))
    }

    /// Handle a character typed while the popup is active.
    /// Returns the new ghost text (or nil) to be set on the buffer.
    public mutating func handlePopupChar(char: Character, buffer: inout TextBuffer) {
        guard case .popup(var state) = mode else { return }

        if char == " " {
            if let item = selectedItem {
                commitPopupSelection(item: item, state: state, buffer: &buffer)
            } else {
                cancelPopup(buffer: &buffer)
                buffer.insert(" ")
            }
            return
        }

        buffer.insert(char)
        state.popup.appendQuery(char)

        if state.popup.items.isEmpty {
            dismissPopupKeepBuffer()
        } else {
            mode = .popup(state)
        }
    }

    /// Handle Enter in popup mode: commit selection.
    /// Returns true if the line should be auto-submitted (submitOnSelect).
    public mutating func handlePopupEnter(buffer: inout TextBuffer) -> Bool {
        guard case .popup(let state) = mode, let item = selectedItem else { return false }
        commitPopupSelection(item: item, state: state, buffer: &buffer)
        return item.submitOnSelect
    }

    /// Handle Tab in popup mode: commit selection (same as Enter but doesn't auto-submit).
    public mutating func handlePopupTab(buffer: inout TextBuffer) {
        guard case .popup(let state) = mode, let item = selectedItem else { return }
        commitPopupSelection(item: item, state: state, buffer: &buffer)
    }

    /// Handle Backspace in popup mode.
    /// Returns true if the popup was dismissed (query exhausted).
    public mutating func handlePopupBackspace(buffer: inout TextBuffer) -> Bool {
        guard case .popup(var state) = mode else { return false }

        // Remove last char from buffer (sync with popup query)
        if buffer.cursor > state.triggerPos {
            buffer.deleteBackward()
        }

        let queryExhausted = state.popup.deleteQueryChar()
        if queryExhausted || buffer.cursor <= state.triggerPos {
            cancelPopup(buffer: &buffer)
            return true
        } else if state.popup.items.isEmpty {
            dismissPopupKeepBuffer()
            return true
        } else {
            mode = .popup(state)
            return false
        }
    }

    /// Move selection up in popup.
    public mutating func handlePopupMoveUp() {
        guard case .popup(var state) = mode else { return }
        state.popup.moveUp()
        mode = .popup(state)
    }

    /// Move selection down in popup.
    public mutating func handlePopupMoveDown() {
        guard case .popup(var state) = mode else { return }
        state.popup.moveDown()
        mode = .popup(state)
    }

    // MARK: - Commit / Cancel

    /// Replace trigger..cursor range in buffer with the selected item's insertText + space.
    private mutating func commitPopupSelection(item: PopupItem, state: PopupState, buffer: inout TextBuffer) {
        let replacement = item.insertText + " "
        buffer.replace(subrangeFrom: state.triggerPos, to: buffer.cursor, with: replacement)
        mode = .normal
        buffer.ghostText = item.argumentHint
    }

    /// Cancel popup: remove trigger + query from buffer.
    public mutating func cancelPopup(buffer: inout TextBuffer) {
        guard case .popup(let state) = mode else { return }
        if state.isSubMenu { mode = .normal; buffer.ghostText = nil; return }
        buffer.replace(subrangeFrom: state.triggerPos, to: buffer.cursor, with: "")
        mode = .normal
        buffer.ghostText = nil
    }

    /// Dismiss popup while keeping buffer content intact (no matches).
    public mutating func dismissPopupKeepBuffer() {
        mode = .normal
    }

    /// Close popup (used by Ctrl+C in popup mode).
    public mutating func closePopup() {
        mode = .normal
    }

    // MARK: - Popup rendering

    /// Render the popup (if active) to stdout via callback.
    /// Returns the popup height (0 if no popup).
    public func renderPopup(to write: (String) -> Void, terminalWidth: Int) -> Int {
        guard case .popup(let state) = mode else { return 0 }
        state.popup.render(to: write, terminalWidth: terminalWidth)
        return state.popup.height
    }
}
