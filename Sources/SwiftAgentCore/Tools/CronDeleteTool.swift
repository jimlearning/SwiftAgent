import Foundation

/// Cancels a scheduled cron job.
/// Matches Claude Code's CronDeleteTool.
public struct CronDeleteTool: Tool {
    public let name = "CronDelete"
    public var searchHint: String? { "cancel a scheduled cron job" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Cancel a scheduled cron job by ID" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["id"] = JSONSchemaProperty(type: "string", description: "Job ID returned by CronCreate")
        schema.required = ["id"]
        return schema
    }()

    private let cronStore: CronStore

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let idVal = input["id"], case .string(let id) = idVal else {
            return ToolResult(content: "Error: id is required", isError: true)
        }

        guard let _ = await cronStore.find(id: id) else {
            return ToolResult(content: "No scheduled job with id '\(id)'", isError: true)
        }

        await cronStore.remove(ids: [id])
        return ToolResult(content: "Cancelled job \(id).")
    }
}
