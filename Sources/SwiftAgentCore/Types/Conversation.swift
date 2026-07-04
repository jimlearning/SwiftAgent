import Foundation

/// Core conversation and message types.
public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case progress
    case attachment
    /// Matches CC's ToolUseSummaryMessage type: 'tool_use_summary'.
    case toolUseSummary = "tool_use_summary"
    /// Matches CC's TombstoneMessage type: 'tombstone'.
    case tombstone
}

// MARK: - Message Origin

/// Provenance of a user message. Matches CC's MessageOrigin discriminated union.
public enum MessageOrigin: Codable, Sendable {
    /// Sent by a human user.
    case human
    /// Sent by a task notification system.
    case taskNotification
    /// Sent by a coordinator agent.
    case coordinator
    /// Sent via a channel (e.g. Slack, API).
    case channel(server: String)

    public var kind: String {
        switch self {
        case .human: return "human"
        case .taskNotification: return "task-notification"
        case .coordinator: return "coordinator"
        case .channel: return "channel"
        }
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case kind, server }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "channel":
            let server = try container.decode(String.self, forKey: .server)
            self = .channel(server: server)
        case "task-notification": self = .taskNotification
        case "coordinator": self = .coordinator
        default: self = .human
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if case .channel(let server) = self {
            try container.encode(server, forKey: .server)
        }
    }
}

// MARK: - Summarize Metadata

/// Metadata for compact-summary user messages. Matches CC's summarizeMetadata.
public struct SummarizeMetadata: Codable, Sendable {
    public let messagesSummarized: Int
    public let userContext: String?

    public init(messagesSummarized: Int, userContext: String? = nil) {
        self.messagesSummarized = messagesSummarized
        self.userContext = userContext
    }
}

// MARK: - Message

public struct Message: Sendable, Identifiable {
    public let uuid: String
    public let type: MessageRole
    public let content: [ContentBlock]
    /// Identifier of the tool use that triggered this message (for assistant messages).
    /// Matches Claude Code's parentMessage.toolUseID.
    public let toolUseID: String?
    /// Parent tool use ID for progress messages. Matches CC's ProgressMessage.parentToolUseID.
    public let parentToolUseID: String?
    /// ISO 8601 timestamp of when this message was created. Matches CC's timestamp.
    public let timestamp: Date
    /// Whether this is a meta-message (compaction summary, system note, etc.).
    /// Matches CC's isMeta flag — meta messages are hidden from transcript by default.
    public let isMeta: Bool
    /// Token usage for this message (set on assistant messages). Matches CC's message.usage.
    public let usage: Usage?
    /// Model that generated this message (set on assistant messages). Matches CC's message.model.
    public let model: String?
    /// Stop reason for the assistant turn. Matches CC's message.stop_reason.
    public let stopReason: String?
    /// Origin of the message (e.g. "human", "compact", "agent"). Matches CC's origin field.
    public let origin: MessageOrigin?
    /// Whether this is a virtual message (not stored to transcript). Matches CC's isVirtual.
    public let isVirtual: Bool
    /// Whether this message IS a compact summary placeholder. Matches CC's isCompactSummary.
    public let isCompactSummary: Bool
    /// Visible in transcript but hidden from model. Matches CC's isVisibleInTranscriptOnly.
    public let isVisibleInTranscriptOnly: Bool
    /// Metadata for compact summary messages. Matches CC's summarizeMetadata.
    public let summarizeMetadata: SummarizeMetadata?
    /// Full tool use result object. Matches CC's toolUseResult.
    public let toolUseResult: JSONValue?
    /// MCP metadata for tool results. Matches CC's mcpMeta.
    public let mcpMeta: MCPMeta?
    /// IDs of pasted images. Matches CC's imagePasteIds.
    public let imagePasteIds: [Int]?
    /// UUID of assistant message containing matching tool_use. Matches CC's sourceToolAssistantUUID.
    public let sourceToolAssistantUUID: String?
    /// Permission mode when message was sent. Matches CC's permissionMode.
    public let permissionMode: PermissionMode?
    /// API request identifier (assistant messages). Matches CC's requestId.
    public let requestId: String?
    /// API error from the SDK. Matches CC's apiError on assistant messages.
    public let apiError: String?
    /// Error classification. Matches CC's error field (authentication_failed, billing_error, rate_limit, etc.).
    public let error: String?
    /// Error details string. Matches CC's errorDetails.
    public let errorDetails: String?
    /// Whether this is an API error message. Matches CC's isApiErrorMessage.
    public let isApiErrorMessage: Bool
    /// Message container ID. Matches CC's message.container.
    public let container: String?
    /// Stop sequence that ended generation. Matches CC's message.stop_sequence.
    public let stopSequence: String?

