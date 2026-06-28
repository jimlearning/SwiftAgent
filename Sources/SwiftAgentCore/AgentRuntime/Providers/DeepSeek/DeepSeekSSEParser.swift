import Foundation

/// Parses DeepSeek SSE (Server-Sent Events) for the Anthropic-compatible mode
/// and emits SessionEvent values through a GenerationChannel.
///
/// Parse mode:
/// - AnthropicCompat: Same event types as AnthropicSSEParser (content_block_delta,
///   content_block_start/stop, message_delta, message_stop, error).
///
/// Snapshot semantics REQUIRED: accumulate text/thinking internally,
/// send FULL accumulated string each time (PITFALLS.md Pitfall 2).
struct DeepSeekSSEParser {

    // MARK: - Public Entry Point

    /// Parse SSE lines and emit SessionEvent values through the channel.
    func parse<S: AsyncSequence>(
        lines: S,
        channel: GenerationChannel
    ) async throws where S.Element == String {
        let parser = AnthropicSSEParser()
        try await parser.parse(lines: lines, channel: channel)
    }
}
