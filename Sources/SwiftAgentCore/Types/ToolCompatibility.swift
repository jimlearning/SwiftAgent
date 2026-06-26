import Foundation

// MARK: - Deprecated Type Compatibility

/// DEPRECATED: Thin compatibility shim so Agent/ and LLM/ files compile
/// until they are deleted in Plans 04-05/04-06.
/// DO NOT use in new code — use ToolOutputValue instead.

/// Legacy ToolResult struct (replaced by ToolOutputValue enum).
public struct ToolResult: Sendable {
    public let content: String
    public let isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

/// Legacy ToolPermissionContext (replaced by ToolUseContext + PermissionMode).
public struct ToolPermissionContext {
    public var mode: PermissionMode
    public var additionalWorkingDirectories: [String: Any] = [:]
    public var alwaysAllowRules: [AnyHashable: [String]] = [:]
    public var alwaysDenyRules: [AnyHashable: [String]] = [:]
    public var alwaysAskRules: [AnyHashable: [String]] = [:]
    public var isBypassPermissionsModeAvailable: Bool = false
    public var isAutoModeAvailable: Bool = false
    public var strippedDangerousRules: [AnyHashable: [String]] = [:]
    public var shouldAvoidPermissionPrompts: Bool = false
    public var awaitAutomatedChecksBeforeDialog: Bool = false
    public var prePlanMode: PermissionMode? = nil

    public init(mode: PermissionMode = .default) {
        self.mode = mode
    }
}

/// Legacy ToolDescriptionOptions (consumed by old Tool.prompt).
public struct ToolDescriptionOptions {
    public let isNonInteractiveSession: Bool
    public let toolPermissionContext: ToolPermissionContext?
    public let tools: [any Sendable]?

    public init(
        isNonInteractiveSession: Bool = false,
        toolPermissionContext: ToolPermissionContext? = nil,
        tools: [any Sendable]? = nil
    ) {
        self.isNonInteractiveSession = isNonInteractiveSession
        self.toolPermissionContext = toolPermissionContext
        self.tools = tools
    }
}

/// Input validation result, matching Claude Code's ValidationResult.
public enum ValidationResult: Sendable {
    case success
    case failure(message: String, errorCode: Int)
}

/// API ToolResultBlockParam format.
public struct ToolResultBlockParam: Sendable {
    public let toolUseID: String
    public let type: String
    public let content: String
    public let isError: Bool?

    public init(toolUseID: String, type: String, content: String, isError: Bool? = nil) {
        self.toolUseID = toolUseID
        self.type = type
        self.content = content
        self.isError = isError
    }
}
