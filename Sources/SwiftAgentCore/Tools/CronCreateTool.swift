import Foundation

/// Schedules a recurring or one-shot cron job.
/// Matches Claude Code's CronCreateTool.
public struct CronCreateTool: Tool {
    public let name = "CronCreate"
    public var searchHint: String? { "schedule a recurring or one-shot prompt" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Schedule a recurring or one-shot cron job that fires a prompt at specified times" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["cron"] = JSONSchemaProperty(type: "string", description: "Standard 5-field cron expression in local time: \"M H DoM Mon DoW\" (e.g., \"*/5 * * * *\" = every 5 minutes)")
        schema.properties?["prompt"] = JSONSchemaProperty(type: "string", description: "The prompt to enqueue at each fire time")
        schema.properties?["recurring"] = JSONSchemaProperty(type: "boolean", description: "true (default) = fire on every cron match. false = fire once then auto-delete")
        schema.properties?["durable"] = JSONSchemaProperty(type: "boolean", description: "true = persist to disk. false (default) = in-memory only")
        schema.required = ["cron", "prompt"]
        return schema
    }()

    private let cronStore: CronStore

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let cronVal = input["cron"], case .string(let cron) = cronVal else {
            return ToolResult(content: "Error: cron expression is required", isError: true)
        }
        guard let promptVal = input["prompt"], case .string(let prompt) = promptVal else {
            return ToolResult(content: "Error: prompt is required", isError: true)
        }

        guard isValidCron(cron) else {
            return ToolResult(content: "Invalid cron expression '\(cron)'. Expected 5 fields: M H DoM Mon DoW.", isError: true)
        }

        let recurring: Bool
        if let r = input["recurring"] {
            if case .bool(let b) = r { recurring = b }
            else if case .string(let s) = r { recurring = s.lowercased() == "true" }
            else { recurring = true }
        } else { recurring = true }

        let durable: Bool
        if let d = input["durable"] {
            if case .bool(let b) = d { durable = b }
            else if case .string(let s) = d { durable = s.lowercased() == "true" }
            else { durable = false }
        } else { durable = false }

        let task = CronTask(cron: cron, prompt: prompt, recurring: recurring, durable: durable)
        do {
            let id = try await cronStore.add(task)
            let human = cronToHuman(cron)
            let whereStr = durable
                ? "Persisted to disk"
                : "Session-only (not written to disk, dies when session exits)"
            let msg = recurring
                ? "Scheduled recurring job \(id) (\(human)). \(whereStr). Use CronDelete to cancel."
                : "Scheduled one-shot task \(id) (\(human)). \(whereStr). It will fire once then auto-delete."
            return ToolResult(content: msg)
        } catch CronError.tooManyJobs {
            return ToolResult(content: "Too many scheduled jobs (max 50). Cancel one first.", isError: true)
        } catch {
            return ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}
