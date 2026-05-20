import Foundation

/// Bytecode/tungsten analysis tool. Ant-internal only.
/// CC: tools/TungstenTool/ — gated by USER_TYPE=ant.
public struct TungstenTool: Tool {
    public init() {}
    public let name = "Tungsten"
    public var searchHint: String? { "analyze bytecode or tungsten artifacts" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Analyze Tungsten bytecode artifacts." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "artifact_path": JSONSchemaProperty(type: "string", description: "Path to the Tungsten artifact"),
        ], required: ["artifact_path"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "Tungsten tool is an ant-internal tool.", isError: true)
    }
}
