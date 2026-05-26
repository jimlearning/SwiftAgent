import Foundation

/// Readline wrapper with persistent history, mirroring nanobot's `_enable_line_editing`.
/// On macOS, `readLine()` uses libedit which provides basic line editing (arrows, backspace).
/// We layer history persistence on top via a flat file.
public final class LineEditor: @unchecked Sendable {
    private let historyFile: URL
    private var entries: [String] = []
    private var historyIndex: Int = 0

    public init(historyDir: URL? = nil) {
        let dir = historyDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent/history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.historyFile = dir.appendingPathComponent("cli_history")
        load()
    }

    /// Read a line with the given prompt. Returns nil on EOF.
    public func readLine(prompt: String) -> String? {
        // Print the prompt in blue (like nanobot's "\033[1;34mYou:\033[0m ")
        let styledPrompt = isTTY ? "\u{001B}[1;34m\(prompt)\u{001B}[0m" : prompt
        print(styledPrompt, terminator: "")
        fflush(stdout)

        guard let line = Swift.readLine() else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            addEntry(trimmed)
        }
        return line
    }

    // MARK: - History management

    public func addEntry(_ entry: String) {
        // Deduplicate consecutive identical entries
        if entries.last == entry { return }
        entries.append(entry)
        // Keep last 500 entries
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        historyIndex = entries.count
        save()
    }

    public func previousEntry() -> String? {
        guard !entries.isEmpty else { return nil }
        if historyIndex > 0 { historyIndex -= 1 }
        return entries[historyIndex]
    }

    public func nextEntry() -> String? {
        guard !entries.isEmpty else { return nil }
        if historyIndex < entries.count - 1 {
            historyIndex += 1
            return entries[historyIndex]
        }
        historyIndex = entries.count
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyFile),
              let content = String(data: data, encoding: .utf8) else { return }
        entries = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        historyIndex = entries.count
    }

    public func save() {
        let content = entries.joined(separator: "\n")
        try? content.write(to: historyFile, atomically: true, encoding: .utf8)
    }

    private var isTTY: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }
}
