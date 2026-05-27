import Foundation
import SwiftAgentCore

struct ChatToolInputError: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case invalidJSON
        case truncatedByMaxTokens
    }

    let kind: Kind
    let toolName: String
    let toolID: String

    var message: String {
        switch kind {
        case .invalidJSON:
            return "Error: model produced incomplete tool input for \(toolName). The tool call was not executed. Please retry with a smaller edit or split the generated content into smaller chunks."
        case .truncatedByMaxTokens:
            return "Error: model output hit max_tokens while preparing tool input for \(toolName). No tool was executed. Please retry with a smaller edit or split the generated content into smaller chunks."
        }
    }
}

struct ChatToolInputAccumulator: Sendable {
    private struct PendingTool: Sendable {
        let name: String
        let id: String
        var inputJSON: String
    }

    private var pendingTool: PendingTool?
    private(set) var sawToolUse = false
    private(set) var errors: [ChatToolInputError] = []
    private(set) var parsedCalls: [ChatToolCall] = []

    mutating func startTool(name: String, id: String) {
        sawToolUse = true
        pendingTool = PendingTool(name: name, id: id, inputJSON: "")
    }

    mutating func appendInputJSONDelta(_ delta: String) {
        pendingTool?.inputJSON += delta
    }

    mutating func stopCurrentBlock() {
        guard let tool = pendingTool else { return }
        defer { pendingTool = nil }

        guard !tool.inputJSON.isEmpty else {
            parsedCalls.append(ChatToolCall(name: tool.name, id: tool.id, input: [:]))
            return
        }

        guard let data = tool.inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errors.append(ChatToolInputError(kind: .invalidJSON, toolName: tool.name, toolID: tool.id))
            return
        }

        var input: [String: JSONValue] = [:]
        for (key, value) in json {
            if let jsonValue = JSONValue.fromAny(value) {
                input[key] = jsonValue
            }
        }
        parsedCalls.append(ChatToolCall(name: tool.name, id: tool.id, input: input))
    }

    mutating func finish(stopReason: String?) -> ChatToolInputError? {
        if let tool = pendingTool, stopReason == "max_tokens" {
            let error = ChatToolInputError(kind: .truncatedByMaxTokens, toolName: tool.name, toolID: tool.id)
            errors.append(error)
            pendingTool = nil
            return error
        }

        if stopReason == "max_tokens", sawToolUse {
            let toolName = parsedCalls.last?.name ?? errors.last?.toolName ?? "tool"
            let toolID = parsedCalls.last?.id ?? errors.last?.toolID ?? ""
            let error = ChatToolInputError(kind: .truncatedByMaxTokens, toolName: toolName, toolID: toolID)
            errors.append(error)
            return error
        }

        return errors.first
    }
}
