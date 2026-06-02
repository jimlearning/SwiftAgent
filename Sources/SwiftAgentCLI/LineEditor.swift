import Foundation
import Darwin
import CoreGraphics

// MARK: - LineEditor (refactored)

/// Line editor with raw terminal mode, supporting arrow-key history navigation,
/// left/right cursor movement, and persistent history file.
///
/// Internally uses:
/// - `TextBuffer` for text/cursor state management
/// - `TerminalInput` for raw terminal I/O
/// - `EditorRenderer` for drawing to terminal
/// - `PasteBurstDetector` for paste detection and placeholder substitution
/// - `ComposerState` for popup overlay management
///
/// Swift equivalent of Nanobot's `_enable_line_editing()` which uses Python's
/// `readline` module (GNU readline / libedit wrapper).
public final class LineEditor: @unchecked Sendable {
    // MARK: - Persistence

    private let historyFile: URL
    internal var entries: [String] = []
    internal var historyIndex: Int = 0
    internal var stashedBuffer: String?
    private let isTTY: Bool

    // MARK: - Subsystems

    private let terminal: any TerminalRawReader
    private var composer: ComposerState
    private var pasteDetector = PasteBurstDetector()

    /// After Ctrl+O is processed by rawModeReadLine, this is set to true.
    public var ctrlOTriggered: Bool = false

    // MARK: - Init

    public init(historyDir: URL? = nil) {
        let dir = historyDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent/history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.historyFile = dir.appendingPathComponent("cli_history")
        self.isTTY = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
        self.terminal = TerminalInput()
        self.composer = ComposerState()
        load()
    }

    /// Test-only init: inject a `TerminalRawReader` so unit tests can drive
    /// the read loop without a real PTY. Bypasses the `isatty` guard when
    /// `isTTY: true` is passed.
    internal init(terminal: any TerminalRawReader,
                  isTTY: Bool = true,
                  historyDir: URL? = nil) {
        let dir = historyDir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-agent-test-history-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.historyFile = dir.appendingPathComponent("cli_history")
        self.isTTY = isTTY
        self.terminal = terminal
        self.composer = ComposerState()
    }

    deinit {
        restoreTerminal()
    }

    // MARK: - Public API

    /// Read a line with the given prompt and full line-editing support.
    /// Returns nil on EOF or Ctrl+D on an empty line.
    public func readLine(prompt: String) -> String? {
        guard isTTY else {
            return fallbackReadLine(prompt: prompt)
        }
        return rawModeReadLine(prompt: prompt)
    }

    /// Save history to disk.
    public func save() {
        let content = entries.map { $0 + "\0" }.joined()
        try? content.write(to: historyFile, atomically: true, encoding: .utf8)
    }

    /// Add an entry to history (deduplicates consecutive identical entries).
    public func addEntry(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if entries.last == trimmed { return }
        entries.append(trimmed)
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        historyIndex = entries.count
        save()
    }

    /// Watch stdin for a bare Escape key press.
    public func interceptEscape() async -> Bool {
        let fd = STDIN_FILENO
        var saved = termios()
        tcgetattr(fd, &saved)
        var raw = TerminalInput.rawAttributes(from: saved, preserveOutputProcessing: true)
        raw.c_cc.0 = 1
        raw.c_cc.1 = 0
        tcsetattr(fd, TCSADRAIN, &raw)
        tcflush(fd, TCIFLUSH)

        defer {
            tcsetattr(fd, TCSADRAIN, &saved)
        }

        while !Task.isCancelled {
            var fds = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ret = poll(&fds, 1, 100)
            if ret > 0 {
                var byte: UInt8 = 0
                let n = Darwin.read(fd, &byte, 1)
                guard n > 0, byte == 27 else { continue }

                var fds2 = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                if poll(&fds2, 1, 50) == 0 {
                    return true
                }
                while poll(&fds2, 1, 10) > 0 {
                    _ = Darwin.read(fd, &byte, 1)
                }
            }
        }
        return false
    }

    /// Restore terminal settings.
    public func restoreTerminal() {
        terminal.restore()
    }

    /// Configure popup data sources.
    public func setPopupDataSources(slash: PopupDataSource?, at: PopupDataSource?) {
        composer.setDataSources(slash: slash, at: at)
    }

    // MARK: - Raw mode line editor

