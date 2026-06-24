import Foundation
import SwiftAgentCore

// MARK: - AgentMessage (Rich Message Model)

/// A message in the agent conversation, enriched for SwiftUI display.
///
/// Supports the full agent conversation model:
/// - User text messages
/// - Assistant text (streamed incrementally)
/// - Assistant thinking/reasoning blocks (collapsible)
/// - Tool invocations (tool name + input summary)
/// - Tool results (output + error state)
/// - System/system-reminder messages
///
/// `renderToken` increments on every mutation; used as the ForEach identity
/// suffix so SwiftUI re-evaluates the view body during streaming even when
/// the message's `id` stays the same.
public struct AgentMessage: Identifiable, Equatable {
    public let id: String
    public let role: AgentMessageRole
    public var blocks: [AgentMessageBlock]
    public var isStreaming: Bool
    public var timestamp: Date
    public var tokenUsage: Usage?
    /// Incremented on every mutation for ForEach identity tracking.
    public var renderToken: Int

    public init(
        id: String = UUID().uuidString,
        role: AgentMessageRole,
        blocks: [AgentMessageBlock] = [],
        isStreaming: Bool = false,
        timestamp: Date = Date(),
        tokenUsage: Usage? = nil,
        renderToken: Int = 0
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.isStreaming = isStreaming
        self.timestamp = timestamp
        self.tokenUsage = tokenUsage
        self.renderToken = renderToken
    }

    /// Stable identity for ForEach — includes renderToken so SwiftUI
    /// re-evaluates the view body on every mutation during streaming.
    public var displayID: String { "\(id):\(renderToken)" }

    // MARK: - Convenience factories

    public static func user(_ text: String, id: String = UUID().uuidString) -> AgentMessage {
        AgentMessage(id: id, role: .user, blocks: [.text(text)])
    }

    public static func assistantStreaming(id: String = UUID().uuidString) -> AgentMessage {
        AgentMessage(id: id, role: .assistant, blocks: [.text("")], isStreaming: true)
    }

    // MARK: - Mutation helpers (each bumps renderToken)

    public mutating func appendText(_ text: String) {
        renderToken &+= 1
        // Merge into the last block if it is already text (streaming continuation).
        if let lastBlock = blocks.last, case .text(let existing) = lastBlock {
            blocks[blocks.count - 1] = .text(existing + text)
            return
        }
        // New text block at the end, preserving the model's output order.
        // The model may produce text before or after tools; we must not reorder.
        blocks.append(.text(text))
    }

    public mutating func appendThinking(_ text: String) {
        renderToken &+= 1
        // Merge into the last block if it is thinking (streaming continuation).
        if let lastBlock = blocks.last, case .thinking(let existing, let id, let expanded) = lastBlock {
            blocks[blocks.count - 1] = .thinking(existing + text, id: id, isExpanded: expanded)
            return
        }
        // New thinking block at the end, preserving interleaved order.
        blocks.append(.thinking(text))
    }

    public mutating func addToolUse(_ block: ToolUseBlock) {
        renderToken &+= 1
        blocks.append(.toolUse(block))
    }

    public mutating func updateToolUse(toolUseID: String, status: ToolUseStatus) {
        renderToken &+= 1
        guard let idx = blocks.firstIndex(where: { $0.toolUse?.toolUseID == toolUseID }) else { return }
        if var toolUse = blocks[idx].toolUse {
            toolUse.status = status
            blocks[idx] = .toolUse(toolUse)
        }
    }

    public mutating func addToolResult(_ block: ToolResultBlock) {
        renderToken &+= 1
        blocks.append(.toolResult(block))
    }

    public mutating func finalize(tokenUsage: Usage? = nil) {
        renderToken &+= 1
        isStreaming = false
        if let usage = tokenUsage { self.tokenUsage = usage }
    }

    public mutating func markFailed(_ error: String) {
        renderToken &+= 1
        isStreaming = false
        blocks = [.text(error)]
    }
}

// MARK: - AgentMessageRole

public enum AgentMessageRole: String, Equatable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - AgentMessageBlock

