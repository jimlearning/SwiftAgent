import Foundation
import Testing
import SwiftAgentCore
@testable import SwiftAgentCLI

/// Direct unit tests for LineEditor.navigateHistory — isolates the history
/// logic from raw-mode I/O. PTY end-to-end tests are too noisy because the
/// chat loop also drives the LLM.
@Suite struct LineEditorHistoryTests {
    @Test
    func upArrowFromEmptyBufferRecallsNewestEntry() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = ["first", "second", "third"]
        editor.historyIndex = editor.entries.count
        var buffer = TextBuffer()

        editor.navigateHistory(direction: -1, buffer: &buffer)

        #expect(buffer.content == "third", "↑ on empty should recall newest entry")
        #expect(editor.historyIndex == 2, "historyIndex should move to entries.count-1")
        // stashedBuffer is set to "" in the empty-buffer branch so that
        // pressing ↓ past the oldest entry behaves as a no-op.
        #expect(editor.stashedBuffer == "", "Empty buffer path sets stashedBuffer = ''")
    }

    @Test
    func upArrowFromNonEmptyBufferStashesCurrentInput() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = ["first", "second"]
        editor.historyIndex = editor.entries.count
        var buffer = TextBuffer(content: "draft input")

        editor.navigateHistory(direction: -1, buffer: &buffer)

        #expect(editor.stashedBuffer == "draft input", "Original input should be stashed")
        #expect(buffer.content == "second", "Buffer should now show last history entry")
    }

    @Test
    func upArrowTwiceDoesNotOverwriteStash() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = ["first", "second", "third"]
        editor.historyIndex = editor.entries.count
        var buffer = TextBuffer(content: "draft input")

        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(editor.stashedBuffer == "draft input")
        #expect(buffer.content == "third")

        // Second ↑ — must NOT overwrite stash with "third"
        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(editor.stashedBuffer == "draft input", "Stash should still be original draft")
        #expect(buffer.content == "second", "Should now show older history entry")
    }

    @Test
    func downArrowPastEndRestoresStashedInput() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = ["first", "second"]
        editor.historyIndex = editor.entries.count
        var buffer = TextBuffer(content: "draft input")

        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(buffer.content == "second")
        #expect(editor.stashedBuffer == "draft input")

        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(buffer.content == "first")
        #expect(editor.stashedBuffer == "draft input", "Stash unchanged after second ↑")

        editor.navigateHistory(direction: 1, buffer: &buffer)
        #expect(buffer.content == "second", "↓ past newest should restore second")

        editor.navigateHistory(direction: 1, buffer: &buffer)
        #expect(buffer.content == "draft input", "↓ past end should restore stash")
        #expect(editor.stashedBuffer == nil, "Stash should clear after restore")
    }

    @Test
    func upArrowBeyondOldestDoesNothing() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = ["only"]
        editor.historyIndex = editor.entries.count
        var buffer = TextBuffer(content: "x")

        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(buffer.content == "only")
        #expect(editor.historyIndex == 0)

        // Up again — should not move
        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(buffer.content == "only", "↑ past oldest should be no-op")
    }

    @Test
    func navigateWithEmptyHistoryIsNoOp() {
        let editor = LineEditor(historyDir: nil)
        editor.entries = []
        var buffer = TextBuffer(content: "x")

        editor.navigateHistory(direction: -1, buffer: &buffer)
        #expect(buffer.content == "x", "No history = no change")
    }
}
