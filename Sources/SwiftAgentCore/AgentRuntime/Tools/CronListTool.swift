import Foundation

/// Lists active cron jobs.
/// Matches Claude Code's CronListTool.
public struct CronListTool: Tool {
    public let name = "CronList"
    public let description = "List all active scheduled cron jobs"

    private let cronStore: CronStore

    public struct Arguments: Codable, Sendable {
        // No arguments needed for listing.
    }

    public typealias Output = ToolOutputValue

    public let inputSchema = JSONSchema(type: "object", properties: [:])

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let tasks = await cronStore.listAll()
        if tasks.isEmpty {
            return .string("No scheduled jobs.")
        }

        let lines = tasks.map { t in
            let human = cronToHuman(t.cron)
            let type = t.recurring ? "recurring" : "one-shot"
            let persist = t.durable ? "" : " [session-only]"
            let truncatedPrompt = t.prompt.count > 80 ? String(t.prompt.prefix(80)) + "\u{2026}" : t.prompt
            return "\(t.id) \u{2014} \(human) (\(type))\(persist): \(truncatedPrompt)"
        }
        return .string(lines.joined(separator: "\n"))
    }
}
