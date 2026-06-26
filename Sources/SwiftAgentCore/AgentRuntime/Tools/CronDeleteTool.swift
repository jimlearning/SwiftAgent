import Foundation

/// Cancels a scheduled cron job.
/// Matches Claude Code's CronDeleteTool.
public struct CronDeleteTool: Tool {
    public let name = "CronDelete"
    public let description = "Cancel a scheduled cron job by ID"

    private let cronStore: CronStore

    public struct Arguments: Codable, Sendable {
        public var id: String

        enum CodingKeys: String, CodingKey {
            case id
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["id"] = JSONSchemaProperty(type: "string", description: "Job ID returned by CronCreate")
        schema.required = ["id"]
        return schema
    }

    public init(cronStore: CronStore = CronStore()) {
        self.cronStore = cronStore
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let id = arguments.id

        guard let _ = await cronStore.find(id: id) else {
            return .string("No scheduled job with id '\(id)'")
        }

        await cronStore.remove(ids: [id])
        return .string("Cancelled job \(id).")
    }
}
