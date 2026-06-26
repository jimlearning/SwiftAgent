import Foundation

/// Schedules a recurring or one-shot cron job.
/// Matches Claude Code's CronCreateTool.
public struct CronCreateTool: Tool {
    public let name = "CronCreate"
    public let description = "Schedule a recurring or one-shot cron job that fires a prompt at specified times"

    private let cronStore: CronStore

    public struct Arguments: Codable, Sendable {
        public var cron: String
        public var prompt: String
        public var recurring: Bool?
        public var durable: Bool?

        enum CodingKeys: String, CodingKey {
            case cron
            case prompt
            case recurring
            case durable
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["cron"] = JSONSchemaProperty(
            type: "string",
            description: "Standard 5-field cron expression in local time: \"M H DoM Mon DoW\" (e.g., \"*/5 * * * *\" = every 5 minutes)"
        )
        schema.properties?["prompt"] = JSONSchemaProperty(
            type: "string",
            description: "The prompt to enqueue at each fire time"
        )
        schema.properties?["recurring"] = JSONSchemaProperty(
            type: "boolean",
            description: "true (default) = fire on every cron match. false = fire once then auto-delete"
        )
        schema.properties?["durable"] = JSONSchemaProperty(
            type: "boolean",
            description: "true = persist to disk. false (default) = in-memory only"
        )
        schema.required = ["cron", "prompt"]
        return schema
    }

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let cron = arguments.cron
        let prompt = arguments.prompt

        guard isValidCron(cron) else {
            return .string("Invalid cron expression '\(cron)'. Expected 5 fields: M H DoM Mon DoW.")
        }

        let recurring = arguments.recurring ?? true
        let durable = arguments.durable ?? false

        let task = CronTask(
            cron: cron,
            prompt: prompt,
            recurring: recurring,
            durable: durable
        )

        do {
            let id = try await cronStore.add(task)
            let human = cronToHuman(cron)
            let whereStr = durable
                ? "Persisted to disk"
                : "Session-only (not written to disk, dies when session exits)"
            let msg = recurring
                ? "Scheduled recurring job \(id) (\(human)). \(whereStr). Use CronDelete to cancel."
                : "Scheduled one-shot task \(id) (\(human)). \(whereStr). It will fire once then auto-delete."
            return .string(msg)
        } catch CronError.tooManyJobs {
            return .string("Too many scheduled jobs (max 50). Cancel one first.")
        } catch {
            return .string("Error: \(error.localizedDescription)")
        }
    }
}
