import Foundation

/// Suspends execution for a specified duration.
/// Matches Claude Code's SleepTool. CC gate: feature(PROACTIVE) || feature(KAIROS).
public struct SleepTool: Tool {
    public let name = "Sleep"
    public let description = "Pause execution for a specified duration."

    public struct Arguments: Codable, Sendable {
        public var duration: Double
        public var reason: String?

        enum CodingKeys: String, CodingKey {
            case duration
            case reason
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["duration"] = JSONSchemaProperty(type: "number", description: "Duration in seconds to sleep")
        schema.properties?["reason"] = JSONSchemaProperty(type: "string", description: "Reason for waiting")
        schema.required = ["duration"]
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let reason = arguments.reason ?? "no reason specified"
        let capped = min(arguments.duration, 300)

        try await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))

        return .string("Slept for \(capped)s (\(reason))")
    }
}
