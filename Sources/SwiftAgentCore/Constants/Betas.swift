import Foundation

/// Beta feature headers matching Claude Code's constants/betas.ts.
/// These are sent as `anthropic-beta` headers to enable experimental features.
public enum Betas {
    /// Core Claude Code beta
    public static let claudeCode20250219 = "claude-code-20250219"
    /// Extended thinking with streaming
    public static let interleavedThinking = "interleaved-thinking-2025-05-14"
    /// 1M token context window
    public static let context1M = "context-1m-2025-08-07"
    /// Context management
    public static let contextManagement = "context-management-2025-06-27"
    /// Structured output mode
    public static let structuredOutputs = "structured-outputs-2025-12-15"
    /// Web search tool
    public static let webSearch = "web-search-2025-03-05"
    /// Tool search — Claude API / Foundry
    public static let toolSearch1P = "advanced-tool-use-2025-11-20"
    /// Tool search — Vertex AI / Bedrock
    public static let toolSearch3P = "tool-search-tool-2025-10-19"
    /// Effort level overrides
    public static let effort = "effort-2025-11-24"
    /// Task budget limits
    public static let taskBudgets = "task-budgets-2026-03-13"
    /// Prompt caching scope
    public static let promptCachingScope = "prompt-caching-scope-2026-01-05"
    /// Fast mode
    public static let fastMode = "fast-mode-2026-02-01"
    /// Redacted thinking
    public static let redactThinking = "redact-thinking-2026-02-12"
    /// Token-efficient tools
    public static let tokenEfficientTools = "token-efficient-tools-2026-03-28"
    /// Advisor tool
    public static let advisor = "advisor-tool-2026-03-01"

    /// CC: feature('CONNECTOR_TEXT') ? 'summarize-connector-text-2026-03-13' : ''
    public static var summarizeConnectorText: String {
        FeatureFlags.isChannelsActive() ? "summarize-connector-text-2026-03-13" : ""
    }

    /// CC: feature('TRANSCRIPT_CLASSIFIER') ? 'afk-mode-2026-01-31' : ''
    public static var afkMode: String {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" ? "afk-mode-2026-01-31" : ""
    }

    /// CC: process.env.USER_TYPE === 'ant' ? 'cli-internal-2026-02-09' : ''
    public static var cliInternal: String {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" ? "cli-internal-2026-02-09" : ""
    }

    /// Bedrock-only beta headers (must go through extraBodyParams, not headers).
    public static let bedrockExtraParamsHeaders: Set<String> = [
        interleavedThinking,
        context1M,
        toolSearch3P,
    ]

    /// Vertex countTokens allowed betas (other betas cause 400 errors).
    public static let vertexCountTokensAllowedBetas: Set<String> = [
        claudeCode20250219,
        interleavedThinking,
        contextManagement,
    ]

    /// All active beta headers combined into a single string for the API request.
    public static var allActiveHeaders: [String] {
        [
            claudeCode20250219,
            interleavedThinking,
            context1M,
            contextManagement,
            structuredOutputs,
            webSearch,
            toolSearch1P,
            effort,
            taskBudgets,
            promptCachingScope,
            fastMode,
            redactThinking,
            tokenEfficientTools,
            advisor,
        ] + [summarizeConnectorText, afkMode, cliInternal].filter { !$0.isEmpty }
    }

    /// Betas observed in Claude Code prompt-gateway requests for coding chat.
    public static var claudeCodeRequestHeaders: [String] {
        [
            claudeCode20250219,
            interleavedThinking,
            redactThinking,
            contextManagement,
            promptCachingScope,
            advisor,
            toolSearch1P,
            effort,
        ]
    }
}
