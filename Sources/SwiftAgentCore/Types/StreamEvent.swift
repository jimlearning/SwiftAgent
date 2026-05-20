public enum StreamEvent: Sendable {
    case messageStart(message: StreamMessageStart)
    case contentBlockStart(index: Int, block: StreamContentBlockStart)
    case textDelta(text: String)
    case thinkingDelta(text: String)
    case signatureDelta(text: String)
    case inputJSONDelta(delta: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: Usage?)
    case messageStop
    case ping
    case error(String)
}

public struct StreamMessageStart: Sendable {
    public let model: String
    public let messageID: String
    public let usage: Usage?

    public init(model: String, messageID: String, usage: Usage? = nil) {
        self.model = model
        self.messageID = messageID
        self.usage = usage
    }
}

public enum StreamContentBlockStart: Sendable {
    case text
    case thinking
    case redactedThinking
    case toolUse(name: String, id: String)
    /// Server-side tool use (advisor/MCP server-initiated).
    /// Matches CC's server_tool_use content block.
    case serverToolUse(name: String, id: String)
}

/// Token usage matching Claude Code's NonNullableUsage / BetaUsage.
public struct Usage: Codable, Sendable {
    public var inputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int
    public var outputTokens: Int
    public var cacheDeletedInputTokens: Int
    public var serverToolUse: ServerToolUse?
    public var serviceTier: String?
    public var cacheCreation: CacheCreation?
    public var inferenceGeo: String?
    public var iterations: [UsageIteration]?
    public var speed: String?
    public var costUSD: Double?
    public var contextWindow: Int?
    public var maxOutputTokens: Int?

    public struct ServerToolUse: Codable, Sendable {
        public var webSearchRequests: Int
        public var webFetchRequests: Int

        public init(webSearchRequests: Int = 0, webFetchRequests: Int = 0) {
            self.webSearchRequests = webSearchRequests
            self.webFetchRequests = webFetchRequests
        }
    }

    public struct CacheCreation: Codable, Sendable {
        public var ephemeral1hInputTokens: Int
        public var ephemeral5mInputTokens: Int

        public init(ephemeral1hInputTokens: Int = 0, ephemeral5mInputTokens: Int = 0) {
            self.ephemeral1hInputTokens = ephemeral1hInputTokens
            self.ephemeral5mInputTokens = ephemeral5mInputTokens
        }
    }

    public struct UsageIteration: Codable, Sendable {
        public var inputTokens: Int
        public var outputTokens: Int

        public init(inputTokens: Int = 0, outputTokens: Int = 0) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public init(
        inputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        cacheDeletedInputTokens: Int = 0,
        outputTokens: Int = 0,
        serverToolUse: ServerToolUse? = nil,
        serviceTier: String? = nil,
        cacheCreation: CacheCreation? = nil,
        inferenceGeo: String? = nil,
        iterations: [UsageIteration]? = nil,
        speed: String? = nil,
        costUSD: Double? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheDeletedInputTokens = cacheDeletedInputTokens
        self.outputTokens = outputTokens
        self.serverToolUse = serverToolUse
        self.serviceTier = serviceTier
        self.cacheCreation = cacheCreation
        self.inferenceGeo = inferenceGeo
        self.iterations = iterations
        self.speed = speed
        self.costUSD = costUSD
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }

    /// Zero-initialized usage matching CC's EMPTY_USAGE.
    public static let empty: Usage = Usage()

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheDeletedInputTokens = "cache_deleted_input_tokens"
        case outputTokens = "output_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
        case cacheCreation = "cache_creation"
        case inferenceGeo = "inference_geo"
        case iterations
        case speed
        case costUSD = "cost_usd"
        case contextWindow = "context_window"
        case maxOutputTokens = "max_output_tokens"
    }
}
