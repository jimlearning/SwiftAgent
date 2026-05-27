import Foundation
import SwiftAgentCore

struct ChatToolCall: Sendable, Equatable {
    let name: String
    let id: String
    let input: [String: JSONValue]
}

struct ChatToolExecutionResult: Sendable, Equatable {
    let call: ChatToolCall
    let output: String
}

enum ChatToolExecutionScheduler {
    static func execute(
        calls: [ChatToolCall],
        isConcurrencySafe: @Sendable (ChatToolCall) -> Bool,
        execute: @escaping @Sendable (ChatToolCall) async -> String
    ) async -> [ChatToolExecutionResult] {
        guard !calls.isEmpty else { return [] }

        var outputs = Array<String?>(repeating: nil, count: calls.count)
        var cursor = 0

        while cursor < calls.count {
            if isConcurrencySafe(calls[cursor]) {
                let start = cursor
                repeat {
                    cursor += 1
                } while cursor < calls.count && isConcurrencySafe(calls[cursor])

                let range = start..<cursor
                if range.count == 1 {
                    outputs[start] = await execute(calls[start])
                } else {
                    await withTaskGroup(of: (Int, String).self) { group in
                        for index in range {
                            let call = calls[index]
                            group.addTask {
                                (index, await execute(call))
                            }
                        }
                        for await (index, output) in group {
                            outputs[index] = output
                        }
                    }
                }
            } else {
                outputs[cursor] = await execute(calls[cursor])
                cursor += 1
            }
        }

        return calls.enumerated().map { index, call in
            ChatToolExecutionResult(call: call, output: outputs[index] ?? "Error: tool execution produced no result")
        }
    }
}