    public init(
        uuid: String = UUID().uuidString,
        type: MessageRole,
        content: [ContentBlock],
        toolUseID: String? = nil,
        parentToolUseID: String? = nil,
        timestamp: Date = Date(),
        isMeta: Bool = false,
        usage: Usage? = nil,
        model: String? = nil,
        stopReason: String? = nil,
        origin: MessageOrigin? = nil,
        isVirtual: Bool = false,
        isCompactSummary: Bool = false,
        isVisibleInTranscriptOnly: Bool = false,
        summarizeMetadata: SummarizeMetadata? = nil,
        toolUseResult: JSONValue? = nil,
        mcpMeta: MCPMeta? = nil,
        imagePasteIds: [Int]? = nil,
        sourceToolAssistantUUID: String? = nil,
        permissionMode: PermissionMode? = nil,
        requestId: String? = nil,
        apiError: String? = nil,
        error: String? = nil,
        errorDetails: String? = nil,
        isApiErrorMessage: Bool = false,
        container: String? = nil,
        stopSequence: String? = nil
    ) {
        self.uuid = uuid
        self.type = type
        self.content = content
        self.toolUseID = toolUseID
        self.parentToolUseID = parentToolUseID
        self.timestamp = timestamp
        self.isMeta = isMeta
        self.usage = usage
        self.model = model
        self.stopReason = stopReason
        self.origin = origin
        self.isVirtual = isVirtual
        self.isCompactSummary = isCompactSummary
        self.isVisibleInTranscriptOnly = isVisibleInTranscriptOnly
        self.summarizeMetadata = summarizeMetadata
        self.toolUseResult = toolUseResult
        self.mcpMeta = mcpMeta
        self.imagePasteIds = imagePasteIds
        self.sourceToolAssistantUUID = sourceToolAssistantUUID
        self.permissionMode = permissionMode
        self.requestId = requestId
        self.apiError = apiError
        self.error = error
        self.errorDetails = errorDetails
        self.isApiErrorMessage = isApiErrorMessage
        self.container = container
        self.stopSequence = stopSequence
    }
}

extension Message {
    public var id: String { uuid }
    public var role: MessageRole { type }
}

// MARK: Message Codable (CC-compatible)

extension Message: Codable {

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case model
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
        case timestamp
        case uuid
        case isMeta
        case isVirtual
        case isCompactSummary
        case isVisibleInTranscriptOnly
        case isApiErrorMessage
        case toolUseID
        case parentToolUseID
        case toolUseResult
        case mcpMeta
        case imagePasteIds
        case sourceToolAssistantUUID
        case permissionMode
        case requestId
        case apiError
        case error
        case errorDetails
        case container
        case origin
        case summarizeMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let role = try container.decode(MessageRole.self, forKey: .role)

        let content: [ContentBlock]
        if let str = try? container.decode(String.self, forKey: .content) {
            content = [.text(str)]
        } else {
            content = try container.decode([ContentBlock].self, forKey: .content)
        }

        self.init(
            uuid: (try? container.decode(String.self, forKey: .id)) ?? (try? container.decode(String.self, forKey: .uuid)) ?? UUID().uuidString,
            type: role,
            content: content,
            toolUseID: try container.decodeIfPresent(String.self, forKey: .toolUseID),
            parentToolUseID: try container.decodeIfPresent(String.self, forKey: .parentToolUseID),
            timestamp: (try? container.decode(Date.self, forKey: .timestamp)) ?? Date(),
            isMeta: try container.decodeIfPresent(Bool.self, forKey: .isMeta) ?? false,
            usage: try container.decodeIfPresent(Usage.self, forKey: .usage),
            model: try container.decodeIfPresent(String.self, forKey: .model),
            stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason),
            origin: try container.decodeIfPresent(MessageOrigin.self, forKey: .origin),
            isVirtual: try container.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false,
            isCompactSummary: try container.decodeIfPresent(Bool.self, forKey: .isCompactSummary) ?? false,
            isVisibleInTranscriptOnly: try container.decodeIfPresent(Bool.self, forKey: .isVisibleInTranscriptOnly) ?? false,
            summarizeMetadata: try container.decodeIfPresent(SummarizeMetadata.self, forKey: .summarizeMetadata),
            toolUseResult: try container.decodeIfPresent(JSONValue.self, forKey: .toolUseResult),
            mcpMeta: try container.decodeIfPresent(MCPMeta.self, forKey: .mcpMeta),
            imagePasteIds: try container.decodeIfPresent([Int].self, forKey: .imagePasteIds),
            sourceToolAssistantUUID: try container.decodeIfPresent(String.self, forKey: .sourceToolAssistantUUID),
            permissionMode: try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode),
            requestId: try container.decodeIfPresent(String.self, forKey: .requestId),
            apiError: try container.decodeIfPresent(String.self, forKey: .apiError),
            error: try container.decodeIfPresent(String.self, forKey: .error),
            errorDetails: try container.decodeIfPresent(String.self, forKey: .errorDetails),
            isApiErrorMessage: try container.decodeIfPresent(Bool.self, forKey: .isApiErrorMessage) ?? false,
            container: try container.decodeIfPresent(String.self, forKey: .container),
            stopSequence: try container.decodeIfPresent(String.self, forKey: .stopSequence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(type, forKey: .role)

        switch type {
        case .user:
            // CC format: user messages with text use a plain string;
            // user messages with tool_result use an array of content blocks.
            let nonText = content.contains { if case .text = $0 { return false }; return true }
            if !nonText, case .text(let text) = content.first {
                try container.encode(text, forKey: .content)
            } else {
                try container.encode(content, forKey: .content)
            }
        case .assistant:
            try container.encode(uuid, forKey: .id)
            try container.encode("message", forKey: .type)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(stopReason, forKey: .stopReason)
            // CC always includes stop_sequence (typically null)
            try container.encode(stopSequence, forKey: .stopSequence)
            try container.encodeIfPresent(usage, forKey: .usage)
        default:
            try container.encode(content, forKey: .content)
        }
    }
}

