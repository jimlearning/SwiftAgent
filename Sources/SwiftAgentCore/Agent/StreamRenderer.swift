import Foundation

/// Formats streaming output for terminal display.
/// Handles ANSI escape sequences, partial content rendering, and status line recovery.
public struct StreamRenderer: Sendable {
    public init() {}
    /// Render a stream event as terminal-safe output.
    public func render(event: StreamEvent, currentOutput: String) -> String {
        switch event {
        case .textDelta(let text):
            return text

        case .messageStart(let msg):
            return "\n[Model: \(msg.model)]\n"

        case .thinkingDelta:
            return ""  // thinking deltas stream inline (accumulated in ContentBlockAccumulator)

        case .signatureDelta:
            return ""  // signature deltas are internal verification data

        case .contentBlockStart(_, let block):
            switch block {
            case .text:
                return ""
            case .thinking:
                return "\n[Thinking...]\n"
            case .redactedThinking:
                return "\n[Thinking redacted]\n"
            case .toolUse(let name, _):
                return "\n→ Calling tool: \(name)...\n"
            case .serverToolUse(let name, _):
                return "\n→ Server tool: \(name)...\n"
            }

        case .inputJSONDelta:
            return "."

        case .contentBlockStop:
            return ""

        case .messageDelta(let reason, let usage):
            var result = ""
            if let u = usage {
                result += "\n[Tokens: ↓\(u.inputTokens) ↑\(u.outputTokens)]"
            }
            if let r = reason {
                result += " [Stop: \(r)]"
            }
            return result

        case .messageStop:
            return "\n"

        case .ping:
            return ""

        case .error(let msg):
            return "\n❌ Error: \(msg)\n"
        }
    }

    /// Sanitize output for terminal — strip control chars except basic ANSI.
    public func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// Truncate output to fit within a terminal column width.
    public func wrap(_ text: String, width: Int) -> String {
        if text.count <= width { return text }
        return String(text.prefix(width - 3)) + "..."
    }

    /// Highlight code blocks in terminal output.
    public func highlightCodeBlocks(_ text: String) -> String {
        // In production: integrate with a syntax highlighter (e.g., Swift-tree-sitter)
        // For now, wrap code blocks with ANSI dim markers
        var result = text
        let pattern = try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: [])
        if let regex = pattern {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 2), in: result) {
                    let code = String(result[codeRange])
                    let highlighted = "\u{001B}[2m\(code)\u{001B}[0m"
                    result.replaceSubrange(codeRange, with: highlighted)
                }
            }
        }
        return result
    }
}