public enum AgentMessageBlock: Equatable, Codable {
    case text(String)
    case thinking(String, id: String = UUID().uuidString, isExpanded: Bool = false)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
    case systemReminder(String)

    public var toolUse: ToolUseBlock? {
        if case .toolUse(let block) = self { return block }
        return nil
    }

    public var toolResult: ToolResultBlock? {
        if case .toolResult(let block) = self { return block }
        return nil
    }

    public var textContent: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    public var thinkingContent: String? {
        if case .thinking(let text, _, _) = self { return text }
        return nil
    }

    // MARK: Codable (backward-compatible with old 2-param thinking form)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.text) {
            self = .text(try container.decode(String.self, forKey: .text))
        } else if container.contains(.thinking) {
            let nested = try container.nestedContainer(keyedBy: ThinkingCodingKeys.self, forKey: .thinking)
            let text = try nested.decode(String.self, forKey: ._0)
            let isExpanded = try nested.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
            // id was added later — default to a fresh UUID for old persisted data
            let id = (try? nested.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            self = .thinking(text, id: id, isExpanded: isExpanded)
        } else if container.contains(.toolUse) {
            let block = try container.decode(ToolUseBlock.self, forKey: .toolUse)
            self = .toolUse(block)
        } else if container.contains(.toolResult) {
            let block = try container.decode(ToolResultBlock.self, forKey: .toolResult)
            self = .toolResult(block)
        } else if container.contains(.systemReminder) {
            self = .systemReminder(try container.decode(String.self, forKey: .systemReminder))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown AgentMessageBlock case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .thinking(let text, let id, let isExpanded):
            var nested = container.nestedContainer(keyedBy: ThinkingCodingKeys.self, forKey: .thinking)
            try nested.encode(text, forKey: ._0)
            try nested.encode(id, forKey: .id)
            try nested.encode(isExpanded, forKey: .isExpanded)
        case .toolUse(let block):
            try container.encode(block, forKey: .toolUse)
        case .toolResult(let block):
            try container.encode(block, forKey: .toolResult)
        case .systemReminder(let text):
            try container.encode(text, forKey: .systemReminder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case thinking
        case toolUse
        case toolResult
        case systemReminder
    }

    private enum ThinkingCodingKeys: String, CodingKey {
        case _0
        case id
        case isExpanded
    }
}

// MARK: - ToolUseBlock

public struct ToolUseBlock: Equatable, Codable {
    public let toolUseID: String
    public let toolName: String
    public let inputSummary: String
    public let inputDetail: String
    /// Raw JSON input for round-tripping back to Core ContentBlock.toolUse.
    public let rawInput: JSONValue?
    public var status: ToolUseStatus

    public init(
        toolUseID: String,
        toolName: String,
        inputSummary: String,
        inputDetail: String,
        rawInput: JSONValue? = nil,
        status: ToolUseStatus = .pending
    ) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.inputSummary = inputSummary
        self.inputDetail = inputDetail
        self.rawInput = rawInput
        self.status = status
    }

    /// Custom decoding so persisted blocks from before the `status` field
    /// was added default to `.completed` instead of failing to decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolUseID = try c.decode(String.self, forKey: .toolUseID)
        toolName = try c.decode(String.self, forKey: .toolName)
        inputSummary = try c.decode(String.self, forKey: .inputSummary)
        inputDetail = try c.decode(String.self, forKey: .inputDetail)
        rawInput = try c.decodeIfPresent(JSONValue.self, forKey: .rawInput)
        status = try c.decodeIfPresent(ToolUseStatus.self, forKey: .status) ?? .completed
    }
}

public enum ToolUseStatus: Equatable, Codable {
    case pending
    case executing
    case completed
    case error(String)
}

// MARK: - ToolResultBlock

public struct ToolResultBlock: Equatable, Codable {
    public let toolUseID: String
    public let content: String
    public let isError: Bool
    public var isExpanded: Bool

