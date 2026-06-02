import Foundation

// MARK: - TextBuffer

/// A text buffer with cursor position, designed for in-terminal line editing.
/// Pure value type — no I/O, no rendering. All mutations are explicit.
public struct TextBuffer: Sendable {
    /// The raw buffer content.
    public private(set) var content: String
    /// Cursor position: count of characters from start (0...content.count).
    public private(set) var cursor: Int
    /// Ghost / placeholder text shown after the cursor in dim style.
    /// Set when a command with argumentHint is committed from popup.
    public var ghostText: String?

    public init(content: String = "", cursor: Int = 0, ghostText: String? = nil) {
        self.content = content
        self.cursor = cursor.clamped(to: 0...content.count)
        self.ghostText = ghostText
    }

    // MARK: - Queries

    public var isEmpty: Bool { content.isEmpty }

    /// The character at the cursor, or nil if cursor is at end.
    public var charAtCursor: Character? {
        guard cursor < content.count else { return nil }
        return content[content.index(content.startIndex, offsetBy: cursor)]
    }

    /// Text from start up to (but not including) the cursor.
    public var prefix: String {
        guard cursor > 0 else { return "" }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        return String(content[..<idx])
    }

    /// Text from cursor to end.
    public var suffix: String {
        guard cursor < content.count else { return "" }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        return String(content[idx...])
    }

    /// Lines in the buffer (components separated by \n).
    public var lines: [String] {
        content.components(separatedBy: "\n")
    }

    /// Whether the buffer contains at least one newline.
    public var isMultiline: Bool {
        content.contains("\n")
    }

    // MARK: - Mutations

    /// Insert a string at the cursor position.
    public mutating func insert(_ string: String) {
        guard !string.isEmpty else { return }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        content.insert(contentsOf: string, at: idx)
        cursor += string.count
        ghostText = nil
    }

    /// Insert a character at the cursor.
    public mutating func insert(_ char: Character) {
        insert(String(char))
    }

    /// Delete one character before the cursor (backspace).
    /// Returns the deleted character, or nil if cursor is at start.
    @discardableResult
    public mutating func deleteBackward() -> Character? {
        guard cursor > 0 else { return nil }
        cursor -= 1
        let idx = content.index(content.startIndex, offsetBy: cursor)
        let removed = content.remove(at: idx)
        ghostText = nil
        return removed
    }

    /// Delete the character at the cursor (forward delete).
    /// Returns the deleted character, or nil if cursor is at end.
    @discardableResult
    public mutating func deleteForward() -> Character? {
        guard cursor < content.count else { return nil }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        let removed = content.remove(at: idx)
        ghostText = nil
        return removed
    }

    /// Delete from cursor to end of line.
    public mutating func deleteToEnd() {
        guard cursor < content.count else { return }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        content.removeSubrange(idx...)
        ghostText = nil
    }

    /// Delete the word before the cursor (Ctrl+W / Alt+Backspace).
    public mutating func deleteWordBefore() {
        guard cursor > 0 else { return }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        var endIdx = idx
        // Skip trailing whitespace
        while endIdx > content.startIndex, content[content.index(before: endIdx)] == " " {
            endIdx = content.index(before: endIdx)
        }
        // Find word start
        while endIdx > content.startIndex, content[content.index(before: endIdx)] != " " {
            endIdx = content.index(before: endIdx)
        }
        let removeCount = content.distance(from: endIdx, to: idx)
        content.removeSubrange(endIdx..<idx)
        cursor -= removeCount
        ghostText = nil
    }

