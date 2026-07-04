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
        case toolResult
        case usage
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
        case .toolCallCompleted(let id, let output, let isError):
            activeTools.removeValue(forKey: id)
            toolResultRecords.append((id, output.stringValue, isError))
            separate(next: .toolResult)
            renderToolResult(output: output, isError: isError)
        case .turnCompleted(let usage, _):
            guard activeTools.isEmpty else { return }
            separate(next: .usage)
            renderUsage(usage)
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
            print(ansi("\r\u{001B}[K  Thinking:\n", color: theme.dim), terminator: "")
        }
        print(ansi(newPart, color: theme.dim), terminator: "")
        fflush(stdout)
        accumulatedThinking = thinking
    }

    private func renderToolResult(output: ToolOutputValue, isError: Bool) {
        let raw = output.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(raw.prefix(500))
        let truncated = raw.count > 500 ? "…" : ""
        if isError {
            print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(snippet)\(truncated)")
        } else if !snippet.isEmpty {
            print("\r\u{001B}[K  \(ansi("✓", color: theme.success)) \(snippet)\(truncated)")
        }
        fflush(stdout)
    }

    private func renderUsage(_ usage: Usage?) {
        guard let usage = usage else { return }
        print(ansi("  ↳ Tokens: in=\(usage.inputTokens) out=\(usage.outputTokens)", color: theme.secondary))
    }

    private func renderError(_ error: AgentRuntimeError) {
        print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(error.localizedDescription)")
        fflush(stdout)
    }
}
