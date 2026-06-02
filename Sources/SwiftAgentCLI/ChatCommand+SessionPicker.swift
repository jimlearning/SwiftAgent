import Foundation
import Darwin
import SwiftAgentCore

extension ChatCommand {
    // MARK: - Interactive session picker

    /// Display an interactive arrow-key menu for selecting a saved session.
    /// Enters raw terminal mode, shows a highlighted list, and returns the
    /// chosen session ID (or nil if cancelled with Esc).
    func sessionPicker(sessions: [SessionMetadata]) -> String? {
        guard !sessions.isEmpty else { return nil }
        guard isatty(STDIN_FILENO) != 0 else { return nil }

        var saved = termios()
        tcgetattr(STDIN_FILENO, &saved)
        var raw = saved
        raw.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        raw.c_cflag &= ~tcflag_t(CSIZE | PARENB)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_cc.0 = 1
        raw.c_cc.1 = 0
        tcsetattr(STDIN_FILENO, TCSADRAIN, &raw)

        defer {
            tcsetattr(STDIN_FILENO, TCSADRAIN, &saved)
        }

        writeToStdout("\u{001B}[?25l")
        defer { writeToStdout("\u{001B}[?25h") }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        var selected = 0
        let itemCount = sessions.count
        let linesPerItem = 2
        let totalMenuLines = itemCount * linesPerItem

        func drawMenu() {
            var output = "\r\u{001B}[K"
            output += "\u{001B}[1mSaved Sessions (↑↓ to move, Enter to select, Esc to cancel):\u{001B}[0m\r\n"
            for (i, s) in sessions.enumerated() {
                let prefix = i == selected ? "\u{001B}[7m" : ""
                let suffix = i == selected ? "\u{001B}[0m" : ""
                let idShort = String(s.id.prefix(36))
                let dateStr = df.string(from: s.updatedAt)
                let titleHint = s.title.map { "  \"\($0.prefix(60))\"" } ?? ""
                output += "\r\u{001B}[K"
                output += "\(prefix)  [\(i+1)] \(idShort)\(titleHint)\(suffix)\r\n"
                output += "\r\u{001B}[K"
                output += "\(prefix)      \(dateStr)  ·  \(s.messageCount) msgs\(suffix)\r\n"
            }
            output += "\u{001B}[\(totalMenuLines + 1)A"
            writeToStdout(output)
        }

        drawMenu()

        while true {
            guard let byte = readRawByte() else { return nil }

            switch byte {
            case 3:
                writeToStdout("\r\n")
                return nil
            case 10, 13:
                let chosen = sessions[selected].id
                writeToStdout("\u{001B}[\(totalMenuLines)B")
                for _ in 0..<(totalMenuLines + 1) {
                    writeToStdout("\u{001B}[2K\u{001B}[A")
                }
                writeToStdout("\r\n")
                return chosen
            case 27:
                if let seq = readEscapeSeq() {
                    switch seq {
                    case .up:
                        if selected > 0 {
                            selected -= 1
                            drawMenu()
                        }
                    case .down:
                        if selected < itemCount - 1 {
                            selected += 1
                            drawMenu()
                        }
                    default:
                        break
                    }
                } else {
                    writeToStdout("\r\n")
                    return nil
                }
            default:
                break
            }
        }
    }

    private func readRawByte() -> UInt8? {
        var byte: UInt8 = 0
        let n = Darwin.read(STDIN_FILENO, &byte, 1)
        if n <= 0 { return nil }
        return byte
    }

    private func readRawByteWithTimeout(ms: Int32 = 50) -> UInt8? {
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ret = poll(&fds, 1, ms)
        if ret <= 0 { return nil }
        return readRawByte()
    }

    private enum EscapeSeq { case up, down, left, right }

    private func readEscapeSeq() -> EscapeSeq? {
        guard let second = readRawByteWithTimeout() else { return nil }
        if second == 91 {
            guard let third = readRawByteWithTimeout() else { return nil }
            switch third {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            default: return nil
            }
        }
        return nil
    }
}
