import Foundation
import SwiftAgentCore

/// Converts markdown text to ANSI-formatted terminal output.
/// Post-processes accumulated response text before display.
/// Rendering style inspired by TermKit's MarkdownView.
public struct MarkdownRenderer: Sendable {
    private let capability: TerminalCapability
    private let theme: ColorTheme
    private let syntaxHighlighter: (any SyntaxHighlightingEngine)?
    private let codeTheme: CodeTheme

    public init(
        capability: TerminalCapability,
        theme: ColorTheme,
        syntaxHighlighter: (any SyntaxHighlightingEngine)? = nil,
        codeTheme: CodeTheme = .monokai
    ) {
        self.capability = capability
        self.theme = theme
        self.syntaxHighlighter = syntaxHighlighter
        self.codeTheme = codeTheme
    }

    // MARK: - Public

    /// Render markdown string to ANSI-formatted string.
    public func render(_ markdown: String) -> String {
        // Pre-process: auto-detect code blocks in plain text (no explicit fences)
        // and wrap them in ``` fences so the rendering pipeline highlights them.
        let processed = autoDetectCodeBlocks(markdown)
        let lines = processed.components(separatedBy: "\n")
        var result: [String] = []
        var inFence = false
        var fenceLang: String? = nil
        var fenceLines: [String] = []
        var fenceDelimiter: Character = "`"
        var fenceCount: Int = 0
        var fenceDepth: Int = 0   // depth of inner fences within a code block
        var tableBuffer: [String] = []

        /// Flush table buffer: detect if it forms a valid table, render accordingly.
        func flushTableBuffer() {
            defer { tableBuffer = [] }
            guard tableBuffer.count >= 2,
                  isTableRow(tableBuffer[0]),
                  isSeparatorRow(tableBuffer[1]) else {
                // Not a table — render as regular lines
                for line in tableBuffer {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        result.append(border(""))
                    } else if let heading = renderHeading(line) {
                        result.append(heading)
                    } else {
                        result.append(border(renderInline(line)))
                    }
                }
                return
            }
            renderTable(header: tableBuffer[0], separator: tableBuffer[1],
                        rows: Array(tableBuffer.dropFirst(2)), into: &result)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Fenced code block detection ---
            if let fi = parseFenceInfo(trimmed) {
                flushTableBuffer()
                if inFence {
                    if !fi.isPureFence {
                        // Language fence (e.g. ```bash): inner opening — content
                        fenceDepth += 1
                        fenceLines.append(line)
                    } else if fi.delimiter == fenceDelimiter, fi.count > fenceCount {
                        // More delimiters than opening — always closes
                        fenceDepth = 0
                        renderCodeBlock(fenceLines, language: fenceLang, into: &result)
                        fenceLines = []
                        inFence = false
                        fenceLang = nil
                    } else if fi.delimiter == fenceDelimiter, fi.count >= fenceCount {
                        if fenceDepth > 0 {
                            // Closing an inner opened block
                            fenceDepth -= 1
                            fenceLines.append(line)
                        } else if fenceLang?.lowercased() == "markdown" {
                            // Markdown source display (e.g. README) contains ```
                            // fences as content. Treat same-count pure fences as
                            // content — recursive render() handles inner blocks.
                            fenceLines.append(line)
                        } else {
                            // Normal close: same-count pure fence closes the block
                            renderCodeBlock(fenceLines, language: fenceLang, into: &result)
                            fenceLines = []
                            inFence = false
                            fenceLang = nil
                        }
                    } else {
                        fenceLines.append(line)
                    }
                } else {
                    fenceLang = fi.language
                    inFence = true
                    fenceDelimiter = fi.delimiter
                    fenceCount = fi.count
                    fenceDepth = 0
                }
                continue
            }

            if inFence {
                fenceLines.append(line)
                continue
            }

            // --- Table buffering ---
            if isTableRow(line) || isSeparatorRow(trimmed) {
                tableBuffer.append(line)
                continue
            } else if !tableBuffer.isEmpty {
                flushTableBuffer()
            }

            // --- Block-level elements ---
            if let heading = renderHeading(line) {
                result.append(heading)
            } else if let blockquote = renderBlockquote(line) {
                result.append(blockquote)
            } else if let listItem = renderListItem(line) {
                result.append(listItem)
            } else if let divider = renderDivider(trimmed) {
                result.append(divider)
            } else if trimmed.isEmpty {
                result.append(border(""))
            } else {
                result.append(border(renderInline(line)))
            }
        }

