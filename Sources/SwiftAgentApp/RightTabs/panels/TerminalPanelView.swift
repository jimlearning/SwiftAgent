import SwiftUI
import ClarcCore

/// Terminal panel using SwiftTerm for a full terminal emulator experience.
/// Each Terminal tab gets its own independent shell process (zsh).
public struct TerminalPanelView: View {
    let tabID: String
    @State private var process = TerminalProcess()

    public init(tabID: String) {
        self.tabID = tabID
    }

    public var body: some View {
        EmbeddedTerminalView(
            executable: "/bin/zsh",
            arguments: ["-i"],
            currentDirectory: NSHomeDirectory(),
            process: process
        )
        .padding(8)
        .background(ClaudeTheme.codeBackground)
    }
}
