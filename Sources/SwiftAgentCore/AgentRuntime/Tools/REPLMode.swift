import Foundation

/// Reports or toggles REPL (Read-Eval-Print Loop) mode.
/// Matches Claude Code's REPL mode constants and behavior.
public struct REPLModeTool: Tool {
    public let name = "REPLMode"
    public let description = "Check or toggle REPL mode. When REPL mode is enabled, write/edit/bash tools are routed through a REPL wrapper to batch operations."

    public struct Arguments: Codable, Sendable {
        public var action: String?

        enum CodingKeys: String, CodingKey {
            case action
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["action"] = JSONSchemaProperty(
            type: "string",
            description: "\"status\" to check current mode, or \"toggle\" to flip it. Defaults to \"status\".",
            enum: ["status", "toggle"]
        )
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let action = arguments.action ?? "status"
        let enabled = REPLModeTool.isReplModeEnabled()

        switch action {
        case "toggle":
            return .string("REPL mode toggle is only available via CLI environment variables (CLAUDE_CODE_REPL=0 to disable, CLAUDE_REPL_MODE=1 to enable). Current status: \(enabled ? "enabled" : "disabled").")
        default:
            return .string("REPL mode is currently \(enabled ? "enabled" : "disabled").")
        }
    }

    /// Checks whether REPL mode is enabled.
    /// REPL mode is default-on for ants in the interactive CLI.
    /// Set CLAUDE_CODE_REPL=0 to disable, or CLAUDE_REPL_MODE=1 to force on.
    public static func isReplModeEnabled() -> Bool {
        if let v = ProcessInfo.processInfo.environment["CLAUDE_CODE_REPL"],
           ["0", "false", "no"].contains(v.lowercased()) {
            return false
        }
        if let v = ProcessInfo.processInfo.environment["CLAUDE_REPL_MODE"],
           ["1", "true", "yes"].contains(v.lowercased()) {
            return true
        }
        let userType = ProcessInfo.processInfo.environment["USER_TYPE"] ?? ""
        let entrypoint = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] ?? ""
        return userType == "ant" && entrypoint == "cli"
    }
}
