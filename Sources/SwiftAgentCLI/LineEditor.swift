import Foundation
import Darwin

// MARK: - Editor Mode

/// Distinguishes normal line editing from the inline popup overlay.
enum EditorMode {
    case normal
    case popup(PopupState)

    var isPopup: Bool {
        if case .popup = self { return true }
        return false
    }
}

/// Mutable state for the inline popup while it is active.
struct PopupState {
    /// The trigger character that opened the popup (`@` or `/`).
    let trigger: Character
    /// Position of the trigger character in the input buffer.
    let triggerPos: Int
    /// The popup interaction engine.
    var popup: InlinePopup
}

/// Line editor with raw terminal mode, supporting arrow-key history navigation,
/// left/right cursor movement, and persistent history file.
///
/// Swift equivalent of Nanobot's `_enable_line_editing()` which uses Python's
/// `readline` module (GNU readline / libedit wrapper).
public final class LineEditor: @unchecked Sendable {
    private let historyFile: URL
    private var entries: [String] = []
    private var historyIndex: Int = 0
    /// Stashed buffer content when navigating history with a non-empty input line.
    /// Allows the user to return to their typed content by pressing ↓ past the
    /// newest history entry (bash/zsh readline behaviour).
    private var stashedBuffer: String?
    private var savedTermios: termios?
    private let isTTY: Bool
    private var pasteCount: Int = 0
    private var drawnLines: Int = 1  // terminal lines currently occupied by prompt+buffer
    /// Which row (0-indexed) the cursor was left at after the last redraw.
    /// Used to correctly reposition before clearing on the next redraw.
    private var lastCursorRow: Int = 0
    private var bracketedPasteEnabled = false

    // MARK: - Popup support

    /// Data source for slash-command (`/`) completions.
    private var slashDataSource: PopupDataSource?
    /// Data source for file (`@`) completions.
    private var atDataSource: PopupDataSource?
    /// Current editing mode — normal line editing or popup overlay.
    private var editorMode: EditorMode = .normal

    /// Configure popup data sources called when `@` or `/` is typed at a word boundary.
    /// - Parameters:
    ///   - slash: Provides completions for `/` (commands and skills).
    ///   - at: Provides completions for `@` (files and directories).
    public func setPopupDataSources(slash: PopupDataSource?, at: PopupDataSource?) {
        self.slashDataSource = slash
        self.atDataSource = at
    }

    /// After Ctrl+O is processed by rawModeReadLine, this is set to true.
    /// The REPL loop should check this after readLine returns an empty
    /// string and call /expand last.
    public var ctrlOTriggered: Bool = false

    // MARK: - Init

