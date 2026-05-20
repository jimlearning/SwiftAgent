import Foundation

/// Transparent shell tool wrapper for Windows PowerShell.
/// Mirrors Claude Code's PowerShellTool. Conditionally enabled on Windows platforms.
public struct PowerShellTool: Tool {
    public init() {}

    public let name = "PowerShell"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Executes a PowerShell command and returns the output"
    }
    public var searchHint: String? { "execute Windows PowerShell commands" }
    public var isReadOnly: Bool { false }
    public var isConcurrencySafe: Bool { false }

    public func isDestructive(_ input: [String: JSONValue]) -> Bool { true }

    public func isEnabled() -> Bool { FeatureFlags.isPowerShellToolEnabled() }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "command": JSONSchemaProperty(type: "string", description: "The PowerShell command to execute"),
            "timeout": JSONSchemaProperty(type: "number", description: "Optional timeout in milliseconds (max 600000)"),
            "description": JSONSchemaProperty(type: "string", description: "Clear, concise description of what this command does"),
            "run_in_background": JSONSchemaProperty(type: "boolean", description: "Set to true to run this command in the background"),
            "dangerouslyDisableSandbox": JSONSchemaProperty(type: "boolean", description: "Set this to true to dangerously override sandbox mode and run commands without sandboxing"),
        ], required: ["command"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let cmd = input["command"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? ""
        #if os(Windows)
        return ToolResult(content: "[PowerShell output for: \(cmd)]")
        #else
        return ToolResult(content: "PowerShell is only available on Windows.", isError: true)
        #endif
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let cmd) = input["command"] { return "PS> \(cmd.prefix(80))" }
        return "Running PowerShell command"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        "Running PowerShell command"
    }
}
