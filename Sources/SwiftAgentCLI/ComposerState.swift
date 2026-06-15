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
    /// Returns the commit outcome for the " " (space) case so callers can
    /// decide whether to flush the line. For non-space characters, returns
    /// `.resolved` (the popup either continues with new query or is dismissed
    /// in-place — neither requires line flushing).
    @discardableResult
    public mutating func handlePopupChar(char: Character, buffer: inout TextBuffer) -> CommitOutcome {
        guard case .popup(var state) = mode else { return .resolved }

        if char == " " {
            if let item = selectedItem {
                let outcome = commitPopupSelection(item: item, state: state, buffer: &buffer)
                if item.submitOnSelect, case .subMenuOpened = outcome {
                    mode = .normal
                    return .resolved
                }
                return outcome
            } else {
                closePopup()
                buffer.insert(" ")
                return .subMenuOpened
            }
        }

        buffer.insert(char)
        state.popup.appendQuery(char)
        mode = .popup(state)
        return .resolved
    }

    /// Handle Enter in popup mode: commit selection.
    /// Returns the commit outcome. If `.subMenuOpened`, the caller should
    /// keep editing. If `.resolved`, the caller should flush the line.
    /// The `submitOnSelect` flag on the item still drives auto-submit
    /// behavior — we encode that by also returning a submit hint.
    @discardableResult
    public mutating func handlePopupEnter(buffer: inout TextBuffer) -> CommitOutcome {
        guard case .popup(let state) = mode, let item = selectedItem else { return .resolved }
        let outcome = commitPopupSelection(item: item, state: state, buffer: &buffer)
        // submitOnSelect forces immediate submit even if a sub-menu was opened.
        if item.submitOnSelect, case .subMenuOpened = outcome {
            mode = .normal
            return .resolved
        }
        return outcome
    }

    /// Handle Tab in popup mode: commit selection. Tab never auto-submits.
    @discardableResult
    public mutating func handlePopupTab(buffer: inout TextBuffer) -> CommitOutcome {
        guard case .popup(let state) = mode, let item = selectedItem else { return .resolved }
        return commitPopupSelection(item: item, state: state, buffer: &buffer)
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

    /// Result of committing a popup selection: did we open a sub-menu
    /// (continue editing) or fully resolve the popup (caller should flush
    /// the line back to the user)?
    public enum CommitOutcome {
        /// A sub-menu is now active. Caller should NOT flush the line —
        /// the user is still composing.
        case subMenuOpened
        /// Popup is closed. Caller should flush the buffer as a completed
        /// line back to the caller of readLine.
        case resolved
    }

    /// Replace trigger..cursor range in buffer with the selected item's insertText + space.
    /// If the item carries sub-options or a sub-data-source, open a follow-up
    /// sub-menu (e.g. /model → list of model names) instead of closing the popup.
    @discardableResult
    private mutating func commitPopupSelection(item: PopupItem, state: PopupState, buffer: inout TextBuffer) -> CommitOutcome {
        let replacement = item.insertText + " "
        buffer.replace(subrangeFrom: state.triggerPos, to: buffer.cursor, with: replacement)

        // 1. Sub-options: wrap in an ArgumentDataSource and open as a sub-menu.
        if let subOptions = item.subOptions, !subOptions.isEmpty {
            let subDS = ArgumentDataSource(choices: subOptions)
            var subPopup = InlinePopup(dataSource: subDS)
            subPopup.refresh()
            let subState = PopupState(
                trigger: state.trigger,
                triggerPos: buffer.cursor,
                popup: subPopup,
                isSubMenu: true
            )
            mode = .popup(subState)
            buffer.ghostText = nil
            return .subMenuOpened
        }

        // 2. Sub-data-source (e.g. /resume → session list).
        if let subDS = item.subDataSource {
            var subPopup = InlinePopup(dataSource: subDS)
            subPopup.refresh()
            let subState = PopupState(
                trigger: state.trigger,
                triggerPos: buffer.cursor,
                popup: subPopup,
                isSubMenu: true
            )
            mode = .popup(subState)
            buffer.ghostText = nil
            return .subMenuOpened
        }

        // 3. Plain commit: show argument hint as ghost text. The popup is
        //    fully resolved — caller should flush the line.
        mode = .normal
        buffer.ghostText = item.argumentHint
        return .resolved
    }

    /// Helper: commit a popup selection and return the outcome.
    /// Used by callers (Enter, Tab, Space) that need to know whether to
    /// continue editing (sub-menu) or flush the line.
    @discardableResult
    public mutating func commitSelection(buffer: inout TextBuffer) -> CommitOutcome {
        guard case .popup(let state) = mode, let item = selectedItem else {
            return .resolved
        }
        return commitPopupSelection(item: item, state: state, buffer: &buffer)
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
