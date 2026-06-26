import Foundation

/// Background PR suggestion tool. Ant-internal only.
/// CC: tools/SuggestBackgroundPRTool/ — process.env.USER_TYPE === 'ant'.
public struct SuggestBackgroundPRTool: Tool {
    public let name = "SuggestBackgroundPR"
    public let description = "Suggest pull request changes asynchronously in the background."

    public struct Arguments: Codable, Sendable {
        public var repo: String
        public var branch: String?

        enum CodingKeys: String, CodingKey {
            case repo
            case branch
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "repo": JSONSchemaProperty(type: "string", description: "GitHub repository (owner/repo)"),
            "branch": JSONSchemaProperty(type: "string", description: "Source branch name"),
        ], required: ["repo"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("SuggestBackgroundPR tool requires ant-internal build.")
    }
}
