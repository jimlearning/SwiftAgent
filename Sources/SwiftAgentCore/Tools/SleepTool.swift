import Foundation

/// Suspends execution for a specified duration.
/// Matches Claude Code's SleepTool. CC gate: feature(PROACTIVE) || feature(KAIROS).
public struct SleepTool: Tool {
    public let name = "Sleep"
    public var searchHint: String? { "pause execution for a specified duration" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Pause execution for a specified duration" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    /// CC: SleepTool is only compiled in when feature(PROACTIVE) || feature(KAIROS).
    /// SA: gated by CLAUDE_CODE_PROACTIVE env or USER_TYPE=ant.
    public func isEnabled() -> Bool {
        if ProcessInfo.processInfo.environment["USER_TYPE"] == "ant" { return true }
        let v = ProcessInfo.processInfo.environment["CLAUDE_CODE_PROACTIVE"] ?? ""
        let l = v.lowercased()
        return l == "1" || l == "true" || l == "yes" || l == "on"
    }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["duration"] = JSONSchemaProperty(type: "number", description: "Duration in seconds to sleep")
        schema.properties?["reason"] = JSONSchemaProperty(type: "string", description: "Reason for waiting")
        schema.required = ["duration"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        let seconds: Double
        if let d = input["duration"] {
            if case .number(let n) = d { seconds = n }
            else if case .string(let s) = d, let n = Double(s) { seconds = n }
            else { seconds = 0 }
        } else {
            return ToolResult(content: "Error: duration is required", isError: true)
        }

        let reason: String
        if let r = input["reason"], case .string(let s) = r { reason = s }
        else { reason = "no reason specified" }

        let capped = min(seconds, 300)
        try await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
        return ToolResult(content: "Slept for \(capped)s (\(reason))")
    }
}
