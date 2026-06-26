import Foundation

/// Bytecode/tungsten analysis tool. Ant-internal only.
/// CC: tools/TungstenTool/ — gated by USER_TYPE=ant.
/// Migrated to Tool protocol with typed Arguments.
public struct TungstenTool: Tool {
    public let name = "Tungsten"
    public let description = "Analyze Tungsten bytecode artifacts."

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var artifactPath: String

        enum CodingKeys: String, CodingKey {
            case artifactPath = "artifact_path"
        }
    }

    // MARK: - Input Schema

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "artifact_path": JSONSchemaProperty(type: "string", description: "Path to the Tungsten artifact"),
        ], required: ["artifact_path"])
    }

    // MARK: - Init

    public init() {}

    // MARK: - Execute Entry Point

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("Tungsten tool is an ant-internal tool.")
    }
}
