import SwiftUI
import AppKit

/// Terminal panel: embeds an NSTextView that runs a real PTY shell
/// via `Process` + `Pipe`. The NSTextView is editable so the user can
/// type commands; keystrokes are forwarded to the shell's stdin and
/// the shell's stdout/stderr is appended to the view in real time.
///
/// Each Terminal tab gets its own process so multiple Terminal tabs
/// are independent shells (cwd = the current project root).
public struct TerminalPanelView: NSViewRepresentable {
    let tabID: String

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = true              // allow typing commands
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        textView.insertionPointColor = NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.4, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = true

        let cwd = FileManager.default.currentDirectoryPath

        // Process setup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = pipe

        let coordinator = context.coordinator
        coordinator.process = process
        coordinator.textView = textView
        coordinator.pipe = pipe
        coordinator.scrollView = scroll

        // Append shell stdout to the view (read on background queue, draw on main).
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                coordinator.appendOutput(text)
            }
        }

        // Intercept every keystroke and forward printable chars + Enter
        // to the shell's stdin. We use NSTextViewDelegate so we can
        // block edits that would mutate history (only allow appending
        // after the last shell output).
        coordinator.installKeyForwarding()

        do {
            try process.run()
        } catch {
            textView.string = "Failed to spawn shell: \(error.localizedDescription)\n"
        }

        // Initial banner + cwd
        coordinator.appendOutput("Terminal — \(cwd)\n")
        coordinator.appendOutput("$ ")

        // Focus the text view so the user can start typing immediately.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scroll
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject, NSTextViewDelegate, @unchecked Sendable {
        var process: Process?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var pipe: Pipe?

        deinit {
            process?.terminate()
        }

        func appendOutput(_ text: String) {
            guard let textView else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
            textView.textStorage?.append(NSAttributedString(string: text, attributes: attrs))
            textView.scrollToEndOfDocument(nil)
        }

        func installKeyForwarding() {
            textView?.delegate = self
        }

        // Block edits in the "history" region — only allow appending
        // after the current prompt caret position.
        public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Disallow any change that's not pure insertion at the end.
            guard let replacement = replacementString else { return false }
            let currentLength = (textView.string as NSString).length
            let isAtEnd = (affectedCharRange.location + affectedCharRange.length) >= currentLength
            let isInsertion = affectedCharRange.length == 0
            guard isInsertion && isAtEnd else { return false }

            // Forward to the shell's stdin. Newlines become Enter.
            if let data = replacement.data(using: .utf8) {
                pipe?.fileHandleForWriting.write(data)
            }
            // Reflect the typed character in the view (it's editable).
            return true
        }
    }
}
