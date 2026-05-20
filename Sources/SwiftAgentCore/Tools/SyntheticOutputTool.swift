import Foundation

/// Generates synthetic output for testing tool pipelines.
/// Mirrors Claude Code's SyntheticOutputTool.
public struct SyntheticOutputTool: Tool {
    public init() {}
    public let name = "StructuredOutput"
    public var searchHint: String? { "return the final response as structured JSON" }
    public let isReadOnly = true
    public let isConcurrencySafe = true

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Generates synthetic tool output for testing and verification."
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "callID": JSONSchemaProperty(type: "string", description: "Unique identifier for this synthetic call."),
            "output": JSONSchemaProperty(type: "string", description: "The output string to return."),
            "isError": JSONSchemaProperty(type: "boolean", description: "Whether the result should be marked as an error."),
        ], required: ["callID"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let outputValue = input["output"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? ""
        let isErrorValue = input["isError"].flatMap { if case .bool(let b) = $0 { return b }; return nil } ?? false
        return ToolResult(content: outputValue, isError: isErrorValue)
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let id) = input["callID"] { return "Synthetic call \(id)" }
        return "Synthetic output"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "Generating synthetic output"
    }
}
