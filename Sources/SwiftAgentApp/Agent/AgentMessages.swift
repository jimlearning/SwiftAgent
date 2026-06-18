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
        if let lastIdx = blocks.lastIndex(where: { $0.textContent != nil }) {
            if let existing = blocks[lastIdx].textContent {
                blocks[lastIdx] = .text(existing + text)
                return
            }
        }
        let insertIdx: Int
        if let firstToolIdx = blocks.firstIndex(where: { $0.toolUse != nil || $0.toolResult != nil }) {
            insertIdx = firstToolIdx
        } else {
            insertIdx = blocks.count
        }
        blocks.insert(.text(text), at: insertIdx)
    }

    public mutating func appendThinking(_ text: String) {
        renderToken &+= 1
        if let lastIdx = blocks.lastIndex(where: {
            if case .thinking = $0 { return true }
            return false
        }) {
            if case .thinking(let existing, let expanded) = blocks[lastIdx] {
                blocks[lastIdx] = .thinking(existing + text, isExpanded: expanded)
                return
            }
        }
        blocks.insert(.thinking(text), at: 0)
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

public enum AgentMessageBlock: Equatable {
    case text(String)
    case thinking(String, isExpanded: Bool = false)
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
        if case .thinking(let text, _) = self { return text }
        return nil
    }
}

// MARK: - ToolUseBlock

public struct ToolUseBlock: Equatable {
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
}

public enum ToolUseStatus: Equatable {
    case pending
    case executing
    case completed
    case error(String)
}

// MARK: - ToolResultBlock

public struct ToolResultBlock: Equatable {
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
                    case .toolUse(let id, let name, let input):
                        return .toolUse(ToolUseBlock(
                            toolUseID: id, toolName: name,
                            inputSummary: summarizeInput(toolName: name, input: input),
                            inputDetail: input.jsonString, rawInput: input
                        ))
                    default: return nil
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

            default: return nil
            }
        }
    }

    /// Rebuild AgentMessage list from RunResult.turns after agent loop completes.
    public static func fromTurns(_ turns: [Turn], lastAssistantID: String? = nil) -> [AgentMessage] {
        var result: [AgentMessage] = []
        for turn in turns {
            let userText = turn.userMessage.content.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined()
            if !userText.isEmpty {
                result.append(AgentMessage(id: turn.userMessage.uuid, role: .user,
                                           blocks: [.text(userText)], timestamp: turn.userMessage.timestamp))
            }
            if let assistant = turn.assistantMessage {
                result.append(AgentMessage(
                    id: lastAssistantID ?? assistant.uuid, role: .assistant,
                    blocks: assistant.content.compactMap { block in
                        switch block {
                        case .text(let text): return .text(text)
                        case .thinking(let text, _): return .thinking(text)
                        case .toolUse(let id, let name, let input):
                            return .toolUse(ToolUseBlock(
                                toolUseID: id, toolName: name,
                                inputSummary: summarizeInput(toolName: name, input: input),
                                inputDetail: input.jsonString, rawInput: input, status: .completed
                            ))
                        default: return nil
                        }
                    },
                    timestamp: assistant.timestamp, tokenUsage: assistant.usage
                ))
            }
            for trMsg in turn.toolResults {
                let blocks = trMsg.content.compactMap { block -> AgentMessageBlock? in
                    if case .toolResult(let toolUseID, let content, let isError) = block {
                        let text: String
                        switch content {
                        case .string(let s): text = s
                        case .blocks: text = "[complex result]"
                        }
                        return .toolResult(ToolResultBlock(toolUseID: toolUseID, content: text, isError: isError))
                    }
                    return nil
                }
                if !blocks.isEmpty {
                    result.append(AgentMessage(id: trMsg.uuid, role: .system, blocks: blocks, timestamp: trMsg.timestamp))
                }
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
