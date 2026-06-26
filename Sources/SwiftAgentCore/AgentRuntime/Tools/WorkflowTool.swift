import Foundation

/// Workflow execution tool. Feature-gated behind WORKFLOW_SCRIPTS.
/// CC: tools/WorkflowTool/ — feature('WORKFLOW_SCRIPTS').
public struct WorkflowTool: Tool {
    public let name = "Workflow"
    public let description = "Execute a predefined workflow script."

    public struct Arguments: Codable, Sendable {
        public var workflowName: String
        public var params: [String: String]?

        enum CodingKeys: String, CodingKey {
            case workflowName = "workflow_name"
            case params
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "workflow_name": JSONSchemaProperty(type: "string", description: "Name of the workflow to execute"),
            "params": JSONSchemaProperty(type: "object", description: "Workflow parameters"),
        ], required: ["workflow_name"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("Workflow tool requires ant-internal build.")
    }
}
