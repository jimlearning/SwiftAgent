import Foundation

/// Sends a message to the user.
/// Matches Claude Code's BriefTool / SendUserMessage.
public struct BriefTool: Tool {
    public let name = "SendUserMessage"
    public var aliases: [String] { ["Brief"] }
    public var searchHint: String? { "send a message to the user — your primary visible output channel" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Send a message to the user. Your primary visible output channel — use this for replies the user must see. Text outside this tool is in the detail view and may not be read." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["message"] = JSONSchemaProperty(type: "string", description: "The message for the user. Supports markdown formatting.")
        schema.properties?["attachments"] = JSONSchemaProperty(type: "array", description: "Optional file paths (absolute or relative to cwd) to attach. Use for photos, screenshots, diffs, logs, or any file the user should see alongside your message.")
        schema.properties?["status"] = JSONSchemaProperty(type: "string", description: "Use 'proactive' when you're surfacing something the user hasn't asked for and needs to see now — task completion while they're away, a blocker you hit, an unsolicited status update. Use 'normal' when replying to something the user just said.", enum: ["normal", "proactive"])
        schema.required = ["message"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let msgVal = input["message"], case .string(let message) = msgVal else {
            return ToolResult(content: "Error: message is required", isError: true)
        }

        let status: String
        if let s = input["status"], case .string(let v) = s { status = v } else { status = "normal" }

        var attachmentCount = 0
        if let attVal = input["attachments"], case .array(let attachments) = attVal {
            attachmentCount = attachments.count
        }

        let attachmentSuffix = attachmentCount > 0 ? " (\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s") included)" : ""

        return ToolResult(content: "Message delivered to user.\(attachmentSuffix)")
    }
}
