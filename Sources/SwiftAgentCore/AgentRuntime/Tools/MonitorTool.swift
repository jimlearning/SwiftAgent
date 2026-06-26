import Foundation

/// Monitor tool for streaming events. Feature-gated behind MONITOR_TOOL.
/// CC: tools/MonitorTool/ — feature('MONITOR_TOOL').
public struct MonitorTool: Tool {
    public let name = "Monitor"
    public let description = "Monitor and stream events from external sources."

    public struct Arguments: Codable, Sendable {
        public var action: String

        enum CodingKeys: String, CodingKey {
            case action
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Monitor action"),
        ], required: ["action"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("Monitor tool requires ant-internal build.")
    }
}
