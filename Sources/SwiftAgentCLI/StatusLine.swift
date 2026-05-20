import Foundation
import SwiftAgentCore

/// Renders the bottom status line during streaming and idle states.
public struct StatusLine {
    public let renderer: TerminalRenderer
    public let store: AppStateStore

    public init(renderer: TerminalRenderer, store: AppStateStore) {
        self.renderer = renderer
        self.store = store
    }

    /// Update and redraw the status line from the latest snapshot.
    public func update() async {
        let snapshot = await store.actor.getSnapshot()
        let line = renderer.renderStatusLine(snapshot)

        // Save cursor, move to bottom, write status, restore
        let output = renderer.saveCursor() +
            renderer.cursorDown(renderer.capability.rows) +
            line +
            "\r" +
            renderer.restoreCursor()

        fputs(output, stdout)
        fflush(stdout)
    }

    /// Clear the status line area.
    public func clear() {
        let blank = String(repeating: " ", count: renderer.capability.columns)
        let output = renderer.saveCursor() +
            renderer.cursorDown(renderer.capability.rows) +
            blank +
            "\r" +
            renderer.restoreCursor()

        fputs(output, stdout)
        fflush(stdout)
    }
}
