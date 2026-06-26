import Foundation

/// Testing permission tool. Only available in test environments.
/// Matches Claude Code's TestingPermissionTool.
///
/// Registration is gated by the ToolMetadata.isEnabled flag (set to false
/// outside debug builds), not by the tool itself.
public struct TestingPermissionTool: Tool {
    public let name = "TestingPermission"
    public let description = "Test the tool permission system with various scenarios."

    public struct Arguments: Codable, Sendable {
        public var scenario: String

        enum CodingKeys: String, CodingKey {
            case scenario
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "scenario": JSONSchemaProperty(
                type: "string",
                description: "Permission test scenario to run"
            ),
        ], required: ["scenario"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("TestingPermission tool is only available in debug/test builds.")
    }
}
