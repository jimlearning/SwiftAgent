import Foundation
import SwiftAgentCore

// MARK: - CollapsedGroup

/// A group of consecutive tool results that have been collapsed into a
/// single summary line. Mirrors Claude Code's `CollapsedReadSearchGroup`.
public struct CollapsedGroup: Sendable {
    /// The individual tool results within this group.
    public let results: [SingleToolResult]

    /// Human-readable one-line summary, e.g.
    /// "  Read 3 files, searched 2 patterns  [0.4s]  [#1]"
    public let summaryLine: String

    /// Reference index for `/expand N`.
    public let refIndex: Int

    public init(results: [SingleToolResult], summaryLine: String, refIndex: Int) {
        self.results = results
        self.summaryLine = summaryLine
        self.refIndex = refIndex
    }
}

// MARK: - CollapseDetector

/// Detects consecutive collapsible tool results and merges them into
/// `CollapsedGroup` values. Non-collapsible results pass through as
/// single-item groups.
///
/// Collapsible tools: Read, Glob, Grep, and Bash commands that look like
/// search/read operations (grep, find, cat, head, tail, ls, wc, etc.).
///
/// This is the SwiftAgent equivalent of Claude Code's `collapseReadSearch.ts`.
public struct CollapseDetector: Sendable {

    public init() {}

    /// Process a batch of tool results, merging consecutive collapsible
    /// results into groups and assigning reference indices.
    public func collapse(
        _ results: [SingleToolResult],
        startingIndex: Int,
        formatCommand: @Sendable (String, [String: JSONValue]) -> String,
        formatSummaryLine: @Sendable (CollapsedGroup) -> String
    ) -> [CollapsedGroup] {
        var groups: [CollapsedGroup] = []
        var index = startingIndex
        var buffer: [SingleToolResult] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let group = makeGroup(buffer, refIndex: index, formatSummaryLine: formatSummaryLine)
            groups.append(group)
            buffer = []
            index += 1
        }

        for result in results {
            if result.isCollapsible {
                buffer.append(result)
            } else {
                flushBuffer()
                // Non-collapsible → own group of 1
                let group = makeGroup([result], refIndex: index, formatSummaryLine: formatSummaryLine)
                groups.append(group)
                index += 1
            }
        }
        flushBuffer()

