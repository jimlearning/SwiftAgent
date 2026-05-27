import Foundation

enum TerminalDisplayWidth {
    static func width(_ text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    static func visibleWidth(_ text: String) -> Int {
        width(stripANSIEscapes(from: text))
    }

    static func rows(forWidth width: Int, columns: Int) -> Int {
        let columns = max(1, columns)
        return max(1, (max(1, width) - 1) / columns + 1)
    }

    static func cursorPosition(forOffset offset: Int, columns: Int) -> (row: Int, column: Int) {
        let columns = max(1, columns)
        guard offset > 0 else { return (0, 0) }
        if offset % columns == 0 {
            return (offset / columns - 1, columns - 1)
        }
        return (offset / columns, offset % columns)
    }

    private static func width(of character: Character) -> Int {
        if character.unicodeScalars.contains(where: { $0.value == 0x200D }),
           character.unicodeScalars.contains(where: isEmoji) {
            return 2
        }

        var total = 0
        for scalar in character.unicodeScalars {
            total += width(of: scalar)
        }
        return max(total, 0)
    }

    private static func width(of scalar: UnicodeScalar) -> Int {
        let value = scalar.value

        if value == 0 { return 0 }
        if value == 9 { return 4 }
        if value < 32 || (value >= 0x7F && value < 0xA0) { return 0 }
        if isCombining(value) || isVariationSelector(value) || value == 0x200D { return 0 }
        if isWide(value) { return 2 }
        return 1
    }

    private static func isCombining(_ value: UInt32) -> Bool {
        switch value {
        case 0x0300...0x036F,
             0x1AB0...0x1AFF,
             0x1DC0...0x1DFF,
             0x20D0...0x20FF,
             0xFE20...0xFE2F:
            return true
        default:
            return false
        }
    }

    private static func isVariationSelector(_ value: UInt32) -> Bool {
        switch value {
        case 0xFE00...0xFE0F,
             0xE0100...0xE01EF:
            return true
        default:
            return false
        }
    }

    private static func isWide(_ value: UInt32) -> Bool {
        switch value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    private static func isEmoji(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1F000...0x1FAFF:
            return true
        default:
            return false
        }
    }

    private static func stripANSIEscapes(from text: String) -> String {
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