    public init(historyDir: URL? = nil) {
        let dir = historyDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent/history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.historyFile = dir.appendingPathComponent("cli_history")
        self.isTTY = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
        load()
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

    /// Save history to disk. Uses \0 (null byte) as entry separator to support
    /// multi-line history entries.
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

    /// Watch stdin for a bare Escape key press. Manages its own raw-mode
    /// terminal state so it can run between `readLine()` calls.
    /// Returns `true` if ESC was pressed (no follow-up byte within 50ms),
    /// `false` if the Task is cancelled.
    public func interceptEscape() async -> Bool {
        let fd = STDIN_FILENO

        // Save current (cooked) terminal and enter raw mode independently
        var saved = termios()
        tcgetattr(fd, &saved)
        var raw = Self.rawInputAttributes(from: saved, preserveOutputProcessing: true)
        raw.c_cc.0 = 1
        raw.c_cc.1 = 0
        tcsetattr(fd, TCSADRAIN, &raw)
        tcflush(fd, TCIFLUSH)  // drain any stale bytes from cooked-mode buffer

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

                // Distinguish bare ESC from escape sequences (arrow keys, etc.)
                var fds2 = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                if poll(&fds2, 1, 50) == 0 {
                    return true
                }
                // Drain the escape sequence bytes so they don't pollute the next readLine
                while poll(&fds2, 1, 10) > 0 {
                    _ = Darwin.read(fd, &byte, 1)
                }
            }
        }
        return false
    }

    /// Restore terminal settings. Safe to call multiple times.
    public func restoreTerminal() {
        guard let saved = savedTermios else { return }
        if bracketedPasteEnabled {
            writeToStdout("\u{001B}[?2004l")
            bracketedPasteEnabled = false
        }
        var attrs = saved
        tcsetattr(STDIN_FILENO, TCSADRAIN, &attrs)
        savedTermios = nil
    }

    // MARK: - Raw mode line editor

    private func rawModeReadLine(prompt: String) -> String? {
        // Print styled prompt
        let styledPrompt = "\u{001B}[1;34m\(prompt)\u{001B}[0m"
        writeToStdout(styledPrompt)

        // Enter raw mode
        enterRawMode()

        defer {
            restoreTerminal()
            writeToStdout("\r\n")
        }

        var buffer = ""
        var cursorPos = 0  // cursor position within buffer (0...buffer.count)
        var pasteExpansions: [String: String] = [:]
        stashedBuffer = nil
        lastCursorRow = 0
        drawnLines = 1

        while true {
            let byte = readByte()
            if byte == nil { return nil }  // EOF

            switch byte {
            case 3:  // Ctrl+C
                if case .popup = editorMode {
                    // Cancel popup — remove trigger + query from buffer
                    cancelPopup(prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                } else {
                    return nil
                }

            case 4:  // Ctrl+D
                if buffer.isEmpty {
                    return nil  // EOF on empty line
                }
                // Otherwise ignore (like bash)

            case 10, 13:  // Enter (\n or \r)
                if case .popup(let state) = editorMode {
                    // Commit selection: replace trigger..cursor with selected text + space
                    if let item = selectedPopupItem(state) {
                        commitPopupSelection(item: item, state: state,
                                             prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                } else {
                    // Fallback for terminals without bracketed paste: if more bytes
                    // are already queued, this newline belongs to the same paste.
                    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                    if poll(&fds, 1, 0) > 0 {
                        let pasted = readPasteBytes()
                        let fullContent = buffer + "\n" + pasted
                        replaceBufferWithPasteSummary(
                            fullContent,
                            prompt: prompt,
                            buffer: &buffer,
                            cursorPos: &cursorPos,
                            pasteExpansions: &pasteExpansions
                        )
                    } else {
                        writeToStdout("\r\n")
                        let line = Self.expandPastePlaceholders(
                            in: buffer,
                            expansions: pasteExpansions
                        ).trimmingCharacters(in: .newlines)
                        if !line.isEmpty {
                            addEntry(line)
                        }
                        return line
                    }
                }

            case 127:  // Backspace (DEL)
                if case .popup(var state) = editorMode {
                    // Remove last char from buffer (sync with popup query)
                    if cursorPos > state.triggerPos {
                        buffer.remove(at: buffer.index(buffer.startIndex, offsetBy: cursorPos - 1))
                        cursorPos -= 1
                    }
                    // Delete last query char; if query becomes empty, exit popup
                    let queryExhausted = state.popup.deleteQueryChar()
                    if queryExhausted || cursorPos <= state.triggerPos {
                        // Trigger only — exit popup and remove trigger char
                        cancelPopup(prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                    } else {
                        editorMode = .popup(state)  // write back mutated state
                    }
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                } else {
                    stashedBuffer = nil
                    if cursorPos > 0 {
                        buffer.remove(at: buffer.index(buffer.startIndex, offsetBy: cursorPos - 1))
                        cursorPos -= 1
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                }

            case 9:  // Tab — equivalent to Enter in popup mode
                if case .popup(let state) = editorMode {
                    if let item = selectedPopupItem(state) {
                        commitPopupSelection(item: item, state: state,
                                             prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                } else {
                    // Normal mode: Tab inserts spaces (standard terminal behavior)
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    buffer.insert(contentsOf: "    ", at: idx)
                    cursorPos += 4
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                }

            case 27:  // Escape sequence (arrow keys, etc.)
                let seq = readEscapeSequence()
                if case .popup(var state) = editorMode {
                    switch seq {
                    case .up:
                        state.popup.moveUp()
                        editorMode = .popup(state)
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    case .down:
                        state.popup.moveDown()
                        editorMode = .popup(state)
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    case .none:
                        // Bare ESC — cancel popup
                        cancelPopup(prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    default:
                        break  // Ignore other escape sequences in popup mode
                    }
                } else {
                    switch seq {
                case .up:
                    navigateHistory(direction: -1, prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                case .down:
                    navigateHistory(direction: 1, prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                case .left:
                    if cursorPos > 0 {
                        cursorPos -= 1
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                case .right:
                    if cursorPos < buffer.count {
                        cursorPos += 1
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                case .wordLeft:
                    // Alt+Left: move cursor to start of current/previous word
                    cursorPos = wordBoundaryBefore(cursorPos, in: buffer)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .wordRight:
                    // Alt+Right: move cursor to end of current/next word
                    cursorPos = wordBoundaryAfter(cursorPos, in: buffer)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .home:
                    cursorPos = 0
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .end:
                    cursorPos = buffer.count
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .deleteWord:
                    stashedBuffer = nil
                    // Alt+Backspace: delete word before cursor using alphanumeric boundaries
                    // Matches bash/zsh backward-kill-word behavior:
                    //   - If cursor is on or after a word boundary, delete preceding whitespace/punctuation
                    //   - Otherwise delete the alphanumeric/word segment before the cursor
                    if cursorPos > 0 {
                        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                        let prefix = buffer[..<idx]
                        let wordChars = CharacterSet.alphanumerics

                        // Find the boundary: scan backwards from cursor
                        var boundaryIdx = prefix.endIndex
                        var foundWordChar = false

                        // Walk backwards through the prefix
                        var iterIdx = prefix.endIndex
                        while iterIdx > prefix.startIndex {
                            let prevIdx = prefix.index(before: iterIdx)
                            let char = prefix[prevIdx]

                            // Determine if this character is a "word character" (alphanumeric)
                            let isWordChar = char.unicodeScalars.allSatisfy { wordChars.contains($0) }

                            if foundWordChar {
                                // We've seen word chars; stop at the first non-word char
                                if !isWordChar {
                                    boundaryIdx = iterIdx  // delete starts after this non-word char
                                    break
                                }
                            } else {
                                // Haven't seen word chars yet
                                if isWordChar {
                                    foundWordChar = true
                                }
                            }
                            iterIdx = prevIdx
                        }

                        if iterIdx == prefix.startIndex {
                            boundaryIdx = prefix.startIndex
                        }

                        let removeCount = buffer.distance(from: boundaryIdx, to: idx)
                        buffer.removeSubrange(boundaryIdx..<idx)
                        cursorPos -= removeCount
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                case .newline:
                    // Option+Enter / Alt+Enter — insert literal newline
                    stashedBuffer = nil
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    buffer.insert(contentsOf: "\n", at: idx)
                    cursorPos += 1
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .paste(let content):
                    stashedBuffer = nil
                    handlePaste(
                        content,
                        prompt: prompt,
                        buffer: &buffer,
                        cursorPos: &cursorPos,
                        pasteExpansions: &pasteExpansions
                    )
                case .none:
                    break  // Unknown escape sequence, ignore
                }
                }  // end else (normal mode escape handling)

            case 21:  // Ctrl+U — clear line
                stashedBuffer = nil
                editorMode = .normal
                buffer = ""
                cursorPos = 0
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)

            case 23:  // Ctrl+W — delete word before cursor
                stashedBuffer = nil
                if cursorPos > 0 {
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    // Skip trailing whitespace
                    var endIdx = idx
                    while endIdx > buffer.startIndex, buffer[buffer.index(before: endIdx)] == " " {
                        endIdx = buffer.index(before: endIdx)
                    }
                    // Find word start
                    while endIdx > buffer.startIndex, buffer[buffer.index(before: endIdx)] != " " {
                        endIdx = buffer.index(before: endIdx)
                    }
                    let removeCount = buffer.distance(from: endIdx, to: idx)
                    buffer.removeSubrange(endIdx..<idx)
                    cursorPos -= removeCount
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                }

            case 11:  // Ctrl+K — delete from cursor to end
                if cursorPos < buffer.count {
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    buffer.removeSubrange(idx...)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                }

            case 1:  // Ctrl+A — beginning of line
                cursorPos = 0
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)

            case 5:  // Ctrl+E — end of line
                cursorPos = buffer.count
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)

            case 15:  // Ctrl+O — expand last collapsed tool result
                writeToStdout("\r\n")
                ctrlOTriggered = true
                return ""

            default:
                // Printable ASCII or multi-byte UTF-8
                if let (char, _) = decodeUTF8Char(leadByte: byte!) {
                    if editorMode.isPopup {
                        // In popup mode: append char to search query
                        handlePopupChar(char: char, prompt: prompt,
                                         buffer: &buffer, cursorPos: &cursorPos)
                    } else if shouldTriggerPopup(char: char, buffer: buffer, cursorPos: cursorPos) {
                        // Normal mode, word-boundary trigger: insert char and open popup
                        stashedBuffer = nil
                        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                        buffer.insert(char, at: idx)
                        cursorPos += 1
                        openPopup(trigger: char, triggerPos: cursorPos - 1,
                                   prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                    } else {
                        // Normal mode: insert character
                        stashedBuffer = nil
                        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                        buffer.insert(char, at: idx)
                        cursorPos += 1
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                }
            }
        }
    }

    // MARK: - Paste handling

    /// Read bytes arriving in rapid succession (paste detection).
    /// Uses 50ms timeout — data arriving within 50ms of each other is considered
    /// part of the same paste operation.
    private func readPasteBytes() -> String {
        var data = Data()
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        while poll(&fds, 1, 50) > 0 {
            if let byte = readByte() {
                data.append(byte)
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Handle pasted content. Multi-line pastes show a summary instead of
    /// auto-submitting. Single-line or very short pastes are inserted directly.
    static func makePastePlaceholder(pasteIndex: Int, content: String) -> String {
        let normalized = normalizePastedContent(content)
        let lineCount = normalized.isEmpty ? 0 : normalized.components(separatedBy: "\n").count
        return "[Pasted text #\(pasteIndex) +\(max(0, lineCount - 1)) lines]"
    }

    static func expandPastePlaceholders(in text: String, expansions: [String: String]) -> String {
        var expanded = text
        for (placeholder, content) in expansions {
            expanded = expanded.replacingOccurrences(of: placeholder, with: content)
        }
        return expanded
    }

    private static func normalizePastedContent(_ content: String) -> String {
        let normalizedNewlines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalizedNewlines.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func handlePaste(
        _ content: String,
        prompt: String,
        buffer: inout String,
        cursorPos: inout Int,
        pasteExpansions: inout [String: String]
    ) {
        pasteCount += 1
        let normalized = Self.normalizePastedContent(content)
        let lineCount = normalized.isEmpty ? 0 : normalized.components(separatedBy: "\n").count

        let insertedText: String
        if lineCount <= 1 {
            // Single meaningful line — insert directly
            insertedText = normalized
        } else {
            // Multi-line paste — display summary, submit the original content.
            let placeholder = Self.makePastePlaceholder(pasteIndex: pasteCount, content: normalized)
            pasteExpansions[placeholder] = normalized
            insertedText = placeholder
        }

        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
        buffer.insert(contentsOf: insertedText, at: idx)
        cursorPos += insertedText.count
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    private func replaceBufferWithPasteSummary(
        _ content: String,
        prompt: String,
        buffer: inout String,
        cursorPos: inout Int,
        pasteExpansions: inout [String: String]
    ) {
        pasteCount += 1
        let normalized = Self.normalizePastedContent(content)
        let placeholder = Self.makePastePlaceholder(pasteIndex: pasteCount, content: normalized)
        pasteExpansions[placeholder] = normalized
        buffer = placeholder
        cursorPos = buffer.count
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    // MARK: - Terminal control

    private func enterRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        savedTermios = raw

        raw = Self.rawInputAttributes(from: raw, preserveOutputProcessing: false)

        // Minimum characters and timeout for read
        raw.c_cc.0 = 1     // VMIN: return after 1 byte
        raw.c_cc.1 = 0     // VTIME: no timeout

        tcsetattr(STDIN_FILENO, TCSADRAIN, &raw)
        writeToStdout("\u{001B}[?2004h")
        bracketedPasteEnabled = true
    }

    static func rawInputAttributes(from saved: termios, preserveOutputProcessing: Bool) -> termios {
        var raw = saved
        raw.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
        if !preserveOutputProcessing {
            raw.c_oflag &= ~tcflag_t(OPOST)
        }
        raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        raw.c_cflag &= ~tcflag_t(CSIZE | PARENB)
        raw.c_cflag |= tcflag_t(CS8)
        return raw
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let n = Darwin.read(STDIN_FILENO, &byte, 1)
        if n <= 0 { return nil }
        return byte
    }

    /// Read a byte with a short timeout. Returns nil if no data within the timeout.
    /// Used for escape sequences to avoid hanging on lone ESC key.
    private func readByteWithTimeout(ms: Int = 50) -> UInt8? {
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ret = poll(&fds, 1, Int32(ms))
        if ret <= 0 { return nil }
        return readByte()
    }

    private enum EscapeSequence {
        case up, down, left, right, home, end, deleteWord, wordLeft, wordRight, newline, paste(String), none
    }

    private func readEscapeSequence() -> EscapeSequence {
        // We already consumed \033. Now read the rest with timeouts to avoid
        // hanging when Escape is pressed alone (no following bytes).
        guard let second = readByteWithTimeout() else { return .none }

        // Alt/Option+Backspace: terminal-dependent sequences
        //   \033\177 = ESC + DEL (macOS Terminal with "Use Option as Meta key")
        //   \033\010 = ESC + BS  (some Linux terminals, xterm, etc.)
        if second == 127 || second == 8 {
            return .deleteWord
        }

        // Option+Enter / Alt+Enter: ESC followed by \r or \n → insert newline
        if second == 10 || second == 13 { return .newline }

        // Alt/Option+Left / +Right: readline-style word navigation
        //   \033b = ESC + b → word left  (backward-word)
        //   \033f = ESC + f → word right (forward-word)
        if second == 98 { return .wordLeft }   // 'b'
        if second == 102 { return .wordRight } // 'f'

        // CSI sequences: ESC [ ...
        if second == 91 {
            guard let third = readByteWithTimeout() else { return .none }

            // Parameterized CSI sequences start with digits.
            // Kitty keyboard protocol: \033[<key>;<mods>u
            if third >= 48, third <= 57 {
                return readComplexCSI(firstParamByte: third)
            }

            switch third {
            case 65: return .up      // A
            case 66: return .down    // B
            case 67: return .right   // C
            case 68: return .left    // D
            case 72: return .home    // H
            case 70: return .end     // F
            case 51:                 // '3' → Delete key: \033[3~
                _ = readByteWithTimeout()  // consume '~'
                return .none
            default:
                return .none
            }
        }

        // SS3 sequences: ESC O ... (application cursor keys, tmux, etc.)
        if second == 79 {
            guard let third = readByteWithTimeout() else { return .none }
            switch third {
            case 65: return .up      // A
            case 66: return .down    // B
            case 67: return .right   // C
            case 68: return .left    // D
            case 72: return .home    // H
            case 70: return .end     // F
            default:
                return .none
            }
        }

        return .none
    }

    /// Parse parameterized CSI sequences (kitty keyboard protocol and xterm modified keys).
    /// The first parameter byte has already been read; reads remaining bytes until a
    /// final byte (letter, `~`, or `u`) is found.
    private func readComplexCSI(firstParamByte: UInt8) -> EscapeSequence {
        var paramBytes = [firstParamByte]

        while true {
            guard let byte = readByteWithTimeout(ms: 30) else { return .none }
            // Accumulate parameter bytes (digits and semicolons)
            if (byte >= 48 && byte <= 57) || byte == 59 {  // '0'-'9' or ';'
                paramBytes.append(byte)
                continue
            }

            // Final byte found — interpret the sequence
            let paramStr = String(bytes: paramBytes, encoding: .utf8) ?? ""

            // Kitty keyboard protocol: CSI <key>;<mods> u
            // 13 = Return key, 2 = Shift modifier → Shift+Enter
            // 127 = Backspace, 5 = Alt modifier → Alt+Backspace
            if byte == 117 /* 'u' */ {
                if paramStr == "13;2" { return .newline }
                if paramStr == "127;5" { return .deleteWord }
            }

            // xterm modified keys: CSI <key>;<mods>;<char> ~
            if byte == 126 /* '~' */, paramStr == "200" {
                return .paste(readBracketedPasteContent())
            }

            if byte == 126 /* '~' */ {
                let parts = paramStr.split(separator: ";")
                if parts.count >= 3, parts[2] == "13" {
                    return .newline
                }
            }

            // xterm modified cursor keys: CSI <key>;<mods> <letter>
            //   Alt+Left:  CSI 1;3 D, Alt+Right: CSI 1;3 C
            if byte == 68 /* 'D' */ {
                let parts = paramStr.split(separator: ";")
                if parts.contains("3") { return .wordLeft }
                return .left
            }
            if byte == 67 /* 'C' */ {
                let parts = paramStr.split(separator: ";")
                if parts.contains("3") { return .wordRight }
                return .right
            }

            return .none
        }
    }

    private func readBracketedPasteContent() -> String {
        let terminator: [UInt8] = [27, 91, 50, 48, 49, 126] // ESC [ 201 ~
        var bytes: [UInt8] = []

        while let byte = readByte() {
            bytes.append(byte)
            if bytes.count >= terminator.count,
               Array(bytes.suffix(terminator.count)) == terminator {
                bytes.removeLast(terminator.count)
                break
            }
        }

        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// Decode a multi-byte UTF-8 character starting from a lead byte.
    /// Returns the character and number of bytes consumed, or nil if invalid.
    private func decodeUTF8Char(leadByte: UInt8) -> (Character, Int)? {
        // Determine sequence length from lead byte
        let seqLen: Int
        var codepoint: UInt32
        if leadByte & 0x80 == 0 {
            return (Character(UnicodeScalar(leadByte)), 1)
        } else if leadByte & 0xE0 == 0xC0 {
            seqLen = 2
            codepoint = UInt32(leadByte & 0x1F)
        } else if leadByte & 0xF0 == 0xE0 {
            seqLen = 3
            codepoint = UInt32(leadByte & 0x0F)
        } else if leadByte & 0xF8 == 0xF0 {
            seqLen = 4
            codepoint = UInt32(leadByte & 0x07)
        } else {
            return nil  // Invalid lead byte
        }

        // Read continuation bytes (use timeout since they may not arrive)
        var bytesRead = 1
        for _ in 1..<seqLen {
            guard let cont = readByteWithTimeout(ms: 20),
                  cont & 0xC0 == 0x80 else { return nil }
            codepoint = (codepoint << 6) | UInt32(cont & 0x3F)
            bytesRead += 1
        }

        guard let scalar = UnicodeScalar(codepoint) else { return nil }
        return (Character(scalar), bytesRead)
    }

    // MARK: - History navigation

    /// Multi-line aware navigation:
    /// - **Multi-line buffer (contains \n)**: ↑↓ move cursor between lines.
    ///   Pressing ↑ at first line or ↓ at last line navigates history.
    /// - **Single-line buffer**: normal history navigation.
    /// - **Buffer has content, first history move**: stash buffer for later restoration.
    private func navigateHistory(direction: Int, prompt: String, buffer: inout String, cursorPos: inout Int) {
        // Multi-line: try vertical cursor movement first
        if buffer.contains("\n") {
            let prefix = buffer.prefix(cursorPos)
            let lines = buffer.components(separatedBy: "\n")
            let currentLine = prefix.components(separatedBy: "\n").count - 1  // 0-based
            // Column position within current line
            let colInLine: Int
            if let lastNewline = prefix.lastIndex(of: "\n") {
                colInLine = prefix.distance(from: prefix.index(after: lastNewline), to: prefix.endIndex)
            } else {
                colInLine = cursorPos
            }

            if direction == -1 {  // ↑
                if currentLine > 0 {
                    // Move cursor to same column on previous line
                    var offset = 0
                    for i in 0..<(currentLine - 1) {
                        offset += lines[i].count + 1  // +1 for \n
                    }
                    let prevLineLen = lines[currentLine - 1].count
                    cursorPos = offset + min(colInLine, prevLineLen)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    return
                }
                // At first line: navigate history
            } else {  // ↓
                if currentLine < lines.count - 1 {
                    // Move cursor to same column on next line
                    var offset = 0
                    for i in 0..<currentLine {
                        offset += lines[i].count + 1  // +1 for \n
                    }
                    let nextLineStart = offset + lines[currentLine].count + 1  // +1 for \n
                    let nextLineLen = lines[currentLine + 1].count
                    cursorPos = nextLineStart + min(colInLine, nextLineLen)
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    return
                }
                // At last line: navigate history
            }
        }

        // History navigation (single-line or at boundary of multi-line)
        guard !entries.isEmpty else { return }

        // If there's content in the buffer and we haven't stashed it yet,
        // save it now and jump to the appropriate end of history.
        if !buffer.isEmpty && stashedBuffer == nil {
            stashedBuffer = buffer
            historyIndex = entries.count
        }

        if !buffer.isEmpty {
            let newIndex = historyIndex + direction

            // Pressing ↓ past the newest entry restores the stashed buffer.
            if direction > 0, newIndex >= entries.count {
                buffer = stashedBuffer ?? ""
                cursorPos = buffer.count
                stashedBuffer = nil
                historyIndex = entries.count
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                return
            }

            guard newIndex >= 0, newIndex < entries.count else { return }

            historyIndex = newIndex
            buffer = entries[historyIndex]
            cursorPos = buffer.count
            redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
            return
        }

        // Buffer is empty: normal sequential history navigation.
        // Explicitly stash empty string so pressing ↓ can restore to empty.
        if stashedBuffer == nil { stashedBuffer = "" }
        let newIndex = historyIndex + direction
        guard newIndex >= 0, newIndex < entries.count else { return }

        historyIndex = newIndex
        buffer = entries[historyIndex]
        cursorPos = buffer.count
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    // MARK: - Display helpers

    /// Find the word boundary before `pos` (Alt+Left behavior).
    /// Uses the same alphanumeric-based word detection as Alt+Backspace (deleteWord):
    ///   Phase 1 – skip backward through non-word characters (punctuation, CJK, spaces)
    ///   Phase 2 – skip backward through word characters (alphanumeric)
    /// Lands at the start of the chunk that deleteWord would remove.
    private func wordBoundaryBefore(_ pos: Int, in buffer: String) -> Int {
        guard pos > 0 else { return 0 }
        let idx = buffer.index(buffer.startIndex, offsetBy: pos)
        let prefix = buffer[..<idx]

        var iterIdx = prefix.endIndex
        let wordChars = CharacterSet.alphanumerics

        // Phase 1: skip backward through non-word characters
        while iterIdx > prefix.startIndex {
            let prevIdx = prefix.index(before: iterIdx)
            let isWord = prefix[prevIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if isWord { break }
            iterIdx = prevIdx
        }

        // Phase 2: skip backward through word characters
        while iterIdx > prefix.startIndex {
            let prevIdx = prefix.index(before: iterIdx)
            let isWord = prefix[prevIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if !isWord { break }
            iterIdx = prevIdx
        }

        return buffer.distance(from: buffer.startIndex, to: iterIdx)
    }

    /// Find the word boundary after `pos` (Alt+Right behavior).
    /// Symmetric to wordBoundaryBefore: skips the current word-or-nonword chunk
    /// then the complementary chunk, landing at the start of the next unit.
    private func wordBoundaryAfter(_ pos: Int, in buffer: String) -> Int {
        guard pos < buffer.count else { return buffer.count }
        let idx = buffer.index(buffer.startIndex, offsetBy: pos)
        let suffix = buffer[idx...]

        var iterIdx = suffix.startIndex
        let wordChars = CharacterSet.alphanumerics

        // Phase 1: skip forward through non-word characters
        while iterIdx < suffix.endIndex {
            let isWord = suffix[iterIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if isWord { break }
            iterIdx = suffix.index(after: iterIdx)
        }

        // Phase 2: skip forward through word characters
        while iterIdx < suffix.endIndex {
            let isWord = suffix[iterIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if !isWord { break }
            iterIdx = suffix.index(after: iterIdx)
        }

        return buffer.distance(from: buffer.startIndex, to: iterIdx)
    }

    private func redrawLine(prompt: String, buffer: String, cursorPos: Int) {
        let styledPrompt = "\u{001B}[1;34m\(prompt)\u{001B}[0m"
        let promptLen = TerminalDisplayWidth.width(prompt)
        let lines = buffer.components(separatedBy: "\n")
        let totalRows = renderedRows(promptWidth: promptLen, lines: lines)

        // Move cursor to row 0 of the previously drawn area, then clear.
        // lastCursorRow tracks which row the cursor was left at after the last redraw,
        // so we only move up by that amount (not the full drawnLines-1).
        if lastCursorRow > 0 {
            writeToStdout("\u{001B}[\(lastCursorRow)A")
        }
        writeToStdout("\r\u{001B}[J")

        // Draw first line with prompt
        writeToStdout(styledPrompt + lines[0])

        // Draw continuation lines: each at column promptLen (aligned under first char)
        let pad = String(repeating: " ", count: promptLen)
        for i in 1..<lines.count {
            writeToStdout("\r\n" + pad + lines[i])
        }

        // Calculate target cursor row/col
        let prefix = String(buffer.prefix(cursorPos))
        let target = cursorPosition(promptWidth: promptLen, prefix: prefix)

        // Move cursor from end of drawn content up to the target row
        let upRows = (totalRows - 1) - target.row
        if upRows > 0 {
            writeToStdout("\u{001B}[\(upRows)A")
        }
        writeToStdout("\r")
        if target.column > 0 {
            writeToStdout("\u{001B}[\(target.column)C")
        }

        // ── Popup rendering (if active) ──
        var popupHeight = 0
        if case .popup(let state) = editorMode {
            // Move to area below input: from current (target.row) to input end (totalRows - 1)
            let downToEnd = (totalRows - 1) - target.row
            let popupStartRow: Int
            if downToEnd >= 0 {
                if downToEnd > 0 { writeToStdout("\u{001B}[\(downToEnd)B") }
                writeToStdout("\r\n")
                popupStartRow = totalRows  // 0-based: right after the input area
            } else {
                writeToStdout("\r\n")
                popupStartRow = totalRows
            }
            state.popup.render(to: writeToStdout, terminalWidth: terminalColumns)
            popupHeight = state.popup.height

            // Explicitly restore cursor to input position (avoid \033[s/\033[u
            // which can behave inconsistently across terminals).
            // After popup render, cursor is at (popupStartRow + popupHeight, col 0).
            // Need to go to (target.row, target.column).
            let rowsAfterPopup = popupStartRow + popupHeight
            let rowsUp = rowsAfterPopup - target.row
            if rowsUp > 0 { writeToStdout("\u{001B}[\(rowsUp)A") }
            writeToStdout("\r")
            if target.column > 0 { writeToStdout("\u{001B}[\(target.column)C") }
        }

        drawnLines = totalRows + popupHeight
        lastCursorRow = target.row
    }

    private func renderedRows(promptWidth: Int, lines: [String]) -> Int {
        lines.reduce(0) { total, line in
            let width = promptWidth + TerminalDisplayWidth.width(line)
            return total + TerminalDisplayWidth.rows(forWidth: width, columns: terminalColumns)
        }
    }

    private func cursorPosition(promptWidth: Int, prefix: String) -> (row: Int, column: Int) {
        let prefixLines = prefix.components(separatedBy: "\n")
        var row = 0

        for line in prefixLines.dropLast() {
            let width = promptWidth + TerminalDisplayWidth.width(line)
            row += TerminalDisplayWidth.rows(forWidth: width, columns: terminalColumns)
        }

        let currentLine = prefixLines.last ?? ""
        let offset = promptWidth + TerminalDisplayWidth.width(currentLine)
        let position = TerminalDisplayWidth.cursorPosition(forOffset: offset, columns: terminalColumns)
        return (row + position.row, position.column)
    }

    private var terminalColumns: Int {
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        return Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "80") ?? 80
    }

    // MARK: - Popup helpers

    /// Returns whether typing `char` at the current position should trigger the popup.
    private func shouldTriggerPopup(char: Character, buffer: String, cursorPos: Int) -> Bool {
        guard char == "@" || char == "/" else { return false }
        guard slashDataSource != nil || atDataSource != nil else { return false }
        // Word boundary: start of line, or preceded by space / newline
        if cursorPos == 0 { return true }
        let prevIdx = buffer.index(buffer.startIndex, offsetBy: cursorPos - 1)
        let prev = buffer[prevIdx]
        return prev == " " || prev == "\n"
    }

    /// Open the popup for the given trigger character.
    private func openPopup(trigger: Character, triggerPos: Int,
                            prompt: String, buffer: inout String, cursorPos: inout Int) {
        let ds: PopupDataSource?
        switch trigger {
        case "/": ds = slashDataSource
        case "@": ds = atDataSource
        default:  ds = nil
        }
        guard let dataSource = ds else { return }

        var popup = InlinePopup(dataSource: dataSource)
        // The query starts empty — user will type to filter
        popup.refresh()
        editorMode = .popup(PopupState(trigger: trigger, triggerPos: triggerPos, popup: popup))
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    /// Handle a character typed while the popup is active.
    private func handlePopupChar(char: Character,
                                  prompt: String, buffer: inout String, cursorPos: inout Int) {
        guard case .popup(var state) = editorMode else { return }
        // Insert the character into the buffer (which IS the search query)
        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
        buffer.insert(char, at: idx)
        cursorPos += 1
        // Also append to the popup query
        state.popup.appendQuery(char)
        editorMode = .popup(state)
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    /// The currently selected item in the popup, or nil if there are no items.
    private func selectedPopupItem(_ state: PopupState) -> PopupItem? {
        guard state.popup.selectedIndex < state.popup.items.count else { return nil }
        return state.popup.items[state.popup.selectedIndex]
    }

    /// Replace the trigger + query portion of the buffer with the selected item's text + space.
    private func commitPopupSelection(item: PopupItem,
                                       state: PopupState,
                                       prompt: String, buffer: inout String, cursorPos: inout Int) {
        let triggerIdx = buffer.index(buffer.startIndex, offsetBy: state.triggerPos)
        let cursorIdx = buffer.index(buffer.startIndex, offsetBy: cursorPos)

        let replacement = item.insertText + " "
        buffer.replaceSubrange(triggerIdx..<cursorIdx, with: replacement)
        cursorPos = state.triggerPos + replacement.count
        editorMode = .normal
    }

    /// Cancel the popup: remove the trigger character and any search query from the buffer.
    private func cancelPopup(prompt: String, buffer: inout String, cursorPos: inout Int) {
        guard case .popup(let state) = editorMode else { return }
        let triggerIdx = buffer.index(buffer.startIndex, offsetBy: state.triggerPos)
        let cursorIdx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
        buffer.removeSubrange(triggerIdx..<cursorIdx)
        cursorPos = state.triggerPos
        editorMode = .normal
    }

    private func writeToStdout(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        _ = Darwin.write(STDOUT_FILENO, (data as NSData).bytes, data.count)
    }

    // MARK: - Fallback (non-TTY)

    private func fallbackReadLine(prompt: String) -> String? {
        let styledPrompt = isTTY ? "\u{001B}[1;34m\(prompt)\u{001B}[0m" : prompt
        print(styledPrompt, terminator: "")
        fflush(stdout)
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
            // New format: null-byte separated (supports multi-line entries)
            entries = content.components(separatedBy: "\0").filter { !$0.isEmpty }
        } else {
            // Legacy format: newline separated (auto-migrate on next save)
            entries = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        historyIndex = entries.count
    }
}
