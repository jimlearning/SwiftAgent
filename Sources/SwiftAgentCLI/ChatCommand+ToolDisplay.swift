import Foundation
import SwiftAgentCore

extension ChatCommand {
    // MARK: - Tool result display

    /// Format a tool result as a user-visible summary showing the full command
    /// and at least 3 lines of output before truncation.
    func toolResultSummary(
        name: String,
        input: [String: JSONValue],
        output: String,
        capability: TerminalCapability
    ) -> String {
        let nameColor = capability.color("  \(name)", color: .brightCyan)
        let dim = capability.color(" → ", color: .brightBlack)
        let cmdStr = formatToolCommand(name: name, input: input, capability: capability)

        var lines: [String] = [nameColor + dim + cmdStr]

        let outputLines = output.components(separatedBy: "\n")
        let maxPreview = 3
        let previewCount = min(outputLines.count, maxPreview)

        for i in 0..<previewCount {
            var line = outputLines[i]
            if line.count > 200 {
                line = String(line.prefix(200)) + "..."
            }
            lines.append(capability.color("    \(line)", color: .brightBlack))
        }

        let remaining = outputLines.count - previewCount
        if remaining > 0 {
            lines.append(capability.color(
                "    ... \(remaining) more line\(remaining == 1 ? "" : "s") (\(output.count) total chars)",
                color: .brightBlack
            ))
        }

        return lines.joined(separator: "\n")
    }

    /// Format a tool's input as a readable command string, showing the most
    /// relevant parameter for each tool type.
    func formatToolCommand(name: String, input: [String: JSONValue], capability: TerminalCapability) -> String {
        switch name {
        case "Bash":
            if case .string(let cmd) = input["command"] { return cmd }

        case "Read":
            if case .string(let path) = input["file_path"] { return path }

        case "Write":
            if case .string(let path) = input["file_path"] { return path }

        case "Edit":
            if case .string(let path) = input["file_path"] { return path }

        case "Glob":
            if case .string(let pattern) = input["pattern"] { return pattern }

        case "Grep":
            var parts: [String] = []
            if case .string(let pattern) = input["pattern"] { parts.append(pattern) }
            if case .string(let path) = input["path"] { parts.append("in \(path)") }
            if !parts.isEmpty { return parts.joined(separator: " ") }

        case "Agent":
            if case .string(let desc) = input["description"] { return desc }

        case "TaskCreate":
            if case .string(let subject) = input["subject"] { return subject }

        case "WebFetch":
            if case .string(let url) = input["url"] { return url }

        case "WebSearch":
            if case .string(let query) = input["query"] { return query }

        default:
            break
        }

        return formatGenericInput(input)
    }

    /// Compact formatting for tools without a dedicated command formatter.
    func formatGenericInput(_ input: [String: JSONValue]) -> String {
        let parts = input.compactMap { key, value -> String? in
            let valStr: String
            switch value {
            case .string(let s): valStr = s
            case .number(let n): valStr = String(format: "%g", n)
            case .bool(let b): valStr = b ? "true" : "false"
            case .null: return nil
            case .array: valStr = "[...]"
            case .object: valStr = "{...}"
            }
            if valStr.count > 80 { return "\(key): ..." }
            return "\(key): \(valStr)"
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }

    /// Handles Ctrl+O: pure toggle — collapse if something is expanded,
    /// expand the last stored group if nothing is.
    /// - Returns: true if something was expanded or collapsed; false if no-op.
    func handleCtrlO(
        cache: ToolResultCache,
        capability: TerminalCapability
    ) async -> Bool {
        if expandState.expandedGroupIndex != nil {
            collapseExpandedOutput()
            return true
        }
        guard let idx = await cache.lastIndex() else { return false }
        let expanded = await expandCollapsedResult(
            arg: "last", cache: cache, capability: capability,
            clearLinesAbove: 1
        )
        expandState.expandedLineCount = expanded.components(separatedBy: "\n").count + 1
        emitBlock(expanded)
        expandState.expandedGroupIndex = idx
        return true
    }

    /// Removes the expanded output block from the terminal using ANSI escape codes.
    func collapseExpandedOutput() {
        guard expandState.expandedLineCount > 0 else { return }
        let n = expandState.expandedLineCount
        writeToStdout("\u{001B}[\(n + 1)A")
        writeToStdout("\u{001B}[0J")
        expandState.expandedGroupIndex = nil
        expandState.expandedLineCount = 0
    }

    /// Expand a previously collapsed tool result group identified by
    /// an index number or the keyword "last".
    func expandCollapsedResult(
        arg: String,
        cache: ToolResultCache,
        capability: TerminalCapability,
        clearLinesAbove: Int = 0
    ) async -> String {
        let prefix = clearLinesAbove > 0 ? "\u{001B}[\(clearLinesAbove)A\u{001B}[0J" : ""
        let stored: StoredGroup?
        if arg == "last" {
            stored = await cache.last()
        } else if let idx = Int(arg) {
            stored = await cache.get(idx)
        } else {
            return prefix + "Usage: /expand <N> or /expand last"
        }

        guard let stored = stored else {
            return prefix + "No collapsed result found for \"\(arg)\"."
        }

        var output = capability.color(
            "── Expanded group [#\(stored.index)] (\(stored.results.count) tool\(stored.results.count == 1 ? "" : "s")) ──",
            color: .brightBlack
        ) + "\n"

        for result in stored.results {
            let nameColor = capability.color("  \(result.name)", color: .brightCyan)
            let cmd = CollapseDetector.commandSummary(
                name: result.name, input: result.input
            )
            output += nameColor + " → " + cmd + "\n"
            output += capability.color(
                "  " + String(repeating: "─", count: min(capability.columns - 4, 60)),
                color: .brightBlack
            ) + "\n"

            let resultOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if resultOutput.isEmpty {
                output += capability.color("  (empty)", color: .brightBlack) + "\n"
            } else {
                let lines = resultOutput.components(separatedBy: "\n")
                let showAll = lines.count <= 50
                for (_, line) in lines.prefix(50).enumerated() {
                    let trimmed = line.count > 200 ? String(line.prefix(200)) + "…" : line
                    output += capability.color("  \(trimmed)", color: .brightBlack) + "\n"
                }
                if !showAll {
                    output += capability.color(
                        "  … \(lines.count - 50) more lines",
                        color: .brightBlack
                    ) + "\n"
                }
            }
            output += "\n"
        }

        return prefix + output
    }
}
