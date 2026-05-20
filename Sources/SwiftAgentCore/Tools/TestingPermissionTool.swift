import Foundation

/// Testing permission tool. Only available in test environments.
/// CC: tools/testing/TestingPermissionTool.ts — process.env.NODE_ENV === 'test'.
public struct TestingPermissionTool: Tool {
    public init() {}
    public let name = "TestingPermission"
    public var searchHint: String? { "test permission system behavior" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Test the tool permission system with various scenarios." }
    public let isReadOnly = false
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "scenario": JSONSchemaProperty(type: "string", description: "Permission test scenario to run"),
        ], required: ["scenario"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "TestingPermission tool is only available in debug/test builds.", isError: true)
    }
}