// MARK: - Tool Result Content

/// Tool result content matching CC's string | ContentBlockParam[] union.
public enum ToolResultContent: Sendable {
    case string(String)
    case blocks([ContentBlock])
}

extension ToolResultContent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            let blocks = try container.decode([ContentBlock].self)
            self = .blocks(blocks)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str): try container.encode(str)
        case .blocks(let blocks): try container.encode(blocks)
        }
    }

    /// Format for API: strings pass through, blocks are converted to [[String: Any]].
    public var apiFormatted: Any {
        switch self {
        case .string(let str): return str
        case .blocks(let blocks):
            return blocks.map { block in
                switch block {
                case .text(let text): return ["type": "text", "text": text] as [String: Any]
                case .image(_, let mediaType, let data, _):
                    var source: [String: Any] = ["type": "base64", "media_type": mediaType]
                    if let data = data { source["data"] = data }
                    return ["type": "image", "source": source] as [String: Any]
                default: return ["type": "text", "text": ""] as [String: Any]
                }
            }
        }
    }
}

// MARK: - Content Block

public enum ContentBlock: Sendable {
    case text(String)
    /// Thinking block with optional cryptographic signature for verification.
    /// Matches CC's thinking block { thinking, signature }.
    case thinking(String, signature: String? = nil, duration: TimeInterval? = nil)
    /// Redacted thinking placeholder (e.g. for streaming truncation).
    /// Matches CC's redacted_thinking block.
    case redactedThinking(String)
    case toolUse(id: String, name: String, input: JSONValue)
    /// Server-side tool use (advisor tools, MCP server-initiated tools).
    /// Matches CC's server_tool_use content block type.
    case serverToolUse(id: String, name: String, input: JSONValue)
    /// Tool result with content matching CC's string | ContentBlockParam[].
    case toolResult(toolUseID: String, content: ToolResultContent, isError: Bool)
    /// Image block with media type and base64 data or URL.
    /// Matches CC's image ContentBlockParam: { source: { type, media_type, data?, url? } }.
    case image(type: String, mediaType: String, data: String? = nil, url: String? = nil)
    /// Document/PDF block for document inputs.
    /// Matches CC's document ContentBlockParam: { source: { type, media_type, data } }.
    case document(type: String, mediaType: String, data: String)
    /// Tool reference block from tool search results (API-injected in tool_result content).
    /// Matches CC's tool_reference ContentBlockParam: { name, description, input_schema }.
    /// Stripped in normalizeMessagesForAPI Pass 6 when tool search is not enabled.
    case toolReference(name: String, description: String)
}

// MARK: ContentBlock Codable (CC-compatible)

extension ContentBlock: Codable {

    // MARK: CC Format Coding Keys

