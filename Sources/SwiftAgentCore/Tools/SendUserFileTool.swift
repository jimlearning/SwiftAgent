import Foundation

/// Send user file tool. Feature-gated behind KAIROS.
/// CC: tools/SendUserFileTool/ — feature('KAIROS').
public struct SendUserFileTool: Tool {
    public init() {}
    public let name = "SendUserFile"
    public var searchHint: String? { "send files to the user" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Send files to the user through the KAIROS messaging system." }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "Path to the file to send"),
            "message": JSONSchemaProperty(type: "string", description: "Optional message to include with the file"),
        ], required: ["file_path"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "SendUserFile tool requires ant-internal build.", isError: true)
    }
}