    public init(
        toolUseID: String,
        content: String,
        isError: Bool = false,
        isExpanded: Bool = false
    ) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
        self.isExpanded = isExpanded
    }

    /// Custom decoding so persisted blocks from before the `isExpanded`
    /// field was added default to `false` instead of failing to decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolUseID = try c.decode(String.self, forKey: .toolUseID)
        content = try c.decode(String.self, forKey: .content)
        isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
    }
}

// MARK: - Conversion from Core types

extension AgentMessage {

    public static func fromCore(_ messages: [Message]) -> [AgentMessage] {
        messages.compactMap { msg in
            switch msg.type {
            case .user:
                let textBlocks: [AgentMessageBlock] = msg.content.compactMap { block in
                    if case .text(let text) = block { return .text(text) }
                    if case .toolResult(let toolUseID, let content, let isError) = block {
                        let resultText: String
                        switch content {
                        case .string(let s): resultText = s
                        case .blocks: resultText = "[complex result]"
                        }
                        return .toolResult(ToolResultBlock(
                            toolUseID: toolUseID,
                            content: resultText,
                            isError: isError
                        ))
                    }
                    return nil
                }
                let hasToolResults = textBlocks.contains { $0.toolResult != nil }
                let role: AgentMessageRole = hasToolResults ? .system : .user
                return AgentMessage(id: msg.uuid, role: role, blocks: textBlocks, timestamp: msg.timestamp)

            case .assistant:
                let blocks: [AgentMessageBlock] = msg.content.compactMap { block in
                    switch block {
                    case .text(let text): return .text(text)
                    case .thinking(let text, _): return .thinking(text)
                    case .toolUse(let id, let name, let input),
                         .serverToolUse(let id, let name, let input):
                        let summary = summarizeInput(toolName: name, input: input)
                        return .toolUse(ToolUseBlock(
                            toolUseID: id, toolName: name,
                            inputSummary: summary,
                            inputDetail: input.jsonString, rawInput: input,
                            status: .completed
                        ))
                    case .toolResult(let toolUseID, let content, let isError):
                        let text: String
                        switch content {
                        case .string(let s): text = s
                        case .blocks: text = "[complex result]"
                        }
                        return .toolResult(ToolResultBlock(
                            toolUseID: toolUseID,
                            content: text,
                            isError: isError
                        ))
                    default:
                        return nil
                    }
                }
                return AgentMessage(id: msg.uuid, role: .assistant, blocks: blocks,
                                    timestamp: msg.timestamp, tokenUsage: msg.usage)

            case .system, .progress:
                let textBlocks: [AgentMessageBlock] = msg.content.compactMap { block in
                    if case .text(let text) = block { return .systemReminder(text) }
                    return nil
                }
                guard !textBlocks.isEmpty else { return nil }
                return AgentMessage(id: msg.uuid, role: .system, blocks: textBlocks, timestamp: msg.timestamp)

            default:
                print("[fromCore] skipped msg type=\(msg.type.rawValue)")
                return nil
            }
        }
    }

