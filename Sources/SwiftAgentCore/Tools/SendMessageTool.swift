import Foundation

/// Sends messages to agent teammates via the swarm protocol.
/// Matches Claude Code's SendMessageTool.
public struct SendMessageTool: Tool {
    public let name = "SendMessage"
    public var searchHint: String? { "send messages to agent teammates (swarm protocol)" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Send a message to a teammate agent. Use this to coordinate work across multiple agents, request plan approvals, or manage lifecycle events." }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["to"] = JSONSchemaProperty(type: "string", description: "Recipient: teammate name, or \"*\" for broadcast to all teammates")
        schema.properties?["summary"] = JSONSchemaProperty(type: "string", description: "A 5-10 word summary shown as a preview in the UI (required when message is a string)")
        schema.properties?["message"] = JSONSchemaProperty(type: "string", description: "Plain text message content, or a structured message object with type field")
        schema.required = ["to", "message"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let toVal = input["to"], case .string(let recipient) = toVal, !recipient.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResult(content: "Error: to must not be empty", isError: true)
        }
        guard let msgVal = input["message"], case .string(let message) = msgVal else {
            return ToolResult(content: "Error: message is required", isError: true)
        }

        let summary: String?
        if let s = input["summary"], case .string(let sum) = s { summary = sum } else { summary = nil }

        if recipient == "*" {
            return ToolResult(content: """
                {"success": true, "message": "Message broadcast to teammates.", "recipients": [], "routing": {"sender": "agent", "target": "@team", "summary": "\(summary ?? "")", "content": "\(message)"}}
                """)
        }

        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            switch type {
            case "shutdown_request":
                let requestId = json["request_id"] as? String ?? UUID().uuidString
                return ToolResult(content: """
                    {"success": true, "message": "Shutdown request sent to \(recipient). Request ID: \(requestId)", "request_id": "\(requestId)", "target": "\(recipient)"}
                    """)
            case "shutdown_response":
                let requestId = json["request_id"] as? String ?? ""
                let approve = json["approve"] as? Bool ?? false
                let msg = approve ? "Shutdown approved. Agent is now exiting." : "Shutdown rejected."
                return ToolResult(content: """
                    {"success": true, "message": "\(msg)", "request_id": "\(requestId)"}
                    """)
            case "plan_approval_response":
                let requestId = json["request_id"] as? String ?? ""
                let approve = json["approve"] as? Bool ?? false
                let feedback = json["feedback"] as? String ?? ""
                let msg = approve ? "Plan approved for \(recipient)." : "Plan rejected with feedback: \"\(feedback)\""
                return ToolResult(content: """
                    {"success": true, "message": "\(msg)", "request_id": "\(requestId)"}
                    """)
            default:
                break
            }
        }

        return ToolResult(content: """
            {"success": true, "message": "Message sent to \(recipient)'s inbox", "routing": {"sender": "agent", "target": "@\(recipient)", "summary": "\(summary ?? "")", "content": "\(message)"}}
            """)
    }
}
