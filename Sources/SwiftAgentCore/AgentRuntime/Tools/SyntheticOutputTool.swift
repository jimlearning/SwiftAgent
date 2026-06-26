import Foundation

/// Generates synthetic output for testing tool pipelines.
/// Mirrors Claude Code's SyntheticOutputTool.
public struct SyntheticOutputTool: Tool {
    public let name = "SyntheticOutput"
    public let description = "Generates synthetic tool output for testing and verification."

    public struct Arguments: Codable, Sendable {
        public var callID: String
        public var output: String?
        public var isError: Bool?

        enum CodingKeys: String, CodingKey {
            case callID = "callID"
            case output
            case isError
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "callID": JSONSchemaProperty(type: "string", description: "Unique identifier for this synthetic call."),
            "output": JSONSchemaProperty(type: "string", description: "The output string to return."),
            "isError": JSONSchemaProperty(type: "boolean", description: "Whether the result should be marked as an error."),
        ], required: ["callID"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let outputValue = arguments.output ?? ""
        let isErrorValue = arguments.isError ?? false
        if isErrorValue {
            return .string("Error: \(outputValue)")
        }
        return .string(outputValue)
    }
}
