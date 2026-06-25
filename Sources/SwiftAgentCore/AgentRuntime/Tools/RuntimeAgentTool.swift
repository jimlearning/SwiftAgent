import Foundation

/// Simplified tool protocol — the contract between model and agent.
/// ~5 core members. Cross-cutting concerns migrate to ToolMetadata.
///
/// Forward-compatible with WWDC27 AgentIntent auto-discovery.
///
/// - Note: Named `RuntimeAgentTool` with the `Runtime` prefix to coexist
///   with the existing `struct AgentTool: Tool` in Tools/AgentTool.swift,
///   following the established convention (RuntimePermissionEngine,
///   RuntimeMemoryStore, etc.). Will be renamed to `Tool` in Phase 4 after
///   old protocol and struct removal and tool migration.
///
/// - Warning: Using bare `any RuntimeAgentTool` (without angle brackets)
///   loses the `Input` type information, making `call(_:)` impossible.
///   Always use `any RuntimeAgentTool<SomeInput>` existentials when the
///   input type must be preserved.
public protocol RuntimeAgentTool<Input>: Sendable {
    /// The type of input this tool accepts. Must be Codable for
    /// serialization and Sendable for concurrency safety.
    associatedtype Input: Codable & Sendable

    /// PascalCase tool name as seen by the LLM (e.g., "Bash", "Read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    var description: String { get }

    /// JSON Schema for the tool's input parameters.
    /// Uses the existing JSONSchema type from Types/Tool.swift.
    var inputSchema: JSONSchema { get }

    /// Execute the tool with validated input.
    func call(_ input: Input) async throws -> ToolOutputValue
}
