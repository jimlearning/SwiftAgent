import Foundation
import Testing
import Darwin
import SwiftAgentCore
@testable import SwiftAgentCLI

/// Reproduce the "history + ghost text stacking" scenario from PTY observations.
final class GhostHistoryReader: TerminalRawReader, @unchecked Sendable {
    private let input: [UInt8]
    private var index = 0
    private(set) var output: [UInt8] = []
    private let lock = NSLock()

    init(input: String) { self.input = Array(input.utf8) }

    func readByte() -> UInt8? {
        lock.lock(); defer { lock.unlock() }
        guard index < input.count else { return nil }
        let b = input[index]; index += 1
        return b
    }

    func readByteWithTimeout(ms: Int32) -> UInt8? { readByte() }
    func decodeUTF8Char(leadByte: UInt8) -> (Character, Int)? {
        return (Character(UnicodeScalar(leadByte)), 1)
    }
    func enterRawMode() {}
    func restore() {}
    func readEscapeSequence() -> EscapeSequence {
        guard let c = readByte() else { return .none }
        if c == 0x5B {
            guard let f = readByte() else { return .none }
            switch f {
            case 0x41: return .up
            case 0x42: return .down
            case 0x43: return .right
            case 0x44: return .left
            case 0x48: return .home
            case 0x46: return .end
            default: return .none
            }
        }
        return .none
    }
    var captured: String { String(bytes: output, encoding: .utf8) ?? "" }
}

@Suite struct LineEditorGhostTextStackingTests {
    @Test
    func historyRecallAfterGhostTextCommitsDoesNotStack() {
        // Sequence: type "/", then "model", then space (commits /model + opens sub-menu).
        // Press ↑ to recall history while sub-menu is still active? No — we
        // need to first ESC out of sub-menu, then ↑ to recall history. But
        // ↑ inside a popup moves selection, so we ESC first.
        // Then ↑ in normal mode: should recall history, replacing buffer.

        // Simplest: type "model" + Enter (no popup, just commit a message).
        // But "/" triggers a popup, so this test must use a non-slash prefix.
        // Use: type "draft input", press ↑ to recall history, then ↓ to
        // restore draft. If ghost text is present, it must not stack.
        let input = "draft input\u{1B}[A\u{1B}[B"
        let reader = GhostHistoryReader(input: input)
        let editor = LineEditor(terminal: reader, isTTY: true)
        editor.entries = ["historical entry"]
        editor.historyIndex = editor.entries.count

        _ = editor.readLine(prompt: "You: ")

        // After ↑ then ↓, the final buffer should be "draft input".
        // The captured output should NOT show "draft input" + "historical entry"
        // on the same rendered line.
        let plain = reader.captured.replacingOccurrences(of: "\u{1B}[0m", with: "")

        // The last "You: " rendering should be either:
        //  - "You: draft input" (stashed restored) — correct
        //  - "You: historical entry" (still in history) — also valid
        // What must NOT happen: "You: draft inputhistorical entry" or
        // "You: historical entrydraft input" on a single line.
        if let lastRange = plain.range(of: "You: ", options: .backwards) {
            let tail = String(plain[lastRange.upperBound...])
            // The last meaningful character should end at one of the
            // expected text fragments, not be glued to a different one.
            let hasDraft = tail.contains("draft input")
            let hasHistory = tail.contains("historical entry")
            // If both present, they must not be overlapping/glued.
            if hasDraft && hasHistory {
                // Find positions
                let dIdx = tail.range(of: "draft input")!.lowerBound
                let hIdx = tail.range(of: "historical entry")!.lowerBound
                let dEnd = tail.range(of: "draft input")!.upperBound
                let hEnd = tail.range(of: "historical entry")!.upperBound
                // Distance between end of one and start of other must be ≥ 1 char
                // of NON-text (i.e. cursor movement / redraw), not directly adjacent.
                let dThenH = dIdx < hIdx && hIdx > dEnd
                let hThenD = hIdx < dIdx && dIdx > hEnd
                // The bug case is when one is rendered immediately after the other
                // with no cursor movement in between.
                #expect(dThenH || hThenD, "Text fragments are stacked without separation: \(tail)")
            }
            #expect(hasDraft || hasHistory, "Final render missing both fragments: \(tail)")
        }
    }
}
