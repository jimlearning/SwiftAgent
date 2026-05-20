import Foundation

/// Lists active cron jobs.
/// Matches Claude Code's CronListTool.
public struct CronListTool: Tool {
    public let name = "CronList"
    public var searchHint: String? { "list active cron jobs" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "List all active scheduled cron jobs" }
    public let isReadOnly = true
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public let inputSchema = JSONSchema(type: "object", properties: [:])

    private let cronStore: CronStore

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let tasks = await cronStore.listAll()
        if tasks.isEmpty {
            return ToolResult(content: "No scheduled jobs.")
        }

        let lines = tasks.map { t in
            let human = cronToHuman(t.cron)
            let type = t.recurring ? "recurring" : "one-shot"
            let persist = t.durable ? "" : " [session-only]"
            let truncatedPrompt = t.prompt.count > 80 ? String(t.prompt.prefix(80)) + "\u{2026}" : t.prompt
            return "\(t.id) \u{2014} \(human) (\(type))\(persist): \(truncatedPrompt)"
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }
}
