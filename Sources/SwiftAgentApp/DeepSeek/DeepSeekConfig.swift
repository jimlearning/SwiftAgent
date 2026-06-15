import Foundation

/// DeepSeek API configuration.
/// API key is loaded from Keychain (or DEEPSEEK_API_KEY env var fallback).
public struct DeepSeekConfig: Sendable {
    /// Base URL for the DeepSeek API (OpenAI-compatible).
    public let baseURL: URL

    /// API key for authentication. Never logged or displayed.
    public let apiKey: String

    /// Default model to use when none specified.
    public let defaultModel: DeepSeekModel

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com/v1")!,
        apiKey: String,
        defaultModel: DeepSeekModel = .v3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.defaultModel = defaultModel
    }
}
