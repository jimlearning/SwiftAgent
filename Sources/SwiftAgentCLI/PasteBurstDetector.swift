import Foundation

// MARK: - PasteBurstDetector

/// Detects and normalizes pasted content from the terminal.
///
/// Handles multi-line paste detection, content normalization, and placeholder
/// substitution for large pastes (matching Claude Code's paste burst behavior).
public struct PasteBurstDetector: Sendable {
    /// Counter for paste operations (to generate unique placeholder IDs).
    public private(set) var pasteCount: Int = 0

    /// Placeholder → content mapping for multi-line pastes.
    public private(set) var expansions: [String: String] = [:]

    public init() {}

    // MARK: - Paste detection

    /// Read bytes arriving in rapid succession from stdin (paste detection).
    /// Uses 50ms timeout — data arriving within 50ms of each other is considered
    /// part of the same paste operation.
    public mutating func readPasteBytes(from reader: TerminalRawReader) -> String {
        var data = Data()
        while reader.readByteWithTimeout(ms: 50) != nil {
            if let byte = reader.readByte() {
                data.append(byte)
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Content handling

    /// Normalize pasted content: unify line endings, strip leading/trailing blank lines.
    public static func normalizeContent(_ content: String) -> String {
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

    /// Create a placeholder string for a multi-line paste.
    public static func makePlaceholder(pasteIndex: Int, content: String) -> String {
        let normalized = normalizeContent(content)
        let lineCount = normalized.isEmpty ? 0 : normalized.components(separatedBy: "\n").count
        return "[Pasted text #\(pasteIndex) +\(max(0, lineCount - 1)) lines]"
    }

    /// Expand paste placeholders in text, replacing them with the stored content.
    public func expandPlaceholders(in text: String) -> String {
        var expanded = text
        for (placeholder, content) in expansions {
            expanded = expanded.replacingOccurrences(of: placeholder, with: content)
        }
        return expanded
    }

    // MARK: - Paste processing

    /// Process pasted content. For single-line content, returns the normalized text.
    /// For multi-line content, stores it in expansions and returns a placeholder.
    public mutating func processPaste(_ rawContent: String) -> String {
        pasteCount += 1
        let normalized = Self.normalizeContent(rawContent)
        let lineCount = normalized.isEmpty ? 0 : normalized.components(separatedBy: "\n").count

        if lineCount <= 1 {
            return normalized
        }

        let placeholder = Self.makePlaceholder(pasteIndex: pasteCount, content: normalized)
        expansions[placeholder] = normalized
        return placeholder
    }

    /// Reset all state (between readLine calls).
    public mutating func reset() {
        expansions.removeAll()
    }
}
