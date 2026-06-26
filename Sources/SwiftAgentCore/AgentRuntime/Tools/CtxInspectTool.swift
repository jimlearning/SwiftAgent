import Foundation

/// Context inspection tool. Feature-gated behind CONTEXT_COLLAPSE.
/// CC: tools/CtxInspectTool/ — feature('CONTEXT_COLLAPSE').
public struct CtxInspectTool: Tool {
    public let name = "CtxInspect"
    public let description = "Inspect the context collapse and compaction state."

    public struct Arguments: Codable, Sendable {}

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [:])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("CtxInspect tool requires ant-internal build.")
    }
}
