import Foundation
import Darwin

// MARK: - TerminalRawReader

/// Low-level terminal I/O: byte reading, escape sequence parsing, and raw mode management.
/// Abstracted from LineEditor to enable independent testing and reuse.
public protocol TerminalRawReader: AnyObject, Sendable {
    /// Read a single byte from stdin, blocking. Returns nil on EOF.
    func readByte() -> UInt8?

    /// Read a byte with a timeout (in milliseconds). Returns nil on timeout.
    func readByteWithTimeout(ms: Int32) -> UInt8?

    /// Decode a UTF-8 character starting from a lead byte.
    func decodeUTF8Char(leadByte: UInt8) -> (Character, Int)?
}

// MARK: - TerminalInput

/// Concrete implementation of raw terminal I/O.
/// Manages terminal mode switching (cooked ↔ raw) and all byte-level input.
public final class TerminalInput: TerminalRawReader, @unchecked Sendable {
    private let fd: Int32
    private var savedTermios: termios?
    private var bracketedPasteEnabled = false

    public init(fd: Int32 = STDIN_FILENO) {
        self.fd = fd
    }

    deinit {
        restore()
    }

    // MARK: - Raw mode

    /// Enter raw terminal mode. Saves current settings for later restoration.
    public func enterRawMode() {
        var raw = termios()
        tcgetattr(fd, &raw)
        savedTermios = raw

        raw = Self.rawAttributes(from: raw, preserveOutputProcessing: false)
        raw.c_cc.0 = 1
        raw.c_cc.1 = 0

        tcsetattr(fd, TCSADRAIN, &raw)
        writeToStdout("\u{001B}[?2004h")
        bracketedPasteEnabled = true
    }

    /// Restore saved terminal settings. Safe to call multiple times.
    public func restore() {
        guard let saved = savedTermios else { return }
        if bracketedPasteEnabled {
            writeToStdout("\u{001B}[?2004l")
            bracketedPasteEnabled = false
        }
        var attrs = saved
        tcsetattr(fd, TCSADRAIN, &attrs)
        savedTermios = nil
    }

    /// Compute raw mode attributes from a saved termios.
    public static func rawAttributes(from saved: termios, preserveOutputProcessing: Bool) -> termios {
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

    // MARK: - TerminalRawReader conformance

    public func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let n = Darwin.read(fd, &byte, 1)
        if n <= 0 { return nil }
        return byte
    }

    public func readByteWithTimeout(ms: Int32 = 50) -> UInt8? {
        var fds = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ret = poll(&fds, 1, ms)
        if ret <= 0 { return nil }
        return readByte()
    }

    public func decodeUTF8Char(leadByte: UInt8) -> (Character, Int)? {
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
            return nil
        }

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

    // MARK: - Escape sequences

    /// Known escape sequence types recognized by the parser.
    public enum EscapeSequence {
        case up, down, left, right
        case home, end
        case deleteWord          // Alt+Backspace
        case wordLeft, wordRight // Alt+Left/Right
        case newline             // Alt+Enter / Shift+Enter (kitty)
        case paste(String)       // Bracketed paste content
        case none                // Unknown / bare ESC
    }

    /// Read and decode an escape sequence (call after consuming the leading ESC byte).
    public func readEscapeSequence() -> EscapeSequence {
        guard let second = readByteWithTimeout() else { return .none }

        // Alt/Option+Backspace
        if second == 127 || second == 8 {
            return .deleteWord
        }

        // Option/Alt+Enter
        if second == 10 || second == 13 { return .newline }

        // Alt/Option+Left / +Right (readline-style)
        if second == 98 { return .wordLeft }   // 'b'
        if second == 102 { return .wordRight } // 'f'

        // CSI: ESC [
        if second == 91 {
            guard let third = readByteWithTimeout() else { return .none }

            if third >= 48, third <= 57 {
                return readComplexCSI(firstParamByte: third)
            }

            switch third {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            case 72: return .home
            case 70: return .end
            case 51:
                _ = readByteWithTimeout()
                return .none
            default:
                return .none
            }
        }

        // SS3: ESC O
        if second == 79 {
            guard let third = readByteWithTimeout() else { return .none }
            switch third {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            case 72: return .home
            case 70: return .end
            default: return .none
            }
        }

        return .none
    }

    /// Read bracketed paste content (between ESC[200~ and ESC[201~).
    public func readBracketedPasteContent() -> String {
        let terminator: [UInt8] = [27, 91, 50, 48, 49, 126]
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

    // MARK: - Complex CSI sequences (private)

    private func readComplexCSI(firstParamByte: UInt8) -> EscapeSequence {
        var paramBytes = [firstParamByte]

        while true {
            guard let byte = readByteWithTimeout(ms: 30) else { return .none }
            if (byte >= 48 && byte <= 57) || byte == 59 {
                paramBytes.append(byte)
                continue
            }

            let paramStr = String(bytes: paramBytes, encoding: .utf8) ?? ""

            if byte == 117 /* 'u' */ {
                if paramStr == "13;2" { return .newline }
                if paramStr == "127;5" { return .deleteWord }
            }

            if byte == 126 /* '~' */, paramStr == "200" {
                return .paste(readBracketedPasteContent())
            }

            if byte == 126 /* '~' */ {
                let parts = paramStr.split(separator: ";")
                if parts.count >= 3, parts[2] == "13" {
                    return .newline
                }
            }

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
}
