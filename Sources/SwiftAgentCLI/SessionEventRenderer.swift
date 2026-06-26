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
            renderThinking(thinking)
        case .toolCallRequested(let id, let name, _):
            activeTools[id] = name
        case .toolCallCompleted(let id, let output, let isError):
            activeTools.removeValue(forKey: id)
            renderToolResult(output: output, isError: isError)
        case .turnCompleted(let usage, _):
            renderUsage(usage)
        case .error(let err):
            renderError(err)
        }
    }

    /// Name of the currently-executing tool, for spinner display.
    public var activeToolName: String? { activeTools.values.first }
    public var hasActiveTools: Bool { !activeTools.isEmpty }

    // MARK: - Private

    private mutating func renderText(_ text: String) {
        guard text.count > accumulatedText.count else { return }
        let newPart = String(text.dropFirst(accumulatedText.count))
        accumulatedText = text
        if !activeTools.isEmpty {
            activeTools.removeAll()
        }
        print(newPart, terminator: "")
        fflush(stdout)
    }

    private mutating func renderThinking(_ thinking: String) {
        guard showThinking else { return }
        guard thinking.count > accumulatedThinking.count else { return }
        let newPart = String(thinking.dropFirst(accumulatedThinking.count))
        if accumulatedThinking.isEmpty {
            print("\r\u{001B}[K  ", terminator: "")
        }
        print(ansi(newPart, color: theme.dim), terminator: "")
        fflush(stdout)
        accumulatedThinking = thinking
    }

    private func renderToolResult(output: ToolOutputValue, isError: Bool) {
        let snippet = output.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        if isError {
            print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(snippet)")
        } else if !snippet.isEmpty {
            print("\r\u{001B}[K  \(ansi("✓", color: theme.success)) \(snippet)")
        }
        fflush(stdout)
    }

    private func renderUsage(_ usage: Usage?) {
        guard let usage = usage else { return }
        print(ansi("  ↳ Tokens: in=\(usage.inputTokens) out=\(usage.outputTokens)", color: theme.dim))
    }

    private func renderError(_ error: AgentRuntimeError) {
        print("\r\u{001B}[K  \(ansi("✗", color: theme.error)) \(error.localizedDescription)")
        fflush(stdout)
    }
}
