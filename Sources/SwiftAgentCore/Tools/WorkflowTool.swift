import Foundation

/// Workflow execution tool. Feature-gated behind WORKFLOW_SCRIPTS.
/// CC: tools/WorkflowTool/ — feature('WORKFLOW_SCRIPTS').
public struct WorkflowTool: Tool {
    public init() {}
    public let name = "Workflow"
    public var searchHint: String? { "execute bundled workflows" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Execute a predefined workflow script." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool {
        ProcessInfo.processInfo.environment["USER_TYPE"] == "ant"
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "workflow_name": JSONSchemaProperty(type: "string", description: "Name of the workflow to execute"),
            "params": JSONSchemaProperty(type: "object", description: "Workflow parameters"),
        ], required: ["workflow_name"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        return ToolResult(content: "Workflow tool requires ant-internal build.", isError: true)
    }
}
