import Foundation
import Testing
import SwiftAgentCore
@testable import SwiftAgentCLI

/// Strip ANSI escape sequences (CSI + color) for substring assertions.
private func stripANSI(_ s: String) -> String {
    var result = ""
    var iter = s.unicodeScalars.makeIterator()
    while let scalar = iter.next() {
        if scalar.value == 0x1B {
            // ESC
            if let next = iter.next() {
                if next.value == 0x5B { // '['
                    // Skip parameter + intermediate + final byte (0x40-0x7E)
                    while let n = iter.next() {
                        if n.value >= 0x40 && n.value <= 0x7E { break }
                    }
                }
            }
            continue
        }
        result.unicodeScalars.append(scalar)
    }
    return result
}

/// End-to-end test: simulate typing `/` and verify the popup is rendered.
struct ComposerSlashPopupIntegrationTests {
    @Test
    func typingSlashOpensPopupAndRendersItems() {
        // Build a minimal slash command data source — exactly the same kind
        // ChatCommand would build at startup.
        let commands: [(name: String, help: String?)] = [
            ("/help", "Show available commands"),
            ("/clear", "Clear the conversation"),
            ("/exit", "Exit the chat"),
            ("/resume", "Resume a previous session"),
            ("/model", "Switch the active model"),
        ]
        let dataSource = CommandDataSource(commands: commands)

        // Create a ComposerState, attach the slash data source, then trigger
        // the popup exactly as LineEditor would on a `/` keystroke.
        var composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("/")
        composer.openPopup(trigger: "/", triggerPos: 0, buffer: &buffer)

        // The popup should now be active.
        #expect(composer.mode.isPopup, "Popup should be active after typing `/`")

        // Render the popup to a string and verify the items show up.
        var rendered = ""
        let height = composer.renderPopup(to: { rendered += $0 }, terminalWidth: 80)

        #expect(height > 0, "Popup height should be > 0 when active")
        let plain = stripANSI(rendered)
        #expect(plain.contains("╭"), "Popup should contain the top border")
        #expect(plain.contains("╯"), "Popup should contain the bottom border")
        #expect(plain.contains("/help"), "Popup should list /help")
        #expect(plain.contains("/clear"), "Popup should list /clear")
        #expect(plain.contains("/exit"), "Popup should list /exit")
    }

    @Test
    func typingSlashFiltersPopupByQuery() {
        let commands: [(name: String, help: String?)] = [
            ("/help", "Show available commands"),
            ("/clear", "Clear the conversation"),
            ("/exit", "Exit the chat"),
        ]
        let dataSource = CommandDataSource(commands: commands)

        var composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("/")
        composer.openPopup(trigger: "/", triggerPos: 0, buffer: &buffer)
        #expect(composer.mode.isPopup)

        // Type "cl" — the popup should filter to /clear.
        composer.handlePopupChar(char: "c", buffer: &buffer)
        composer.handlePopupChar(char: "l", buffer: &buffer)

        var rendered = ""
        let _ = composer.renderPopup(to: { rendered += $0 }, terminalWidth: 80)
        let plain = stripANSI(rendered)

        #expect(plain.contains("/clear"), "Popup should show /clear after typing 'cl'")
        #expect(!plain.contains("/exit"), "Popup should not show /exit (no fuzzy match for 'cl')")
    }

    @Test
    func atPopupTriggerOpensOnAtSymbol() {
        let dataSource = FileDataSource(workingDirectory: "/tmp", maxResults: 5)
        var composer = ComposerState(atDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("@")
        composer.openPopup(trigger: "@", triggerPos: 0, buffer: &buffer)

        #expect(composer.mode.isPopup, "Popup should be active after typing `@`")
    }

    @Test
    func typingSlashInMiddleOfWordDoesNotOpenPopup() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        let composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("foo")
        // Cursor is at end, prev char is "o" — should NOT trigger.
        let shouldOpen = composer.shouldTriggerPopup(char: "/", buffer: buffer)
        #expect(shouldOpen == false, "Should not open popup mid-word")
    }

    @Test
    func typingSlashAtStartOfLineOpensPopup() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        let composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        let shouldOpen = composer.shouldTriggerPopup(char: "/", buffer: buffer)
        #expect(shouldOpen == true, "Should open popup at start of empty buffer")
    }

    @Test
    func typingSlashAfterSpaceOpensPopup() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        let composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("hello ")
        let shouldOpen = composer.shouldTriggerPopup(char: "/", buffer: buffer)
        #expect(shouldOpen == true, "Should open popup after a space")
    }

    @Test
    func popupDismissesWhenFirstCharHasNoMatches() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        var composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("/")
        composer.openPopup(trigger: "/", triggerPos: 0, buffer: &buffer)

        // Type "x" — /help won't match. Popup should auto-dismiss and
        // keep the typed character in the buffer.
        composer.handlePopupChar(char: "x", buffer: &buffer)
        #expect(!composer.mode.isPopup, "Popup should dismiss when no items match")
        #expect(buffer.content == "/x", "Typed char should be kept in buffer")

        // Once dismissed, subsequent handlePopupChar calls are no-ops
        // (LineEditor's default branch handles further typing).
        composer.handlePopupChar(char: "y", buffer: &buffer)
        #expect(buffer.content == "/x", "Subsequent chars do not pass through handlePopupChar after dismiss")
    }

    @Test
    func backspaceInPopupExitsWhenQueryEmpty() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        var composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("/")
        composer.openPopup(trigger: "/", triggerPos: 0, buffer: &buffer)
        #expect(composer.mode.isPopup)

        // Backspace should remove the trigger and exit the popup.
        let exited = composer.handlePopupBackspace(buffer: &buffer)
        #expect(exited, "Backspace at trigger should exit popup")
        #expect(!composer.mode.isPopup, "Popup should be dismissed")
        #expect(buffer.content == "", "Trigger char should be removed from buffer")
    }

    @Test
    func selectingItemCommitsTextToBuffer() {
        let dataSource = CommandDataSource(commands: [("/help", nil)])
        var composer = ComposerState(slashDataSource: dataSource)
        var buffer = TextBuffer()
        buffer.insert("/")
        composer.openPopup(trigger: "/", triggerPos: 0, buffer: &buffer)

        // Press Enter to commit the first (and only) item.
        let shouldSubmit = composer.handlePopupEnter(buffer: &buffer)
        #expect(shouldSubmit == false, "/help should not auto-submit")
        #expect(!composer.mode.isPopup, "Popup should be closed after commit")
        #expect(buffer.content == "/help ", "Buffer should contain committed command with trailing space")
    }
}
