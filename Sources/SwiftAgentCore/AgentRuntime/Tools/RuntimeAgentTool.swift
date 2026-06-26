import Foundation

/// Tool protocol — the contract between model and agent.
/// ~5 core members. Cross-cutting concerns migrate to ToolMetadata.
/// Mirrors Apple's FoundationModels `Tool` protocol.
///
/// Forward-compatible with WWDC27 AgentIntent auto-discovery.
///
/// - Note: Formerly `RuntimeAgentTool` — renamed to `Tool` after the old
///   `Tool` protocol was deleted from Types/Tool.swift in Phase 4 (Plan 04-03).
///
/// - Warning: Using bare `any Tool` (without angle brackets)
///   loses the `Arguments` type information, making `call(arguments:)` impossible.
///   Always use `any Tool<SomeArguments>` existentials when the
///   arguments type must be preserved.
public protocol Tool<Arguments>: Sendable {
    /// The type of arguments this tool accepts. Must be Codable for
    /// serialization and Sendable for concurrency safety.
    associatedtype Arguments: Codable & Sendable

    /// PascalCase tool name as seen by the LLM (e.g., "Bash", "Read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    var description: String { get }

    /// JSON Schema for the tool's input parameters.
    var inputSchema: JSONSchema { get }

    /// Execute the tool with validated arguments.
    func call(arguments: Arguments) async throws -> ToolOutputValue

    /// Type-erased call path — decodes `Data` input into `Arguments` and
    /// delegates to `call(arguments:)`. Works through `any Tool` existentials
    /// because the signature does not expose the associated `Arguments` type.
    func _callFromData(_ input: Data) async throws -> ToolOutputValue
}

extension Tool {
    public func _callFromData(_ input: Data) async throws -> ToolOutputValue {
        let args = try JSONDecoder().decode(Arguments.self, from: input)
        return try await self.call(arguments: args)
    }
}

/// Backward-compatibility typealias.
public typealias RuntimeAgentTool = Tool

// MARK: - Temporary Tool Extensions (for deprecated Agent/ code)

/// Temporary defaults for old Tool protocol members still called by Agent/ and LLM/ code.
/// These files will be deleted in Plans 04-05/04-06. Remove this extension afterward.
extension Tool {
    public var isReadOnly: Bool { false }
    public var isConcurrencySafe: Bool { false }
    public var isMcp: Bool { false }
    public var isLsp: Bool { false }
    public var shouldDefer: Bool { false }
    public var alwaysLoad: Bool { false }
    public var maxResultSizeChars: Int { 100_000 }
    public var strict: Bool { false }
    public var outputSchema: JSONSchema? { nil }
    public var inputJSONSchema: JSONSchema? { nil }
    public var mcpInfo: MCPToolInfo? { nil }
    public var aliases: [String] { [] }
    public var searchHint: String? { nil }

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { description }
    public func isReadOnly(_ input: [String: JSONValue]) -> Bool { isReadOnly }
    public func isConcurrencySafe(_ input: [String: JSONValue]) -> Bool { isConcurrencySafe }
    public func interruptBehavior() -> InterruptBehavior { .block }
    public func isOpenWorld(_ input: [String: JSONValue]) -> Bool { false }
    public func requiresUserInteraction() -> Bool { false }
    public func isDestructive(_ input: [String: JSONValue]) -> Bool { false }
    public func isEnabled() -> Bool { true }
    public func getPath(_ input: [String: JSONValue]) -> String? { nil }
    public func userFacingName(_ input: [String: JSONValue]) -> String { name }
    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any { "" }
    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? { nil }
    public func getActivityDescription(_ input: [String: JSONValue]) -> String? { nil }
    public func isTransparentWrapper() -> Bool { false }
    public func extractSearchText(_ output: ToolResult) -> String { output.content }
    public func isResultTruncated(_ output: ToolResult) -> Bool { false }

    public func checkPermissions(input: [String: JSONValue], context: ToolUseContext) async -> PermissionResult { .allow(PermissionAllowDecision()) }
    public func validateInput(_ input: [String: JSONValue], context: ToolUseContext) async -> ValidationResult { .success }
    public func mapToolResultToToolResultBlockParam(_ content: ToolResult, toolUseID: String) -> ToolResultBlockParam {
        ToolResultBlockParam(toolUseID: toolUseID, type: "tool_result", content: content.content, isError: content.isError)
    }
    public func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String {
        description
    }
}