    private enum CCKeys: String, CodingKey {
        case type
        case text
        case thinking
        case signature
        case duration
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
        case source
        case data
        case mediaType = "media_type"
        case description
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CCKeys.self)

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "thinking":
            let text = try container.decode(String.self, forKey: .thinking)
            let sig = try container.decodeIfPresent(String.self, forKey: .signature)
            let dur = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            self = .thinking(text, signature: sig, duration: dur)
        case "redacted_thinking":
            let data = try container.decode(String.self, forKey: .data)
            self = .redactedThinking(data)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "server_tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .serverToolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseID = try container.decode(String.self, forKey: .toolUseID)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            let content: ToolResultContent
            if let str = try? container.decode(String.self, forKey: .content) {
                content = .string(str)
            } else {
                let blocks = try container.decode([ContentBlock].self, forKey: .content)
                content = .blocks(blocks)
            }
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
        case "image":
            let nested = try container.nestedContainer(keyedBy: CCKeys.self, forKey: .source)
            let imgType = try nested.decode(String.self, forKey: .type)
            let mediaType = try nested.decode(String.self, forKey: .mediaType)
            let data = try nested.decodeIfPresent(String.self, forKey: .data)
            let url = try nested.decodeIfPresent(String.self, forKey: .url)
            self = .image(type: imgType, mediaType: mediaType, data: data, url: url)
        case "document":
            let nested = try container.nestedContainer(keyedBy: CCKeys.self, forKey: .source)
            let docType = try nested.decode(String.self, forKey: .type)
            let mediaType = try nested.decode(String.self, forKey: .mediaType)
            let data = try nested.decode(String.self, forKey: .data)
            self = .document(type: docType, mediaType: mediaType, data: data)
        case "tool_reference":
            let name = try container.decode(String.self, forKey: .name)
            let desc = try container.decode(String.self, forKey: .description)
            self = .toolReference(name: name, description: desc)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown ContentBlock type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CCKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinking(let text, let signature, let duration):
            try container.encode("thinking", forKey: .type)
            try container.encode(text, forKey: .thinking)
            try container.encodeIfPresent(signature, forKey: .signature)
            try container.encodeIfPresent(duration, forKey: .duration)
        case .redactedThinking(let data):
            try container.encode("redacted_thinking", forKey: .type)
            try container.encode(data, forKey: .data)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .serverToolUse(let id, let name, let input):
            try container.encode("server_tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        case .image(let type, let mediaType, let data, let url):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: CCKeys.self, forKey: .source)
            try source.encode(type, forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encodeIfPresent(data, forKey: .data)
            try source.encodeIfPresent(url, forKey: .url)
        case .document(let type, let mediaType, let data):
            try container.encode("document", forKey: .type)
            var source = container.nestedContainer(keyedBy: CCKeys.self, forKey: .source)
            try source.encode(type, forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(data, forKey: .data)
        case .toolReference(let name, let description):
            try container.encode("tool_reference", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
        }
    }
}

/// A JSON-compatible value for tool inputs/outputs.
/// Encodes as plain JSON (no wrapper) for CC compatibility.
public indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { $0.anyValue }
        case .object(let dict): return dict.mapValues { $0.anyValue }
        }
    }

    public static func fromAny(_ value: Any) -> JSONValue? {
        switch value {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let b as Bool: return .bool(b)
        case let n as Double: return .number(n)
        case let n as Int: return .number(Double(n))
        case is NSNull: return .null
        case let arr as [Any]: return .array(arr.compactMap { fromAny($0) })
        case let dict as [String: Any]: return .object(dict.compactMapValues { fromAny($0) })
        default: return nil
        }
    }
}

// MARK: JSONValue Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Double.self) {
            self = .number(num)
        } else if let bol = try? container.decode(Bool.self) {
            self = .bool(bol)
        } else if container.decodeNil() {
            self = .null
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let arr): try container.encode(arr)
        case .object(let dict): try container.encode(dict)
        }
    }
}

extension JSONValue {
    /// Returns a JSON string representation of this value.
    /// Useful for tool input summaries and display.
    public var jsonString: String {
        switch self {
        case .string(let s): return "\"" + s + "\""
        case .number(let n):
            if n == Double(Int(n)) { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[" + arr.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let dict):
            let pairs = dict.map { "\"\($0.key)\":\($0.value.jsonString)" }.joined(separator: ",")
            return "{" + pairs + "}"
        }
    }
}

public struct Turn: Codable, Sendable {
    public var userMessage: Message
    public var assistantMessage: Message?
    public var toolResults: [Message]

    public init(userMessage: Message, assistantMessage: Message? = nil, toolResults: [Message] = []) {
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.toolResults = toolResults
    }
}

public struct Conversation: Codable, Sendable, Identifiable {
    public let id: String
    public var turns: [Turn]
    public var systemPrompt: String?
    /// Flat message storage for direct serialization/deserialization.
    /// When set, `messages` returns this directly instead of deriving from `turns`.
    public var flatMessages: [Message]?

    public init(id: String = UUID().uuidString, turns: [Turn] = [], systemPrompt: String? = nil, flatMessages: [Message]? = nil) {
        self.id = id
        self.turns = turns
        self.systemPrompt = systemPrompt
        self.flatMessages = flatMessages
    }

    public var messages: [Message] {
        if let flat = flatMessages { return flat }
        var result: [Message] = []
        if let prompt = systemPrompt {
            result.append(Message(type: .system, content: [.text(prompt)]))
        }
        for turn in turns {
            result.append(turn.userMessage)
            if let assistant = turn.assistantMessage {
                result.append(assistant)
            }
            result.append(contentsOf: turn.toolResults)
        }
        return result
    }
}