        flushTableBuffer()

        // Unclosed fence — render what we have
        if inFence && !fenceLines.isEmpty {
            renderCodeBlock(fenceLines, language: fenceLang, into: &result)
        }

        return result.joined(separator: "\n") + "\n"
    }

    // MARK: - Code auto-detection

    /// Scan plain text for code-like patterns and wrap them in ``` fences
    /// so the rendering pipeline applies syntax highlighting.
    ///
    /// Only activates when the input has NO explicit ``` fences — if the LLM
    /// already used fences we trust the markdown structure. Detects:
    /// 1. Shebang lines (`#!/usr/bin/env ...`)
    /// 2. Indented blocks (4+ spaces or tab, 3+ lines)
    /// 3. Lines with high programming-keyword density
    private func autoDetectCodeBlocks(_ text: String) -> String {
        let rawLines = text.components(separatedBy: "\n")
        guard rawLines.count >= 3 else { return text }

        // If explicit ``` fences exist, trust the LLM's markdown structure
        let hasExplicitFences = rawLines.contains { line in
            parseFenceInfo(line.trimmingCharacters(in: .whitespaces)) != nil
        }
        guard !hasExplicitFences else { return text }

        // First pass: classify each line
        let lineKinds: [LineKind] = rawLines.map { classifyLine($0) }
        guard lineKinds.contains(.code) else { return text }

        // Second pass: merge adjacent code lines into blocks
        var blocks: [(start: Int, end: Int, kind: CodeBlockKind)] = []
        var i = 0
        while i < lineKinds.count {
            guard lineKinds[i] == .code else { i += 1; continue }

            let blockStart = i
            while i < lineKinds.count && lineKinds[i] == .code { i += 1 }
            let blockEnd = i - 1
            let lineCount = blockEnd - blockStart + 1

            // Only wrap substantial blocks (3+ lines)
            if lineCount >= 3 {
                let blockLines = Array(rawLines[blockStart...blockEnd])
                let kind = classifyBlock(blockLines)
                blocks.append((blockStart, blockEnd, kind))
            }
        }

        guard !blocks.isEmpty else { return text }

        // Third pass: build output with code blocks wrapped in fences
        var result = ""
        var pos = 0
        for block in blocks {
            // Text before this block
            while pos < block.start {
                result += rawLines[pos] + "\n"
                pos += 1
            }

            let blockLines = rawLines[block.start...block.end]
            let content = blockLines.joined(separator: "\n")

            // Dedent if indented code block
            let dedented: String
            if case .indented = block.kind {
                dedented = blockLines.map { stripCommonIndent($0) }.joined(separator: "\n")
            } else {
                dedented = content
            }

            let lang = detectLanguage(dedented)
            let fence = lang.map { "```\($0)" } ?? "```"
            result += fence + "\n" + dedented + "\n```\n"

            pos = block.end + 1
        }
        // Trailing text
        while pos < rawLines.count {
            result += rawLines[pos] + "\n"
            pos += 1
        }

        // Trim trailing newline to match original
        if result.hasSuffix("\n") && !text.hasSuffix("\n") {
            result = String(result.dropLast())
        }

        return result
    }

    private enum LineKind { case code, other }
    private enum CodeBlockKind { case indented, shebang, keyword }

    /// Classify a single line as code-like or not.
    private func classifyLine(_ line: String) -> LineKind {
        // Blank lines are neutral — they can appear inside code blocks
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .other }

        // Shebang — definitely code
        if trimmed.hasPrefix("#!/") { return .code }

        // Already-fenced code — don't double-process
        if parseFenceInfo(trimmed) != nil { return .other }

        // Markdown headers — not code
        if trimmed.firstMatch(of: #/^#{1,6}\s/#) != nil { return .other }

        // List items — not code
        if trimmed.firstMatch(of: #/^[-*]\s/#) != nil { return .other }

        // Blockquote — not code
        if trimmed.hasPrefix(">") { return .other }

        // Table rows — not code
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { return .other }

        // Horizontal rules — not code
        if trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 3 { return .other }
        if trimmed.allSatisfy({ $0 == "*" }) && trimmed.count >= 3 { return .other }
        if trimmed.allSatisfy({ $0 == "_" }) && trimmed.count >= 3 { return .other }

        // Indented with 4+ spaces or tab — indented code block pattern
        if line.hasPrefix("    ") || line.hasPrefix("\t") { return .code }

        // Keyword density: if a line has 2+ code keywords, it's likely code
        if codeKeywordDensity(trimmed) >= 2 { return .code }

        // Common code line patterns
        if looksLikeCodeLine(trimmed) { return .code }

        return .other
    }

    /// Classify a multi-line block for dedenting and language detection.
    private func classifyBlock(_ lines: [String]) -> CodeBlockKind {
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let first = nonEmpty.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("#!/") {
            return .shebang
        }
        // Check if all non-empty lines are indented
        let allIndented = nonEmpty.allSatisfy { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        if allIndented { return .indented }
        return .keyword
    }

    /// Strip common leading whitespace from an indented code line.
    private func stripCommonIndent(_ line: String) -> String {
        if line.hasPrefix("    ") {
            return String(line.dropFirst(4))
        }
        if line.hasPrefix("\t") {
            return String(line.dropFirst(1))
        }
        // Strip up to 4 leading spaces
        var count = 0
        for ch in line {
            if ch == " ", count < 4 { count += 1 }
            else { break }
        }
        return count > 0 ? String(line.dropFirst(count)) : line
    }

    /// Count programming keywords in a line (for density check).
    private func codeKeywordDensity(_ line: String) -> Int {
        // Non-capturing groups keep regex Output as Substring
        let codePatterns: [Regex<Substring>] = [
            #/\b(?:func|fn|def|function|class|struct|enum|interface|impl|trait|type|typedef|module|package|import|export|from|include|require|using|namespace)\b/#,
            #/\b(?:public|private|protected|static|final|abstract|virtual|override|const|let|var|int|string|bool|void|float|double|char|byte|long|short)\b/#,
            #/\b(?:return|yield|await|async|throw|raise|try|catch|except|finally|if|else|for|while|do|switch|case|break|continue|goto)\b/#,
            #/\b(?:new|delete|malloc|free|alloc|init|deinit|self|this|super|base)\b/#,
            #/\b(?:print|println|console[.]log|fmt[.]|printf|echo|write|read)\b/#,
            #/\b(?:http[.]|https[.]|fetch|axios|request|response|json[.]|JSON[.])\b/#,
            // CSS patterns
            #/@(?:media|import|font-face|keyframes|supports|container|layer|charset)\b/#,
            #/\b(?:color|display|margin|padding|border|width|height|font-size|background|position|flex|grid)\s*:\s*[^;]+\;/#,
        ]
        return codePatterns.reduce(0) { count, pattern in
            count + (line.contains(pattern) ? 1 : 0)
        }
    }

    /// Check if a line looks like a code statement (not prose).
    private func looksLikeCodeLine(_ line: String) -> Bool {
        // Function calls with chaining: foo().bar().baz()
        if line.contains(#/\w+\(.*\)\.\w+/#) { return true }

        // Semicolon at end (C-like languages)
        if line.hasSuffix(";") && line.count > 10 { return true }

        // Decorator/annotation: @Identifier (not email addresses with @ mid-text)
        if line.hasPrefix("@") && line.count > 3 && line.prefix(while: { $0 != " " }).count == line.count { return true }

        // Comment lines — only block-comment syntax, not CLI flags
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { return true }

        return false
    }

    /// Simple language detection from code content — checks the first few lines
    /// for language-specific patterns.
    private func detectLanguage(_ code: String) -> String? {
        let lines = code.components(separatedBy: "\n")
        let head = lines.prefix(10).joined(separator: "\n")

        // Shebang
        if head.contains("#!/usr/bin/env python") || head.contains("#!/usr/bin/python") { return "python" }
        if head.contains("#!/usr/bin/env node") || head.contains("#!/usr/bin/node") { return "javascript" }
        if head.contains("#!/usr/bin/env bash") || head.contains("#!/bin/bash") || head.contains("#!/bin/sh") { return "bash" }
        if head.contains("#!/usr/bin/env ruby") { return "ruby" }
        if head.contains("#!/usr/bin/env swift") { return "swift" }

        // Swift
        if head.contains(#/\b(import\s+(Foundation|SwiftUI|UIKit|AppKit))\b/#) { return "swift" }
        if head.contains(#/\b(func\s+\w+\s*\([^)]*\)\s*(->|throws|async))\b/#) { return "swift" }
        if head.contains(#/\b(struct\s+\w+\s*:\s*\w|class\s+\w+\s*:\s*\w)\b/#) { return "swift" }
        if head.contains(#/\b(guard\s+let|if\s+let|var\s+\w+\s*:\s*\w+|let\s+\w+\s*:\s*\w+)\b/#) { return "swift" }
        if head.contains(#/\b(\.forEach|\.map|\.filter|\.reduce|\.compactMap)\b/#) { return "swift" }

        // Python
        if head.contains(#/\b(import\s+\w+|from\s+\w+\s+import)\b/#) { return "python" }
        if head.contains(#/\b(def\s+\w+\s*\([^)]*\)\s*:)\b/#) { return "python" }
        if head.contains(#/\b(class\s+\w+\s*(\(|:)|if\s+__name__)\b/#) { return "python" }
        if head.contains(#/\b(print\(|self\.|\.format\(|f"[^"]*\{)\b/#) { return "python" }

        // JavaScript / TypeScript
        if head.contains(#/\b(const\s+\w+\s*=\s*(\(|function|=>|require)|let\s+\w+\s*=)\b/#) { return "javascript" }
        if head.contains(#/\b(import\s+.*\s+from\s+['"]|export\s+(default\s+)?(function|const|class))\b/#) { return "javascript" }
        if head.contains(#/\b(console\.log|document\.|window\.|\.then\(|async\s+\(|\.addEventListener)\b/#) { return "javascript" }
        if head.contains(#/\b(interface\s+\w+\s*\{|type\s+\w+\s*=)\b/#) { return "typescript" }

        // Rust
        if head.contains(#/\b(fn\s+\w+\s*\([^)]*\)\s*(->|where)|impl\s+\w+|use\s+\w+::)\b/#) { return "rust" }
        if head.contains(#/\b(let\s+mut\s+\w+|Vec<|Option<|Result<|\.unwrap\(|\.expect\()\b/#) { return "rust" }

        // Go
        if head.contains(#/\b(func\s+\w+\s*\([^)]*\)\s*\w*\{|package\s+main|go\s+func)\b/#) { return "go" }

        // Kotlin
        if head.contains(#/\b(fun\s+\w+\s*\([^)]*\)\s*:\s*\w+|val\s+\w+\s*:\s*\w+|var\s+\w+\s*:\s*\w+)\b/#) { return "kotlin" }

        // C/C++
        if head.contains(#/\b(#include\s*[<"]|int\s+main\s*\(|std::|printf\(|cout\s*<<)\b/#) { return "cpp" }

        // Java
        if head.contains(#/\b(public\s+class\s+\w+|public\s+static\s+void\s+main|System\.out\.)\b/#) { return "java" }

        // Ruby
        if head.contains(#/\b(def\s+\w+\s*$|\.each\s+do\s+\||require\s+['"]\w|attr_accessor)\b/#) { return "ruby" }

        // Shell
        if head.contains(#/\b(^#!/|if\s+\[\s|then\b|elif\b|fi\b|esac\b|done\b|local\s+\w+=)\b/#) { return "bash" }

        // SQL
        if head.contains(#/\b(SELECT\s+|FROM\s+|WHERE\s+|INSERT\s+INTO|CREATE\s+TABLE|ALTER\s+TABLE)\b/#) { return "sql" }

        // CSS
        if head.contains(#/\{[^}]*\b(?:color|display|margin|padding|font-size|width|height|background)\s*:\s*[^;]+\;?\s*\}/#) { return "css" }
        if head.contains(#/@(?:media|import|font-face|keyframes|supports|container|layer)\b/#) { return "css" }
        if head.contains(#/^\.[\w-]+\s*\{|^#[\w-]+\s*\{|^[\w-]+\s*\{/#) && head.contains(":") && head.contains(";") { return "css" }

        // YAML
        if head.contains(#/^\w+:\s*$/#) && lines.count >= 2 { return "yaml" }

        // JSON
        if head.hasPrefix("{") && head.contains(#/"\w+"\s*:/#) { return "json" }

        return nil
    }

    // MARK: - Code blocks (TermKit-style boxed)

    private func renderCodeBlock(_ lines: [String], language: String?, into result: inout [String]) {
        guard !lines.isEmpty else { return }

        // Recursively render markdown content as full markdown (tables, lists,
        // nested code blocks, etc.) instead of treating it as flat code text.
        if let lang = language, (lang.lowercased() == "markdown" || lang.lowercased() == "md") {
            let source = lines.joined(separator: "\n")
            let rendered = render(source)
            let renderedLines = rendered.components(separatedBy: "\n").filter { !$0.isEmpty }
            for rline in renderedLines {
                result.append(rline)
            }
            return
        }

        // Calculate inner width from the longest line (capped by terminal width)
        let maxContentLen = lines.map(TerminalDisplayWidth.width).max() ?? 0
        let innerWidth = min(max(maxContentLen, 8), max(0, capability.columns - 6))
        let langLabel = language.map { " \($0) " } ?? ""
        // Box border adds 4 columns ("│ " + " │"), so top/bottom need innerWidth + 2 dashes
        let dashCount = innerWidth + 2

        // Top border: ┌──────── lang ────────┐
        let topDashCount = max(0, dashCount - TerminalDisplayWidth.width(langLabel))
        let topBorder = "┌" + repeatChar("─", topDashCount) + langLabel + "┐"
        result.append(border(dim(topBorder)))

        // Try syntax highlighting via the generic engine
        let highlightedLines: [String]?
        if let syntaxHighlighter, let lang = language {
            let source = lines.joined(separator: "\n")
            if let tokens = syntaxHighlighter.highlight(source, language: lang) {
                let renderer = TokenANSIRenderer(theme: codeTheme, capability: capability)
                // Use line-balanced rendering so multi-line tokens (comments,
                // strings) don't leak ANSI codes across line boundaries.
                highlightedLines = renderer.renderLines(source, tokens: tokens)
            } else {
                highlightedLines = nil
            }
        } else {
            highlightedLines = nil
        }

        // Content lines
        if let hlLines = highlightedLines {
            let innerLeft = capability.color("│ ", color: theme.secondary, style: .dim)
            let innerRight = capability.color(" │", color: theme.secondary, style: .dim)
            for line in hlLines {
                let padded = padToVisibleWidth(line, width: innerWidth)
                result.append(border(innerLeft + padded + innerRight))
            }
        } else {
            for line in lines {
                let padded = padToVisibleWidth(line, width: innerWidth)
                result.append(border(dim("│ " + padded + " │")))
            }
        }

        // Bottom border: └──────────────────┘
        let bottom = "└" + repeatChar("─", dashCount) + "┘"
        result.append(border(dim(bottom)))
    }

    private func parseFenceInfo(_ trimmed: String) -> FenceInfo? {
        // Backtick fence: 3+ backticks
        if trimmed.hasPrefix("```") {
            let count = trimmed.prefix(while: { $0 == "`" }).count
            let rest = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
            return FenceInfo(count: count, delimiter: "`", language: rest.isEmpty ? nil : rest, isPureFence: rest.isEmpty)
        }
        // Tilde fence: 3+ tildes
        if trimmed.hasPrefix("~~~") {
            let count = trimmed.prefix(while: { $0 == "~" }).count
            let rest = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
            return FenceInfo(count: count, delimiter: "~", language: rest.isEmpty ? nil : rest, isPureFence: rest.isEmpty)
        }
        return nil
    }

    struct FenceInfo {
        let count: Int
        let delimiter: Character
        let language: String?
        let isPureFence: Bool
    }

    // MARK: - Headings (TermKit-style)

    private func renderHeading(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(#{1,6})\s+(.+)/#) else { return nil }
        let level = match.1.count
        let text = String(match.2)
        let styled = capability.color(text, color: headingColor(level), style: .bold)
        let prefix = border("")

        switch level {
        case 1:
            // H1: Overline + text + underline with ═
            let rule = repeatChar("═", text.count)
            return prefix + "\n" + border(dim(rule)) + "\n" + border(styled) + "\n" + border(dim(rule))
        case 2:
            // H2: Text + underline with ─
            let rule = repeatChar("─", text.count)
            return border(styled) + "\n" + border(dim(rule))
        case 3:
            // H3: Just bold + color, no underline
            return border(styled)
        default:
            // H4+: Bold only
            return border(bold(text))
        }
    }

    private func headingColor(_ level: Int) -> ANSIColor {
        switch level {
        case 1: .brightBlue
        case 2: .brightGreen
        case 3: .brightYellow
        default: .white
        }
    }

    // MARK: - Blockquote

    private func renderBlockquote(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^>\s?(.+)/#) else { return nil }
        let text = String(match.1)
        return border(dim("▎ ") + dim(renderInline(text)))
    }

    // MARK: - Divider (horizontal rule)

    private func renderDivider(_ trimmed: String) -> String? {
        let isDivider = trimmed.allSatisfy { $0 == "-" } && trimmed.count >= 3
                      || trimmed.allSatisfy { $0 == "*" } && trimmed.count >= 3
                      || trimmed.allSatisfy { $0 == "_" } && trimmed.count >= 3
        guard isDivider else { return nil }
        let width = max(0, capability.columns - 4)
        return border(dim(String(repeating: "─", count: width)))
    }

    // MARK: - List items

    private func renderListItem(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(\s*)[-*]\s+(.+)/#) else { return nil }
        let indent = String(repeating: " ", count: match.1.count)
        let text = String(match.2)
        return border(indent + capability.color("•", color: theme.secondary) + " " + renderInline(text))
    }

    // MARK: - Table rendering

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|")
    }

    private func isSeparatorRow(_ trimmed: String) -> Bool {
        // Separator: |---|:---:|---|  (only dashes, colons, pipes, spaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let inner = trimmed.dropFirst().dropLast()
        let allowed: Set<Character> = ["|", "-", ":", " "]
        return !inner.isEmpty && inner.allSatisfy { allowed.contains($0) }
    }

    private func renderTable(header: String, separator: String, rows: [String], into result: inout [String]) {
        let headerCols = parseColumns(header)
        let sepCols = parseColumns(separator)
        let dataCols = rows.map(parseColumns)

        guard !headerCols.isEmpty else { return }
        let colCount = headerCols.count

        // Calculate max width per column
        var colWidths = Array(repeating: 3, count: colCount) // minimum width
        for i in 0..<colCount {
            colWidths[i] = max(colWidths[i], TerminalDisplayWidth.width(headerCols[i]))
            for row in dataCols where i < row.count {
                colWidths[i] = max(colWidths[i], TerminalDisplayWidth.width(row[i]))
            }
        }

        // Alignments from separator row (default: left)
        var alignments = Array(repeating: TableAlignment.left, count: colCount)
        for i in 0..<min(colCount, sepCols.count) {
            let sep = sepCols[i].trimmingCharacters(in: .whitespaces)
            if sep.hasPrefix(":") && sep.hasSuffix(":") { alignments[i] = .center }
            else if sep.hasSuffix(":") { alignments[i] = .right }
            else { alignments[i] = .left }
        }

        // Render header — bold cells within dim borders (inner bold doesn't reset dim)
        let headerCells = headerCols.enumerated().map { i, col in
            innerBold(padCell(col, width: colWidths[i], alignment: .center))
        }
        result.append(border(dim("│ " + headerCells.joined(separator: " │ ") + " │")))

        // Separator line with box chars
        let sepLine = colWidths.map { repeatChar("─", $0 + 2) }.joined(separator: "┼")
        result.append(border(dim("├" + sepLine + "┤")))

        // Data rows
        for row in dataCols {
            let cells: [String]
            if row.count >= colCount {
                cells = row.enumerated().map { i, col -> String in
                    let width = colWidths[min(i, colWidths.count - 1)]
                    let align = alignments[min(i, alignments.count - 1)]
                    return padCell(col, width: width, alignment: align)
                }
            } else {
                // Pad missing columns
                var padded = [String]()
                for i in 0..<colCount {
                    let col = i < row.count ? row[i] : ""
                    padded.append(padCell(col, width: colWidths[i], alignment: alignments[i]))
                }
                cells = padded
            }
            result.append(border(dim("│ " + cells.joined(separator: " │ ") + " │")))
        }
    }

    private enum TableAlignment { case left, center, right }

    private func parseColumns(_ row: String) -> [String] {
        var cols = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // Drop leading empty and trailing empty from split (outer pipes)
        if let first = cols.first, first.trimmingCharacters(in: .whitespaces).isEmpty { cols.removeFirst() }
        if let last = cols.last, last.trimmingCharacters(in: .whitespaces).isEmpty { cols.removeLast() }
        return cols.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func padCell(_ text: String, width: Int, alignment: TableAlignment) -> String {
        let visibleWidth = TerminalDisplayWidth.width(text)
        switch alignment {
        case .left:
            return padToVisibleWidth(text, width: width)
        case .right:
            let pad = String(repeating: " ", count: max(0, width - visibleWidth))
            return pad + text
        case .center:
            let totalPad = max(0, width - visibleWidth)
            let leftPad = totalPad / 2
            let rightPad = totalPad - leftPad
            return String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad)
        }
    }

    private func padToVisibleWidth(_ text: String, width: Int) -> String {
        let pad = max(0, width - TerminalDisplayWidth.visibleWidth(text))
        return text + String(repeating: " ", count: pad)
    }

    // MARK: - Inline rendering

    private func renderInline(_ line: String) -> String {
        var result = line
        result = replaceLinks(result)
        result = replaceCodeSpans(result)
        result = replaceBold(result)
        result = replaceItalic(result)
        return result
    }

    /// Replace `code` with standout-styled text. Backtick content is literal.
    private func replaceCodeSpans(_ text: String) -> String {
        let pattern = #/`([^`]+)`/#
        return text.replacing(pattern) { match in
            inlineCode(String(match.1))
        }
    }

    /// Replace **bold** with ANSI bold.
    private func replaceBold(_ text: String) -> String {
        let pattern = #/\*\*(.+?)\*\*/#
        return text.replacing(pattern) { match in
            bold(String(match.1))
        }
    }

    /// Replace *italic* with ANSI italic. Bold processed first, so remaining *text* is italic.
    private func replaceItalic(_ text: String) -> String {
        let pattern = #/\*(.+?)\*/#
        return text.replacing(pattern) { match in
            italic(String(match.1))
        }
    }

    /// Replace [text](url) with underlined styled text.
    private func replaceLinks(_ text: String) -> String {
        let pattern = #/\[([^\]]+)\]\(([^)]+)\)/#
        return text.replacing(pattern) { match in
            let linkText = String(match.1)
            return capability.color(linkText, color: theme.secondary, style: .underline)
        }
    }

    // MARK: - ANSI helpers

    private func border(_ text: String) -> String {
        capability.color("│ ", color: theme.secondary) + text
    }

    private func bold(_ text: String) -> String {
        styled(text, style: .bold)
    }

    /// Bold that toggles bold on/off within a dim context.
    /// \033[22m resets intensity (both bold and dim), so we re-apply \033[2m after.
    private func innerBold(_ text: String) -> String {
        capability.supportsColor
            ? "\u{001B}[1m\(text)\u{001B}[22m\u{001B}[2m"
            : text
    }

    private func italic(_ text: String) -> String {
        styled(text, style: .italic)
    }

    private func dim(_ text: String) -> String {
        styled(text, style: .dim)
    }

    /// Inline code: bright-cyan on dim background for standout effect against normal text.
    private func inlineCode(_ text: String) -> String {
        capability.supportsColor
            ? "\u{001B}[100m\u{001B}[96m \(text) \u{001B}[0m"
            : "`\(text)`"
    }

    private func styled(_ text: String, style: ANIStyle) -> String {
        capability.supportsColor
            ? "\u{001B}[\(style.rawValue)m\(text)\u{001B}[0m"
            : text
    }

    private func repeatChar(_ ch: Character, _ count: Int) -> String {
        count > 0 ? String(repeating: ch, count: count) : ""
    }
}
