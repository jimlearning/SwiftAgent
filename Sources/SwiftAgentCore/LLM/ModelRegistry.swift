/// Registry of known Claude models with capabilities.
public struct ModelRegistry: Sendable {
    public static let shared = ModelRegistry()

    public let models: [String: ModelInfo]

    public init() {
        self.models = [
            "claude-haiku-4-5": ModelInfo(
                id: "claude-haiku-4-5",
                displayName: "Claude Haiku 4.5",
                contextWindow: 200_000,
                maxOutput: 4096,
                supportsStreaming: true,
                supportsToolUse: true,
                supportsThinking: false
            ),
            "claude-sonnet-4-6": ModelInfo(
                id: "claude-sonnet-4-6",
                displayName: "Claude Sonnet 4.6",
                contextWindow: 200_000,
                maxOutput: 8192,
                supportsStreaming: true,
                supportsToolUse: true,
                supportsThinking: true
            ),
            "claude-opus-4-7": ModelInfo(
                id: "claude-opus-4-7",
                displayName: "Claude Opus 4.7",
                contextWindow: 200_000,
                maxOutput: 16384,
                supportsStreaming: true,
                supportsToolUse: true,
                supportsThinking: true
            ),
        ]
    }

    /// Model aliases matching Claude Code's model resolution (e.g. "sonnet" → "claude-sonnet-4-6").
    public static let modelAliases: [String: String] = [
        "sonnet": "claude-sonnet-4-6",
        "opus": "claude-opus-4-7",
        "haiku": "claude-haiku-4-5",
        "default": "claude-sonnet-4-6",
    ]

    /// Resolve a model ID through aliases, returning the canonical model ID.
    public func resolveModel(_ modelID: String, overrides: [String: String]? = nil) -> String {
        // Apply user/project modelOverrides first
        if let overrides = overrides, let overridden = overrides[modelID] {
            return overridden
        }
        // Resolve known aliases
        if let aliased = Self.modelAliases[modelID] {
            return aliased
        }
        return modelID
    }

    public func info(for modelID: String) -> ModelInfo? {
        models[resolveModel(modelID)]
    }

    public var defaultModel: String { "claude-sonnet-4-6" }

    public func effectiveContextWindow(for modelID: String) -> Int {
        let window = info(for: modelID)?.contextWindow ?? 200_000
        return window - 20_000  // reserve for output
    }
}

public struct ModelInfo: Sendable {
    public let id: String
    public let displayName: String
    public let contextWindow: Int
    public let maxOutput: Int
    public let supportsStreaming: Bool
    public let supportsToolUse: Bool
    public let supportsThinking: Bool
}
