import Foundation

// MARK: - MCP Resource Types

/// Resource description returned by resources/list.
/// Matches MCP spec Resource type.
public struct MCPResourceDescription: Sendable {
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

/// Content returned by resources/read.
/// Matches MCP spec ResourceContents type.
public struct MCPResourceContent: Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String?
    public let blob: String?

    public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
}

/// Result from resources/read containing one or more contents.
public struct MCPResourceReadResult: Sendable {
    public let contents: [MCPResourceContent]

    public init(contents: [MCPResourceContent]) {
        self.contents = contents
    }
}

// MARK: - MCP Prompt Types

/// Prompt description returned by prompts/list.
/// Matches MCP spec Prompt type.
public struct MCPPromptDescription: Sendable {
    public let name: String
    public let description: String?
    public let arguments: [MCPPromptArgument]?

    public init(name: String, description: String? = nil, arguments: [MCPPromptArgument]? = nil) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
}

/// Prompt argument descriptor.
/// Matches MCP spec PromptArgument type.
public struct MCPPromptArgument: Sendable {
    public let name: String
    public let description: String?
    public let required: Bool

    public init(name: String, description: String? = nil, required: Bool = false) {
        self.name = name
        self.description = description
        self.required = required
    }
}

/// Result from prompts/get containing messages.
/// Matches MCP spec GetPromptResult type.
public struct MCPPromptResult: Sendable {
    public let description: String?
    public let messages: [MCPPromptMessage]

    public init(description: String? = nil, messages: [MCPPromptMessage]) {
        self.description = description
        self.messages = messages
    }
}

/// A message in a prompt result.
/// Matches MCP spec PromptMessage type.
public struct MCPPromptMessage: Sendable {
    public let role: String  // "user" | "assistant"
    public let content: MCPPromptContent

    public init(role: String, content: MCPPromptContent) {
        self.role = role
        self.content = content
    }
}

/// Content of a prompt message.
/// Matches MCP spec (text or image content).
public enum MCPPromptContent: Sendable {
    case text(String)
    case image(type: String, data: String, mimeType: String)
}