        return groups
    }

    private func makeGroup(
        _ results: [SingleToolResult],
        refIndex: Int,
        formatSummaryLine: @Sendable (CollapsedGroup) -> String
    ) -> CollapsedGroup {
        let summary = formatSummaryLine(
            CollapsedGroup(results: results, summaryLine: "", refIndex: refIndex)
        )
        return CollapsedGroup(results: results, summaryLine: summary, refIndex: refIndex)
    }

    // MARK: - Classification

    /// Returns true if a tool+input pair should be eligible for grouping
    /// with other collapsible tools.
    public static func isCollapsible(name: String, input: [String: JSONValue]) -> Bool {
        switch name {
        case "Read", "Glob", "Grep":
            return true
        case "Bash":
            if case .string(let cmd) = input["command"] {
                return isSearchOrReadCommand(cmd)
            }
            return false
        default:
            return false
        }
    }

    /// Heuristic: does a bash command look like it's searching or reading?
    private static func isSearchOrReadCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: CharacterSet.whitespaces)
        // Get the first non-comment, non-blank line
        let meaningfulLine = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .first ?? ""
        let firstWord = meaningfulLine.components(separatedBy: CharacterSet.whitespaces).first ?? ""

        // Commands that are reads/searches
        let readCommands: Set<String> = [
            "cat", "head", "tail", "less", "more",
            "grep", "rg", "ag", "ack", "find", "fd",
            "ls", "tree", "du", "wc", "stat",
            "file", "readlink", "realpath",
            "git", "diff", "cmp",
            "echo", "printf", "print",
            "which", "whereis", "type", "command",
        ]
        return readCommands.contains(firstWord)
    }

    /// Return a compact, human-readable command summary (like CC's
    /// `commandAsHint` and `getDisplayPath`). Truncates long commands to
    /// ~80 chars for use in one-line summaries.
    public static func commandSummary(name: String, input: [String: JSONValue]) -> String {
        switch name {
        case "Read":
            if case .string(let path) = input["file_path"] {
                return path.count <= 60 ? path : "…" + String(path.suffix(59))
            }
            return "(read)"
        case "Glob":
            if case .string(let pattern) = input["pattern"] { return pattern }
            return "(glob)"
        case "Grep":
            var parts: [String] = []
            if case .string(let pattern) = input["pattern"] { parts.append("\"\(pattern)\"") }
            if case .string(let path) = input["path"] { parts.append("in \(path)") }
            return parts.isEmpty ? "(grep)" : parts.joined(separator: " ")
        case "Bash":
            if case .string(let cmd) = input["command"] {
                let cleaned = cmd
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    .first ?? cmd
                let collapsed = cleaned.replacingOccurrences(
                    of: "\\s+", with: " ", options: .regularExpression
                ).trimmingCharacters(in: CharacterSet.whitespaces)
                return collapsed.count <= 80 ? collapsed : String(collapsed.prefix(77)) + "…"
            }
            return "(bash)"
        default:
            return name
        }
    }

    /// Like `commandSummary` but never truncates the command — suitable
    /// for the detailed multi-line display where the user expects to see
    /// the full invocation.
    public static func fullCommandSummary(name: String, input: [String: JSONValue]) -> String {
        switch name {
        case "Bash":
            if case .string(let cmd) = input["command"] {
                let cleaned = cmd
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    .first ?? cmd
                return cleaned.replacingOccurrences(
                    of: "\\s+", with: " ", options: .regularExpression
                ).trimmingCharacters(in: CharacterSet.whitespaces)
            }
            return "(bash)"
        default:
            // For all other tools, the standard summary is already
            // sufficiently descriptive
            return commandSummary(name: name, input: input)
        }
    }
}

// MARK: - Summary Line Formatter

/// Builds a single-line summary for a collapsed group, suitable for
/// display in the REPL. Matches Claude Code's `getSearchReadSummaryText`.
public struct CollapsedSummaryFormatter: Sendable {

    public let capability: TerminalCapability

    public init(capability: TerminalCapability) {
        self.capability = capability
    }

