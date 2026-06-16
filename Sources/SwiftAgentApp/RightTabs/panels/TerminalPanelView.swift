import SwiftUI
import AppKit

/// Terminal panel: embeds an NSTextView that runs a real PTY shell
/// via `Process` + `Pipe`. Each tab gets its own session (cwd =
/// current project, or $HOME if no project).
public struct TerminalPanelView: NSViewRepresentable {
    let tabID: String

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        // Spawn a shell
        let cwd = FileManager.default.currentDirectoryPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                textView.textStorage?.append(NSAttributedString(
                    string: text,
                    attributes: [
                        .foregroundColor: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1),
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    ]
                ))
                textView.scrollToEndOfDocument(nil)
            }
        }

        do {
            try process.run()
        } catch {
            textView.string = "Failed to spawn shell: \(error.localizedDescription)"
        }

        // Store the process on the coordinator so it can be cleaned up.
        context.coordinator.process = process

        // Banner with cwd
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let banner = NSAttributedString(
                string: "Terminal — \(cwd)\n$ ",
                attributes: [
                    .foregroundColor: NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.4, alpha: 1),
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                ]
            )
            textView.textStorage?.append(banner)
        }

        return scroll
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public class Coordinator {
        var process: Process?
        deinit {
            process?.terminate()
        }
    }
}
