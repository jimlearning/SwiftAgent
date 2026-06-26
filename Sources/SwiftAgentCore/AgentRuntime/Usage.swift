import Foundation

/// Token usage metadata matching Claude Code's NonNullableUsage / BetaUsage.
/// Used by SessionEvent, Response, and provider SSE parsers.
public struct Usage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int
    public var outputTokens: Int
    public var serverToolUse: ServerToolUse?
    public var serviceTier: String?
    public var cacheCreation: CacheCreation?
    public var inferenceGeo: String?
    public var iterations: [UsageIteration]?
    public var speed: String?
    public var costUSD: Double?
    public var contextWindow: Int?
    public var maxOutputTokens: Int?

    public struct ServerToolUse: Codable, Sendable, Equatable {
        public var webSearchRequests: Int
        public var webFetchRequests: Int

        public init(webSearchRequests: Int = 0, webFetchRequests: Int = 0) {
            self.webSearchRequests = webSearchRequests
            self.webFetchRequests = webFetchRequests
        }
    }

    public struct CacheCreation: Codable, Sendable, Equatable {
        public var ephemeral1hInputTokens: Int
        public var ephemeral5mInputTokens: Int

        public init(ephemeral1hInputTokens: Int = 0, ephemeral5mInputTokens: Int = 0) {
            self.ephemeral1hInputTokens = ephemeral1hInputTokens
            self.ephemeral5mInputTokens = ephemeral5mInputTokens
        }
    }

    public struct UsageIteration: Codable, Sendable, Equatable {
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

    public static let empty = Usage()

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
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