    /// Format a single-result group with content preview — shows the
    /// tool command plus up to 5 lines of actual output so the user can
    /// see what happened without needing /expand.
    ///
    /// Example:
    /// ```
    ///   Read → /path/to/file.swift
    ///     import Foundation
    ///     import ArgumentParser
    ///     ... 69 more lines (3.0KB)  [#4]
    /// ```
    public func formatDetailed(for group: CollapsedGroup) -> String {
        guard let result = group.results.first else {
            return "  (empty)  [#\(group.refIndex)]"
        }

        let nameColor = capability.color("  \(result.name)", color: .brightCyan)
        let dim = capability.color(" → ", color: .brightBlack)
        let cmd = CollapseDetector.fullCommandSummary(name: result.name, input: result.input)
        let idxTag = capability.color("  [#\(group.refIndex)]", color: .brightBlack)

        var lines: [String] = [nameColor + dim + cmd]

        let outputLines = result.output.components(separatedBy: "\n")
        let maxPreview = 5
        let previewCount = min(outputLines.count, maxPreview)

        for i in 0..<previewCount {
            var line = outputLines[i]
            // Trim to 200 chars to keep display tidy
            if line.count > 200 {
                line = String(line.prefix(200)) + "…"
            }
            lines.append(capability.color("    \(line)", color: .brightBlack))
        }

        let remaining = outputLines.count - previewCount
        if remaining > 0 {
            let statsLine = "  … \(remaining) more line\(remaining == 1 ? "" : "s") (\(Self.formattedSize(result.charCount)))" + idxTag
            lines.append(capability.color(statsLine, color: .brightBlack))
        } else {
            let statsLine = "  \(result.lineCount) line\(result.lineCount == 1 ? "" : "s") · \(Self.formattedSize(result.charCount))" + idxTag
            lines.append(capability.color(statsLine, color: .brightBlack))
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a one-line summary like:
    ///   "  Read 3 files, searched 2 patterns  [#1]"
    /// or for a single non-collapsible tool:
    ///   "  Bash  echo hello  [OK · 0 lines]  [#1]"
    public func format(for group: CollapsedGroup) -> String {
        let idxTag = capability.color("  [#\(group.refIndex)]", color: .brightBlack)

        guard let first = group.results.first else {
            return "  (empty)" + idxTag
        }

        // Single non-collapsible result → compact tool summary
        if group.results.count == 1 && !first.isCollapsible {
            let nameColor = capability.color("  \(first.name)", color: .brightCyan)
            let dim = capability.color("  ", color: .brightBlack)
            let cmd = CollapseDetector.commandSummary(name: first.name, input: first.input)
            let statLine = statPart(first)
            return nameColor + dim + cmd + "  " + statLine + idxTag
        }

        // Single collapsible result → direct tool summary
        if group.results.count == 1 {
            let nameColor = capability.color("  \(first.name)", color: .brightCyan)
            let dim = capability.color("  ", color: .brightBlack)
            let cmd = CollapseDetector.commandSummary(name: first.name, input: first.input)
            let statLine = statPart(first)
            return nameColor + dim + cmd + "  " + statLine + idxTag
        }

        // Multiple results → aggregated
        var reads = 0
        var searches = 0
        var listings = 0
        var nonCollapsible = 0
        var readPaths: Set<String> = []
        var searchPatterns: [String] = []
        var totalChars = 0
        var totalLines = 0

        for r in group.results {
            totalChars += r.charCount
            totalLines += r.lineCount
            if !r.isCollapsible {
                nonCollapsible += 1
                continue
            }
            switch r.name {
            case "Read":
                reads += 1
                if case .string(let p) = r.input["file_path"] {
                    readPaths.insert(p)
                }
            case "Glob", "Grep":
                searches += 1
                if case .string(let p) = r.input["pattern"] {
                    searchPatterns.append(p)
                }
            case "Bash":
                if case .string(let cmd) = r.input["command"] {
                    let firstWord = cmd.trimmingCharacters(in: CharacterSet.whitespaces)
                        .components(separatedBy: CharacterSet.whitespaces).first ?? ""
                    switch firstWord {
                    case "ls", "tree", "du":
                        listings += 1
                    case "grep", "rg", "ag", "ack", "find", "fd":
                        searches += 1
                        if case .string = r.input["command"] {
                            searchPatterns.append(firstWord + " …")
                        }
                    default:
                        reads += 1
                    }
                } else {
                    reads += 1
                }
            default:
                reads += 1
            }
        }

        var parts: [String] = []
        let uniqueReads = max(readPaths.count, reads)
        if reads > 0 {
            parts.append("Read \(uniqueReads) \(uniqueReads == 1 ? "file" : "files")")
        }
        if searches > 0 {
            parts.append("searched \(searches) \(searches == 1 ? "pattern" : "patterns")")
        }
        if listings > 0 {
            parts.append("listed \(listings) \(listings == 1 ? "dir" : "dirs")")
        }

        let action = parts.joined(separator: ", ")
        let dim = capability.color("  " + action, color: .brightBlack)
        let stats = capability.color(
            "  \(totalLines) lines · \(Self.formattedSize(totalChars))",
            color: .brightBlack
        )
        return dim + stats + idxTag
    }

    private func statPart(_ result: SingleToolResult) -> String {
        let dim = capability.color(
            "  \(result.lineCount) lines · \(Self.formattedSize(result.charCount))",
            color: .brightBlack
        )
        return dim
    }

    public static func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1_048_576 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }
}
