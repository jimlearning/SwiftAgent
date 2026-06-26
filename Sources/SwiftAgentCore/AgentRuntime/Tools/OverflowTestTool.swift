import Foundation

/// Overflow test tool for testing context overflow handling. Feature-gated.
/// CC: tools/OverflowTestTool/ — feature('OVERFLOW_TEST_TOOL').
public struct OverflowTestTool: Tool {
    public let name = "OverflowTest"
    public let description = "Generate large output for testing context overflow handling."

    public struct Arguments: Codable, Sendable {
        public var sizeKb: Int

        enum CodingKeys: String, CodingKey {
            case sizeKb = "size_kb"
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "size_kb": JSONSchemaProperty(type: "number", description: "Size of output in KB"),
        ], required: ["size_kb"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("OverflowTest tool requires ant-internal build.")
    }
}
