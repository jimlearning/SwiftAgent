import Foundation

/// Controls which DeepSeek API endpoint the provider targets.
///
/// DeepSeek supports two wire formats:
/// - Anthropic-compatible: POST /anthropic/v1/messages (same shape as Anthropic Messages API)
/// - OpenAI-compatible:    POST /v1/chat/completions (Chat Completions format)
///
/// When DeepSeek adds Responses API support, switch `endpointPath` to `/v1/responses`
/// and use the Responses API translators/parser instead of Chat Completions.
public enum APICompatibility: Sendable {
    case anthropicCompatible
    case openAICompatible

    var endpointPath: String {
        switch self {
        case .anthropicCompatible:
            return "/anthropic/v1/messages"
        case .openAICompatible:
            return "/v1/chat/completions"
        }
    }

    var defaultBaseURL: URL {
        URL(string: "https://api.deepseek.com")!
    }
}
