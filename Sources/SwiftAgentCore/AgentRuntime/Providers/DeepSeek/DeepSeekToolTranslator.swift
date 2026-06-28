import Foundation

/// Translates SessionToolDefinition values into DeepSeek wire format
/// for Anthropic-compatible, Chat Completions, and Responses API endpoints.
/// Pure-functional: no mutable state, no side effects.
struct DeepSeekToolTranslator: Sendable {

    /// Convert SessionToolDefinition to Chat Completions tool format.
    /// Delegates to the canonical OpenAIToolTranslator.
    static func translateChatCompletions(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        OpenAIToolTranslator.translateChatCompletions(tools)
    }

    /// Convert SessionToolDefinition to Responses API tool format.
    /// Delegates to the canonical OpenAIToolTranslator.
    static func translateResponses(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        OpenAIToolTranslator.translateResponses(tools)
    }

    /// Convert SessionToolDefinition array to Anthropic-format tool dicts.
    /// Delegates to the canonical AnthropicToolTranslator.
    static func translateAnthropicCompat(_ tools: [SessionToolDefinition]) -> [[String: Any]] {
        AnthropicToolTranslator.translate(tools)
    }

}