    /// Delete the alphanumeric word segment before cursor (Alt+Backspace behavior).
    public mutating func deleteAlnumSegmentBefore() -> Bool {
        guard cursor > 0 else { return false }
        let idx = content.index(content.startIndex, offsetBy: cursor)
        let prefix = content[..<idx]
        let wordChars = CharacterSet.alphanumerics

        var boundaryIdx = prefix.endIndex
        var foundWordChar = false
        var iterIdx = prefix.endIndex

        while iterIdx > prefix.startIndex {
            let prevIdx = prefix.index(before: iterIdx)
            let char = prefix[prevIdx]
            let isWordChar = char.unicodeScalars.allSatisfy { wordChars.contains($0) }

            if foundWordChar {
                if !isWordChar {
                    boundaryIdx = iterIdx
                    break
                }
            } else {
                if isWordChar { foundWordChar = true }
            }
            iterIdx = prevIdx
        }

        if iterIdx == prefix.startIndex { boundaryIdx = prefix.startIndex }

        let removeCount = content.distance(from: boundaryIdx, to: idx)
        content.removeSubrange(boundaryIdx..<idx)
        cursor -= removeCount
        ghostText = nil
        return true
    }

    /// Insert a newline at cursor.
    public mutating func insertNewline() {
        insert("\n")
    }

    /// Move cursor to a specific position (clamped to valid range).
    public mutating func setCursor(_ position: Int) {
        cursor = position.clamped(to: 0...content.count)
    }

    /// Move cursor left by one character (if possible).
    public mutating func moveLeft() -> Bool {
        guard cursor > 0 else { return false }
        cursor -= 1
        return true
    }

    /// Move cursor right by one character (if possible).
    public mutating func moveRight() -> Bool {
        guard cursor < content.count else { return false }
        cursor += 1
        return true
    }

    /// Move cursor to start of line.
    public mutating func moveToStartOfLine() {
        cursor = 0
    }

    /// Move cursor to end of line.
    public mutating func moveToEndOfLine() {
        cursor = content.count
    }

    /// Move cursor to previous word boundary (Alt+Left).
    public mutating func moveWordLeft() {
        cursor = wordBoundaryBefore(cursor)
    }

    /// Move cursor to next word boundary (Alt+Right).
    public mutating func moveWordRight() {
        cursor = wordBoundaryAfter(cursor)
    }

    /// Clear all content and reset cursor.
    public mutating func clearAll() {
        content = ""
        cursor = 0
        ghostText = nil
    }

    /// Replace the entire buffer.
    public mutating func replaceAll(with newContent: String) {
        content = newContent
        cursor = newContent.count
        ghostText = nil
    }

    /// Replace a range of text (from startOffset to endOffset) with a new string.
    public mutating func replace(subrangeFrom startOffset: Int, to endOffset: Int, with replacement: String) {
        let startIdx = content.index(content.startIndex, offsetBy: startOffset)
        let endIdx = content.index(content.startIndex, offsetBy: endOffset)
        content.replaceSubrange(startIdx..<endIdx, with: replacement)
        cursor = startOffset + replacement.count
    }

    // MARK: - Word boundaries (private)

    private func wordBoundaryBefore(_ pos: Int) -> Int {
        guard pos > 0 else { return 0 }
        let idx = content.index(content.startIndex, offsetBy: pos)
        let prefix = content[..<idx]

        var iterIdx = prefix.endIndex
        let wordChars = CharacterSet.alphanumerics

        while iterIdx > prefix.startIndex {
            let prevIdx = prefix.index(before: iterIdx)
            let isWord = prefix[prevIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if isWord { break }
            iterIdx = prevIdx
        }

        while iterIdx > prefix.startIndex {
            let prevIdx = prefix.index(before: iterIdx)
            let isWord = prefix[prevIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if !isWord { break }
            iterIdx = prevIdx
        }

        return content.distance(from: content.startIndex, to: iterIdx)
    }

    private func wordBoundaryAfter(_ pos: Int) -> Int {
        guard pos < content.count else { return content.count }
        let idx = content.index(content.startIndex, offsetBy: pos)
        let suffix = content[idx...]

        var iterIdx = suffix.startIndex
        let wordChars = CharacterSet.alphanumerics

        while iterIdx < suffix.endIndex {
            let isWord = suffix[iterIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if isWord { break }
            iterIdx = suffix.index(after: iterIdx)
        }

        while iterIdx < suffix.endIndex {
            let isWord = suffix[iterIdx].unicodeScalars.allSatisfy { wordChars.contains($0) }
            if !isWord { break }
            iterIdx = suffix.index(after: iterIdx)
        }

        return content.distance(from: content.startIndex, to: iterIdx)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