    private func rawModeReadLine(prompt: String) -> String? {
        let promptWidth = TerminalDisplayWidth.width(prompt)
        var renderer = EditorRenderer(prompt: prompt, promptWidth: promptWidth, terminalColumns: terminalColumns)

        // Print styled prompt
        EditorRenderer.writePrompt(prompt, isTTY: isTTY)

        terminal.enterRawMode()
        defer {
            terminal.restore()
            if isTTY { writeToStdout("\r\n") }
        }

        var buffer = TextBuffer()
        stashedBuffer = nil
        composer.mode = .normal
        pasteDetector.reset()

        while true {
            let byte = terminal.readByte()
            if byte == nil { return nil }

            switch byte {
            case 3:  // Ctrl+C
                if composer.mode.isPopup {
                    composer.cancelPopup(buffer: &buffer)
                    redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                } else {
                    return nil
                }

            case 4:  // Ctrl+D
                if buffer.isEmpty { return nil }

            case 10, 13:  // Enter
                if Self.isShiftHeld() {
                    stashedBuffer = nil
                    buffer.insertNewline()
                    redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    break
                }

                if composer.mode.isPopup {
                    let outcome = composer.handlePopupEnter(buffer: &buffer)
                    switch outcome {
                    case .resolved:
                        // Popup committed and closed — flush the line.
                        writeToStdout("\r\n")
                        let line = pasteDetector.expandPlaceholders(in: buffer.content)
                            .trimmingCharacters(in: .newlines)
                        if !line.isEmpty { addEntry(line) }
                        return line
                    case .subMenuOpened:
                        // Sub-menu is active — keep editing.
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    }
                } else {
                    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                    if poll(&fds, 1, 0) > 0 {
                        let pasted = pasteDetector.readPasteBytes(from: terminal)
                        let fullContent = buffer.content + "\n" + pasted
                        buffer.replaceAll(with: pasteDetector.processPaste(fullContent))
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    } else {
                        writeToStdout("\r\n")
                        let line = pasteDetector.expandPlaceholders(in: buffer.content)
                            .trimmingCharacters(in: .newlines)
                        if !line.isEmpty { addEntry(line) }
                        return line
                    }
                }

            case 127:  // Backspace (DEL)
                stashedBuffer = nil
                if composer.mode.isPopup {
                    _ = composer.handlePopupBackspace(buffer: &buffer)
                } else {
                    buffer.deleteBackward()
                }
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 9:  // Tab
                if composer.mode.isPopup {
                    let outcome = composer.handlePopupTab(buffer: &buffer)
                    if case .resolved = outcome {
                        // Tab on a popup with no sub-menu — keep editing
                        // (don't flush). The current behavior was to
                        // commit-and-stay-on-input-line, which is the same
                        // as Space.
                    }
                    redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                } else {
                    buffer.insert("    ")
                    redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                }

            case 27:  // Escape sequence
                let seq = terminal.readEscapeSequence()
                if composer.mode.isPopup {
                    switch seq {
                    case .up:   composer.handlePopupMoveUp()
                    case .down: composer.handlePopupMoveDown()
                    case .none: composer.cancelPopup(buffer: &buffer)
                    default:    break
                    }
                    redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                } else {
                    if handleNormalEscape(seq: seq, buffer: &buffer) {
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    }
                }

            case 21:  // Ctrl+U — clear line
                stashedBuffer = nil
                composer.mode = .normal
                buffer.clearAll()
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 23:  // Ctrl+W — delete word before cursor
                stashedBuffer = nil
                buffer.deleteWordBefore()
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 11:  // Ctrl+K — delete from cursor to end
                buffer.deleteToEnd()
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 1:  // Ctrl+A — beginning of line
                buffer.moveToStartOfLine()
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 5:  // Ctrl+E — end of line
                buffer.moveToEndOfLine()
                redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)

            case 15:  // Ctrl+O — expand last collapsed tool result
                ctrlOTriggered = true
                return ""

            default:
                if let (char, _) = terminal.decodeUTF8Char(leadByte: byte!) {
                    if composer.mode.isPopup {
                        let outcome = composer.handlePopupChar(char: char, buffer: &buffer)
                        if case .resolved = outcome, !composer.mode.isPopup {
                            // Space committed a popup with no sub-menu.
                            // Flush the line so the next readLine call
                            // gets a fresh buffer instead of appending
                            // subsequent input to the committed text.
                            writeToStdout("\r\n")
                            let line = pasteDetector.expandPlaceholders(in: buffer.content)
                                .trimmingCharacters(in: .newlines)
                            if !line.isEmpty { addEntry(line) }
                            return line
                        }
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    } else if composer.shouldTriggerPopup(char: char, buffer: buffer) {
                        stashedBuffer = nil
                        buffer.insert(char)
                        composer.openPopup(trigger: char, triggerPos: buffer.cursor - 1, buffer: &buffer)
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    } else {
                        stashedBuffer = nil
                        buffer.insert(char)
                        redraw(renderer: &renderer, buffer: &buffer, promptWidth: promptWidth)
                    }
                }
            }
        }
    }

    // MARK: - Redraw

    /// Redraw the input buffer and, if active, the popup overlay.
    /// Centralized so every byte handler invokes the same composite render.
    private func redraw(renderer: inout EditorRenderer, buffer: inout TextBuffer, promptWidth: Int) {
        let prefix = String(buffer.content.prefix(buffer.cursor))
        let target = renderer.cursorPosition(promptWidth: promptWidth, prefix: prefix)
        renderer.redraw(buffer: buffer)
        if composer.mode.isPopup {
            let popupStartRow = renderer.moveToPopupArea()
            let popupHeight = composer.renderPopup(to: { writeToStdout($0) }, terminalWidth: terminalColumns)
            renderer.restoreCursorAfterPopup(target: target, popupStartRow: popupStartRow, popupHeight: popupHeight)
        }
    }

    // MARK: - Escape sequence handling (normal mode)

    private func handleNormalEscape(
        seq: EscapeSequence,
        buffer: inout TextBuffer

    ) -> Bool {
        switch seq {
        case .up:
            navigateHistory(direction: -1, buffer: &buffer)
            return true

        case .down:
            navigateHistory(direction: 1, buffer: &buffer)
            return true

        case .left:
            _ = buffer.moveLeft()
            return true

        case .right:
            _ = buffer.moveRight()
            return true

        case .wordLeft:
            buffer.moveWordLeft()
            return true

        case .wordRight:
            buffer.moveWordRight()
            return true

        case .home:
            buffer.moveToStartOfLine()
            return true

        case .end:
            buffer.moveToEndOfLine()
            return true

        case .deleteWord:
            stashedBuffer = nil
            _ = buffer.deleteAlnumSegmentBefore()
            return true

        case .newline:
            stashedBuffer = nil
            buffer.insertNewline()
            return true

        case .paste(let content):
            stashedBuffer = nil
            let text = pasteDetector.processPaste(content)
            buffer.insert(text)
            return true

        case .none:
            return false
        }
    }

    // MARK: - History navigation

    internal func navigateHistory(direction: Int, buffer: inout TextBuffer) {
        // Multi-line: try vertical cursor movement first
        if buffer.isMultiline {
            let prefix = buffer.content.prefix(buffer.cursor)
            let lines = buffer.lines
            let currentLine = prefix.components(separatedBy: "\n").count - 1

            let colInLine: Int
            if let lastNewline = prefix.lastIndex(of: "\n") {
                colInLine = prefix.distance(from: prefix.index(after: lastNewline), to: prefix.endIndex)
            } else {
                colInLine = buffer.cursor
            }

            if direction == -1, currentLine > 0 {  // ↑ within multiline
                var offset = 0
                for i in 0..<(currentLine - 1) { offset += lines[i].count + 1 }
                let prevLineLen = lines[currentLine - 1].count
                buffer.setCursor(offset + min(colInLine, prevLineLen))
                return
            }
            if direction == 1, currentLine < lines.count - 1 {  // ↓ within multiline
                var offset = 0
                for i in 0..<lines.count - 1 { offset += lines[i].count + 1 }
                // Actually we need offset to the next line start
                offset = 0
                for i in 0...currentLine { offset += lines[i].count + 1 }
                let nextLineLen = lines[currentLine + 1].count
                buffer.setCursor(offset + min(colInLine, nextLineLen))
                return
            }
        }

        // History navigation
        guard !entries.isEmpty else { return }

        if !buffer.isEmpty && stashedBuffer == nil {
            stashedBuffer = buffer.content
            historyIndex = entries.count
        }

        if !buffer.content.isEmpty {
            let newIndex = historyIndex + direction

            if direction > 0, newIndex >= entries.count {
                buffer.replaceAll(with: stashedBuffer ?? "")
                stashedBuffer = nil
                historyIndex = entries.count
                return
            }

            guard newIndex >= 0, newIndex < entries.count else { return }

            historyIndex = newIndex
            buffer.replaceAll(with: entries[historyIndex])
            return
        }

        if stashedBuffer == nil { stashedBuffer = "" }
        let newIndex = historyIndex + direction
        guard newIndex >= 0, newIndex < entries.count else { return }

        historyIndex = newIndex
        buffer.replaceAll(with: entries[historyIndex])
    }



    // MARK: - Terminal

    private var terminalColumns: Int {
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        return Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "80") ?? 80
    }

    private func writeToStdout(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        _ = Darwin.write(STDOUT_FILENO, (data as NSData).bytes, data.count)
    }

    // MARK: - Shift key detection

    private static func isShiftHeld() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskShift)
    }

    // MARK: - Fallback (non-TTY)

    private func fallbackReadLine(prompt: String) -> String? {
        EditorRenderer.writePrompt(prompt, isTTY: isTTY)
        guard let line = Swift.readLine() else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { addEntry(trimmed) }
        return line
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyFile),
              let content = String(data: data, encoding: .utf8) else { return }
        if content.contains("\0") {
            entries = content.components(separatedBy: "\0").filter { !$0.isEmpty }
        } else {
            entries = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        historyIndex = entries.count
    }
}
