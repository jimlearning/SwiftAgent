import Foundation
import SwiftAgentCore

/// Renders SessionEvent stream values from LanguageModelSessionImpl.streamResponse(to:) into
/// terminal output. Replaces the deleted StatusLine, ChatToolInputAccumulator,
/// ChatToolExecutionScheduler, and Agent/StreamRenderer.
///
/// SessionEvent uses snapshot semantics — each textDelta/thinkingDelta carries the
/// FULL accumulated value, not incremental additions. This renderer tracks the
/// previous snapshot and only prints new content, avoiding double-rendering.
public struct SessionEventRenderer {
    private let terminal: TerminalRenderer
    private let theme: ColorTheme
    private let showThinking: Bool

    /// Accumulated response text (snapshots replace, not append).
    private(set) public var accumulatedText: String = ""
    /// Accumulated thinking text.
    private(set) public var accumulatedThinking: String = ""
    /// Active tool calls keyed by id. Value is the PascalCase tool name.
    private var activeTools: [String: String] = [:]

    /// Recorded tool calls (for JSONL transcript logging).
    private(set) public var toolCallRecords: [(id: String, name: String, input: Data)] = []
    /// Recorded tool results (for JSONL transcript logging).
    private(set) public var toolResultRecords: [(id: String, output: String, isError: Bool)] = []

    /// Tracks the last visible block type to insert blank-line separators
    /// between different block categories.
    private enum BlockType {
        case none
        case thinking
        case text
        case toolCall
        case toolResult
        case error
    }
    private var lastBlockType: BlockType = .none

    public init(
        terminal: TerminalRenderer,
        theme: ColorTheme,
        showThinking: Bool
    ) {
        self.terminal = terminal
        self.theme = theme
        self.showThinking = showThinking
    }

    // MARK: - Render

    public mutating func render(_ event: SessionEvent) {
        switch event {
        case .textDelta(let text):
            renderText(text)
        case .thinkingDelta(let thinking):
            if showThinking {
                separate(next: .thinking)
            }
            renderThinking(thinking)
        case .toolCallRequested(let id, let name, let input):
            activeTools[id] = name
            toolCallRecords.append((id, name, input))
            separate(next: .toolCall)
            renderToolCall(name: name, input: input)
        case .toolCallCompleted(let id, let output, let isError):
            activeTools.removeValue(forKey: id)
            toolResultRecords.append((id, output.stringValue, isError))
            // toolCall → toolResult is a visual pair: no blank line between them
            if lastBlockType != .toolCall {
                separate(next: .toolResult)
            } else {
                lastBlockType = .toolResult
            }
            renderToolResult(output: output, isError: isError)
        case .turnCompleted:
            guard activeTools.isEmpty else { return }
        case .error(let err):
            separate(next: .error)
            renderError(err)
        }
    }

    /// Name of the currently-executing tool, for spinner display.
    public var activeToolName: String? { activeTools.values.first }
    public var hasActiveTools: Bool { !activeTools.isEmpty }

    // MARK: - Private

    /// Emit a blank line when transitioning between different visible block types.
    /// Thinking output ends mid-line (no trailing newline), so transitions away
    /// from thinking need an extra newline to terminate the thinking line first.
    private mutating func separate(next: BlockType) {
        if lastBlockType != .none && lastBlockType != next {
            if lastBlockType == .thinking {
                print("\n")
            } else {
                print("")
            }
        }
        lastBlockType = next
    }

    private mutating func renderText(_ text: String) {
        guard text.count > accumulatedText.count else { return }
        accumulatedText = text
        if !activeTools.isEmpty {
            activeTools.removeAll()
        }
        // Text is NOT printed during streaming — it would duplicate the
        // post-turn markdown + border render. The accumulated text is
        // rendered once after the turn completes.
    }

    private mutating func renderThinking(_ thinking: String) {
        guard showThinking else {
            accumulatedThinking = thinking
            return
        }
        // Detect a new thinking block (different API call iteration).
        // Snapshots from a new iteration start short; if the incoming
        // snapshot is shorter than our accumulated value, or doesn't
        // share the same prefix, it's a fresh block.
        if thinking.count < accumulatedThinking.count
            || !thinking.hasPrefix(accumulatedThinking) {
            accumulatedThinking = ""
        }
        guard thinking.count > accumulatedThinking.count else { return }
        let newPart = String(thinking.dropFirst(accumulatedThinking.count))
        if accumulatedThinking.isEmpty {
            // CC format: ∴ Thinking… + blank line (gap={1}) + indented content.
            // The 2-space indent is a line prefix, not a per-chunk prefix.
            print(ansi("\r\u{001B}[K\u{2234} Thinking\u{2026}\n", color: theme.dim), terminator: "")
            print("")
            print(ansi("  ", color: theme.dim), terminator: "")
        }
        print(ansi(newPart, color: theme.dim), terminator: "")
        fflush(stdout)
        accumulatedThinking = thinking
    }

    // MARK: - Tool call display

    /// CC-aligned tool call prefix: `⏺` (U+23FA, black circle for record).
    private static let toolCallPrefix = "\u{23FA} "
    /// CC-aligned tool result prefix: `  ⎿  ` (U+23BF).
    private static let toolResultPrefix = "  \u{23BF}  "

    /// Display a tool call in CC format: `⏺ ToolName(summary)`.
    private func renderToolCall(name: String, input: Data) {
        let summary = Self.extractToolSummary(from: input)
        let line: String
        if let summary = summary {
            line = "\r\u{001B}[K\(Self.toolCallPrefix)\(name)(\(summary))"
        } else {
            line = "\r\u{001B}[K\(Self.toolCallPrefix)\(name)"
        }
        print(ansi(line, color: theme.secondary))
        fflush(stdout)
    }

    /// Extract a human-readable summary from tool input JSON.
    /// Looks for the tool's primary argument: command, file_path, pattern, query, etc.
    private static func extractToolSummary(from input: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            return nil
        }
        // Primary keys in priority order — the value that best describes what the tool does
        let primaryKeys = ["command", "file_path", "pattern", "query", "old_string", "new_string", "content", "name", "description"]
        for key in primaryKeys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        // Fallback: first non-empty string value
        for (_, value) in json {
            if let str = value as? String, !str.isEmpty {
                return str
            }
        }
        return nil
    }

    /// Display a tool result in CC format:
    /// ```
    ///   ⎿  first line
    ///      subsequent lines (5-space indent aligns with text after ⎿  )
    /// ```
    private func renderToolResult(output: ToolOutputValue, isError: Bool) {
        let raw = output.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = raw.components(separatedBy: "\n")

        if isError {
            let first = lines.first ?? ""
            let snippet = String(first.prefix(500))
            let truncated = first.count > 500 ? "…" : ""
            print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(snippet)\(truncated)")
            for line in lines.dropFirst() {
                print("     \(line)")
            }
        } else if !raw.isEmpty {
            let first = lines.first ?? ""
            print(ansi("\r\u{001B}[K\(Self.toolResultPrefix)\(first)", color: theme.secondary))
            for line in lines.dropFirst() {
                print(ansi("     \(line)", color: theme.secondary))
            }
        }
        fflush(stdout)
    }

    private func renderError(_ error: AgentRuntimeError) {
        print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(error.localizedDescription)")
        fflush(stdout)
    }
}
