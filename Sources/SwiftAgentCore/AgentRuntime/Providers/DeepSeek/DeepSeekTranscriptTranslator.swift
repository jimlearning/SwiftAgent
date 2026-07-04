import Foundation

/// Translates Transcript entries into DeepSeek wire format for
/// Anthropic-compatible, Chat Completions, and Responses API endpoints.
/// Pure-functional: no mutable state, no side effects. Independently testable.
struct DeepSeekTranscriptTranslator: Sendable {

    // MARK: - Anthropic-Compatible Translation

    /// Translate Transcript into Anthropic Messages API format for DeepSeek's
    /// Anthropic-compatible endpoint (/anthropic/v1/messages).
    ///
    /// Delegates to the canonical AnthropicTranscriptTranslator and post-processes:
    /// - Strips cache_control keys from content blocks (DeepSeek doesn't support prompt caching)
    /// - Strips empty signature from thinking blocks (DeepSeek returns signature:"" which
    ///   triggers server-side validation errors if included)
    ///
    /// - Returns: (messages, optional system prompt)
    static func translateAnthropicCompat(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> (messages: [[String: Any]], system: Any?) {
        let (messages, system) = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: systemPrompt)
        return (stripCacheControl(from: messages), stripCacheControl(from: system))
    }

    // MARK: - Chat Completions API

    /// Translate Transcript into Chat Completions `messages[]` format.
    /// Delegates to OpenAITranscriptTranslator.
    static func translateChatCompletions(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        OpenAITranscriptTranslator.translateChatCompletions(transcript, systemPrompt: systemPrompt)
    }

    // MARK: - Responses API

    /// Translate Transcript into Responses API input items.
    /// Delegates to OpenAITranscriptTranslator — the Responses format is
    /// provider-agnostic.
    static func translateResponses(
        _ transcript: Transcript,
        systemPrompt: String?
    ) -> [[String: Any]] {
        OpenAITranscriptTranslator.translateResponses(transcript, systemPrompt: systemPrompt)
    }

    // MARK: - Post-Processing

    /// Strip DeepSeek-incompatible keys from Anthropic-format messages:
    /// - Removes `cache_control` from all content blocks (DeepSeek doesn't support prompt caching)
    /// - Removes empty-string `signature` from thinking blocks (causes server-side validation errors)
    private static func stripCacheControl(from messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { msg -> [String: Any] in
            var stripped = msg
            if let blocks = msg["content"] as? [[String: Any]] {
                stripped["content"] = blocks.map(stripBlock)
            }
            return stripped
        }
    }

    /// Strip DeepSeek-incompatible keys from the system parameter.
    /// Handles both plain String and array-of-blocks formats.
    private static func stripCacheControl(from system: Any?) -> Any? {
        guard let system else { return nil }
        if let blocks = system as? [[String: Any]] {
            return blocks.map(stripBlock)
        }
        return system // plain string, no cache_control to strip
    }

    /// Strip cache_control from a single content block.
    /// Note: thinking signatures are preserved as-is (even empty ones).
    /// DeepSeek V4 requires the signature key to be present in re-prompts.
    private static func stripBlock(_ block: [String: Any]) -> [String: Any] {
        var stripped = block
        stripped.removeValue(forKey: "cache_control")
        return stripped
    }

}
