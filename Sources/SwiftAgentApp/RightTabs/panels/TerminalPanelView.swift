import SwiftUI
import ClarcCore

/// Terminal panel using SwiftTerm for a full terminal emulator experience.
/// Each Terminal tab gets its own independent shell process (zsh).
public struct TerminalPanelView: View {
    let tabID: String
    let projectPath: String?
    @State private var process = TerminalProcess()

    public init(tabID: String, projectPath: String? = nil) {
        self.tabID = tabID
        self.projectPath = projectPath
    }

    public var body: some View {
        EmbeddedTerminalView(
            executable: "/bin/zsh",
            arguments: ["-i"],
            currentDirectory: projectPath ?? NSHomeDirectory(),
            process: process
        )
        .padding(8)
        .background(ClaudeTheme.codeBackground)
    }
}
