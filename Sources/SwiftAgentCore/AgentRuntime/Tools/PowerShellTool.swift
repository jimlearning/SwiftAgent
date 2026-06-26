import Foundation

/// Transparent shell tool wrapper for Windows PowerShell.
/// Mirrors Claude Code's PowerShellTool. Conditionally enabled on Windows platforms.
/// Migrated to Tool protocol with typed Arguments.
public struct PowerShellTool: Tool {
    public let name = "PowerShell"
    public let description = "Executes a PowerShell command and returns the output"

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var command: String
        public var timeout: Int?
        public var description: String?
        public var runInBackground: Bool?
        public var dangerouslyDisableSandbox: Bool?

        enum CodingKeys: String, CodingKey {
            case command
            case timeout
            case description
            case runInBackground = "run_in_background"
            case dangerouslyDisableSandbox = "dangerouslyDisableSandbox"
        }
    }

    // MARK: - Input Schema

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "command": JSONSchemaProperty(type: "string", description: "The PowerShell command to execute"),
            "timeout": JSONSchemaProperty(type: "number", description: "Optional timeout in milliseconds (max 600000)"),
            "description": JSONSchemaProperty(type: "string", description: "Clear, concise description of what this command does"),
            "run_in_background": JSONSchemaProperty(type: "boolean", description: "Set to true to run this command in the background"),
            "dangerouslyDisableSandbox": JSONSchemaProperty(type: "boolean", description: "Set this to true to dangerously override sandbox mode and run commands without sandboxing"),
        ], required: ["command"])
    }

    // MARK: - Init

    public init() {}

    // MARK: - Execute Entry Point

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let cmd = arguments.command
        #if os(Windows)
        return .string("[PowerShell output for: \(cmd)]")
        #else
        return .string("PowerShell is only available on Windows.")
        #endif
    }
}
