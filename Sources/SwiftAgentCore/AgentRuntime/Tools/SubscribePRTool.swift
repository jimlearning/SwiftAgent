import Foundation

/// Subscribe to PR updates tool. Feature-gated behind KAIROS_GITHUB_WEBHOOKS.
/// CC: tools/SubscribePRTool/ — feature('KAIROS_GITHUB_WEBHOOKS').
public struct SubscribePRTool: Tool {
    public let name = "SubscribePR"
    public let description = "Subscribe to GitHub pull request webhook notifications."

    public struct Arguments: Codable, Sendable {
        public var repo: String
        public var prNumber: Int

        enum CodingKeys: String, CodingKey {
            case repo
            case prNumber = "pr_number"
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "repo": JSONSchemaProperty(type: "string", description: "GitHub repository (owner/repo)"),
            "pr_number": JSONSchemaProperty(type: "number", description: "Pull request number"),
        ], required: ["repo", "pr_number"])
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("SubscribePR tool requires ant-internal build.")
    }
}
