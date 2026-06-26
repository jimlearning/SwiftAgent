import Foundation

/// Terminal capture tool. Feature-gated behind TERMINAL_PANEL.
/// CC: tools/TerminalCaptureTool/ — feature('TERMINAL_PANEL').
/// Migrated to Tool protocol with typed Arguments.
public struct TerminalCaptureTool: Tool {
    public let name = "TerminalCapture"
    public let description = "Capture terminal output from the current session."

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var action: String

        enum CodingKeys: String, CodingKey {
            case action
        }
    }

    // MARK: - Input Schema

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "action": JSONSchemaProperty(type: "string", description: "Capture action: screenshot or text"),
        ], required: ["action"])
    }

    // MARK: - Init

    public init() {}

    // MARK: - Execute Entry Point

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        return .string("TerminalCapture tool requires ant-internal build.")
    }
}