    /// Rebuild AgentMessage list from RunResult.turns after agent loop completes.
    ///
    /// All turns in a single agent run share the same user input (QueryEngine reuses
    /// the original `userInput` for every Turn). The user message is only emitted for
    /// the FIRST turn to avoid duplication; subsequent turns contribute only their
    /// assistant message and tool results.
    ///
    /// Each turn's assistant message gets a unique UUID so they survive JSONL
    /// deduplication independently. The first turn reuses `lastAssistantID` (the
    /// streaming placeholder's UUID) so the coordinator replaces it in-place.
    public static func fromTurns(_ turns: [Turn], lastAssistantID: String? = nil) -> [AgentMessage] {
        var result: [AgentMessage] = []
        var isFirstTurn = true
        var isFirstAssistant = true
        for turn in turns {
            // Only emit user message for the first turn — all turns in a run
            // share the same user input, so repeating it causes duplication.
            if isFirstTurn {
                let userText = turn.userMessage.content.compactMap { block -> String? in
                    if case .text(let text) = block { return text }
                    return nil
                }.joined()
                if !userText.isEmpty {
                    result.append(AgentMessage(id: turn.userMessage.uuid, role: .user,
                                               blocks: [.text(userText)], timestamp: turn.userMessage.timestamp))
                }
                isFirstTurn = false
            }
            if let assistant = turn.assistantMessage {
                // First assistant reuses the streaming placeholder's UUID so the
                // coordinator replaces it in-place; subsequent assistants get unique
                // UUIDs so their tool_use blocks survive JSONL dedup independently.
                let msgID = isFirstAssistant
                    ? (lastAssistantID ?? assistant.uuid)
                    : assistant.uuid
                isFirstAssistant = false

                // Build the initial block list from the assistant's content.
                var blocks: [AgentMessageBlock] = assistant.content.compactMap { block in
                    switch block {
                    case .text(let text): return .text(text)
                    case .thinking(let text, _): return .thinking(text)
                    case .toolUse(let id, let name, let input),
                         .serverToolUse(let id, let name, let input):
                        return .toolUse(ToolUseBlock(
                            toolUseID: id, toolName: name,
                            inputSummary: summarizeInput(toolName: name, input: input),
                            inputDetail: input.jsonString, rawInput: input, status: .completed
                        ))
                    default: return nil
                    }
                }

                // Inline tool results right after their matching toolUse cards so
                // they stay adjacent (same as the streaming in-message layout).
                for trMsg in turn.toolResults {
                    for block in trMsg.content {
                        if case .toolResult(let toolUseID, let content, let isError) = block {
                            let text: String
                            switch content {
                            case .string(let s): text = s
                            case .blocks: text = "[complex result]"
                            }
                            let resultBlock: AgentMessageBlock = .toolResult(
                                ToolResultBlock(toolUseID: toolUseID, content: text, isError: isError)
                            )
                            // Insert after the matching toolUse card, or append if not found.
                            if let idx = blocks.lastIndex(where: { b in b.toolUse?.toolUseID == toolUseID }) {
                                blocks.insert(resultBlock, at: idx + 1)
                            } else {
                                blocks.append(resultBlock)
                            }
                        }
                    }
                }

                result.append(AgentMessage(
                    id: msgID, role: .assistant,
                    blocks: blocks,
                    timestamp: assistant.timestamp, tokenUsage: assistant.usage
                ))
            }
        }
        return result
    }

    private static func summarizeInput(toolName: String, input: JSONValue) -> String {
        switch input {
        case .object(let dict):
            switch toolName {
            case "Bash", "PowerShell":
                return dict["command"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Read", "FileRead":
                return dict["file_path"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Write", "FileWrite":
                return dict["file_path"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Edit", "FileEdit":
                return dict["file_path"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Grep":
                return dict["pattern"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Glob":
                return dict["pattern"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "WebFetch":
                return dict["url"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "WebSearch":
                return dict["query"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            case "Task":
                return dict["description"]?.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? toolName
            default:
                if let first = dict.first {
                    return "\(first.key): \(first.value.jsonString.truncated(to: 60))"
                }
                return toolName
            }
        case .string(let s): return s.truncated(to: 60)
        default: return toolName
        }
    }
}

// MARK: - Helpers

extension String {
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "\u{2026}"
    }
}

// MARK: - Block Serialization

extension [AgentMessageBlock] {
    /// Encode blocks to JSON for persistence in the metadata column.
    public func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode blocks from JSON stored in the metadata column.
    public static func fromJSON(_ json: String) -> [AgentMessageBlock]? {
        guard let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([AgentMessageBlock].self, from: data)
        else { return nil }
        return blocks
    }

    /// Extract plain text for the content column (sidebar preview).
    public func extractText() -> String {
        var parts: [String] = []
        for block in self {
            switch block {
            case .text(let text): parts.append(text)
            case .thinking: break
            case .toolUse(let tu):
                parts.append("[\(tu.toolName): \(tu.inputSummary)]")
            case .toolResult(let tr):
                if tr.isError { parts.append("[Error: \(tr.content.truncated(to: 200))]") }
            case .systemReminder(let text): parts.append(text)
            }
        }
        return parts.joined(separator: "\n")
    }
}
