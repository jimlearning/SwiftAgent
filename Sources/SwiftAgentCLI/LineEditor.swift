import Foundation
import Darwin

/// Line editor with raw terminal mode, supporting arrow-key history navigation,
/// left/right cursor movement, and persistent history file.
///
/// Swift equivalent of Nanobot's `_enable_line_editing()` which uses Python's
/// `readline` module (GNU readline / libedit wrapper).
public final class LineEditor: @unchecked Sendable {
    private let historyFile: URL
    private var entries: [String] = []
    private var historyIndex: Int = 0
    private var savedTermios: termios?
    private let isTTY: Bool
    private var pasteCount: Int = 0
    private var drawnLines: Int = 1  // terminal lines currently occupied by prompt+buffer

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

    /// Save history to disk.
    public func save() {
        let content = entries.joined(separator: "\n")
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
        var raw = saved
        raw.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        raw.c_cflag &= ~tcflag_t(CSIZE | PARENB)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_cc.0 = 1
        raw.c_cc.1 = 0
        tcsetattr(fd, TCSADRAIN, &raw)

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

        while true {
            let byte = readByte()
            if byte == nil { return nil }  // EOF

            switch byte {
            case 3:  // Ctrl+C
                writeToStdout("^C\r\n")
                return nil

            case 4:  // Ctrl+D
                if buffer.isEmpty {
                    return nil  // EOF on empty line
                }
                // Otherwise ignore (like bash)

            case 10, 13:  // Enter (\n or \r)
                // Detect paste: if more data is immediately available (within 0ms poll),
                // this \n is part of pasted content, not a manual Enter press.
                var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                if poll(&fds, 1, 0) > 0 {
                    let pasted = readPasteBytes()
                    let fullContent = buffer + "\n" + pasted
                    handlePaste(fullContent, prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                } else {
                    writeToStdout("\r\n")
                    let line = buffer.trimmingCharacters(in: .newlines)
                    if !line.isEmpty {
                        addEntry(line)
                    }
                    return line
                }

            case 127:  // Backspace (DEL)
                if cursorPos > 0 {
                    buffer.remove(at: buffer.index(buffer.startIndex, offsetBy: cursorPos - 1))
                    cursorPos -= 1
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                }

            case 27:  // Escape sequence (arrow keys, etc.)
                let seq = readEscapeSequence()
                switch seq {
                case .up:
                    navigateHistory(direction: -1, prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                case .down:
                    navigateHistory(direction: 1, prompt: prompt, buffer: &buffer, cursorPos: &cursorPos)
                case .left:
                    if cursorPos > 0 {
                        cursorPos -= 1
                        if buffer.contains("\n") { redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos) }
                        else { moveCursorLeft() }
                    }
                case .right:
                    if cursorPos < buffer.count {
                        cursorPos += 1
                        if buffer.contains("\n") { redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos) }
                        else { moveCursorRight() }
                    }
                case .home:
                    cursorPos = 0
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .end:
                    cursorPos = buffer.count
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .deleteWord:
                    // Alt+Backspace / Ctrl+W: delete word before cursor
                    if cursorPos > 0 {
                        let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                        let prefix = buffer[..<idx]
                        if let lastSpace = prefix.lastIndex(of: " ") {
                            let removeCount = cursorPos - (prefix.distance(from: prefix.startIndex, to: lastSpace) + 1)
                            let startIdx = buffer.index(buffer.startIndex, offsetBy: cursorPos - removeCount)
                            buffer.removeSubrange(startIdx..<idx)
                            cursorPos -= removeCount
                        } else {
                            buffer.removeSubrange(..<idx)
                            cursorPos = 0
                        }
                        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                    }
                case .newline:
                    // Option+Enter / Alt+Enter — insert literal newline
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    buffer.insert(contentsOf: "\n", at: idx)
                    cursorPos += 1
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
                case .none:
                    break  // Unknown escape sequence, ignore
                }

            case 21:  // Ctrl+U — clear line
                buffer = ""
                cursorPos = 0
                redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)

            case 23:  // Ctrl+W — delete word before cursor
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

            default:
                // Printable ASCII or multi-byte UTF-8
                if let (char, _) = decodeUTF8Char(leadByte: byte!) {
                    // Put back any extra bytes we already consumed from the continuation
                    // (decodeUTF8Char reads them, so we insert all at once)
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursorPos)
                    buffer.insert(char, at: idx)
                    cursorPos += 1
                    redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
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
    private func handlePaste(_ content: String, prompt: String, buffer: inout String, cursorPos: inout Int) {
        pasteCount += 1
        let lines = content.components(separatedBy: "\n")

        // Strip leading/trailing empty lines from paste
        let trimmed = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if trimmed.count <= 1 {
            // Single meaningful line — insert directly
            buffer = trimmed.first ?? ""
        } else {
            // Multi-line paste — display summary, don't auto-submit
            buffer = "[Pasted text #\(pasteCount) +\(trimmed.count) lines]"
        }
        cursorPos = buffer.count
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    // MARK: - Terminal control

    private func enterRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        savedTermios = raw

        // cfmakeraw equivalent
        raw.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        raw.c_cflag &= ~tcflag_t(CSIZE | PARENB)
        raw.c_cflag |= tcflag_t(CS8)

        // Minimum characters and timeout for read
        raw.c_cc.0 = 1     // VMIN: return after 1 byte
        raw.c_cc.1 = 0     // VTIME: no timeout

        tcsetattr(STDIN_FILENO, TCSADRAIN, &raw)
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
        case up, down, left, right, home, end, deleteWord, newline, none
    }

    private func readEscapeSequence() -> EscapeSequence {
        // We already consumed \033. Now read the rest with timeouts to avoid
        // hanging when Escape is pressed alone (no following bytes).
        guard let second = readByteWithTimeout() else { return .none }

        if second == 127 {  // \033\177 = Alt+Backspace on macOS
            return .deleteWord
        }

        // Option+Enter / Alt+Enter: ESC followed by \r or \n → insert newline
        if second == 10 || second == 13 { return .newline }

        guard second == 91 else { return .none }  // '['

        guard let third = readByteWithTimeout() else { return .none }

        // Parameterized CSI sequences start with digits.
        // Kitty keyboard protocol: \033[<key>;<mods>u
        // xterm modified keys:     \033[<key>;<mods>;<char>~
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
            if byte == 117 /* 'u' */, paramStr == "13;2" {
                return .newline
            }

            // xterm modified keys: CSI <key>;<mods>;<char> ~
            if byte == 126 /* '~' */ {
                let parts = paramStr.split(separator: ";")
                if parts.count >= 3, parts[2] == "13" {
                    return .newline
                }
            }

            return .none
        }
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

    private func navigateHistory(direction: Int, prompt: String, buffer: inout String, cursorPos: inout Int) {
        guard !entries.isEmpty else { return }

        let newIndex = historyIndex + direction
        guard newIndex >= 0, newIndex < entries.count else { return }

        historyIndex = newIndex
        buffer = entries[historyIndex]
        cursorPos = buffer.count
        redrawLine(prompt: prompt, buffer: buffer, cursorPos: cursorPos)
    }

    // MARK: - Display helpers

    private func redrawLine(prompt: String, buffer: String, cursorPos: Int) {
        let styledPrompt = "\u{001B}[1;34m\(prompt)\u{001B}[0m"
        let promptLen = prompt.count
        let newlineCount = buffer.components(separatedBy: "\n").count - 1

        // Move up to clear all previously drawn lines, then clear to end of display
        if drawnLines > 1 {
            writeToStdout("\u{001B}[\(drawnLines - 1)A")
        }
        writeToStdout("\r\u{001B}[J")

        // Draw prompt + buffer. \n in buffer is padded with prompt-width spaces
        // so continuation lines align under the first character of the first line:
        //   You: first line
        //        second line
        let pad = String(repeating: " ", count: promptLen)
        let displayBuffer = buffer.replacingOccurrences(of: "\n", with: "\n" + pad)
        writeToStdout(styledPrompt + displayBuffer)

        // Calculate cursor row/col within the displayed region.
        // Continuation lines are indented by promptLen, so col includes that offset.
        let prefix = String(buffer.prefix(cursorPos))
        let cursorRows = prefix.components(separatedBy: "\n").count - 1
        let lastNL = prefix.lastIndex(of: "\n")
        let colOffset: Int
        if let nl = lastNL {
            colOffset = promptLen + prefix.distance(from: prefix.index(after: nl), to: prefix.endIndex)
        } else {
            colOffset = promptLen + cursorPos
        }

        // Move cursor from end of drawn content back to target position
        let totalRows = newlineCount
        let upRows = totalRows - cursorRows
        if upRows > 0 {
            writeToStdout("\u{001B}[\(upRows)A")
        }
        writeToStdout("\r")
        if colOffset > 0 {
            writeToStdout("\u{001B}[\(colOffset)C")
        }

        drawnLines = 1 + newlineCount
    }

    private func moveCursorLeft() {
        writeToStdout("\u{001B}[1D")
    }

    private func moveCursorRight() {
        writeToStdout("\u{001B}[1C")
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
        entries = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        historyIndex = entries.count
    }
}
