import Foundation

/// Agent identity bundle. Forward-compatible with WWDC27 DynamicProfile
/// runtime switching (swap profile mid-session without losing transcript).
public struct AgentProfile: Sendable {
    /// Display name for this agent configuration.
    public var name: String

    /// System instructions defining agent behavior.
    public var instructions: String

    /// Tools available to this agent.
    public var tools: [any RuntimeAgentTool]

    /// Model used for inference (nil = use AgentRuntime default).
    public var model: (any LanguageModel)?

    /// Permission mode for this agent.
    public var permissionMode: AgentPermission

    /// Memory scope defining persistence boundaries.
    public var memoryScope: MemoryScope

    public init(
        name: String,
        instructions: String,
        tools: [any RuntimeAgentTool] = [],
        model: (any LanguageModel)? = nil,
        permissionMode: AgentPermission = .default,
        memoryScope: MemoryScope = .session
    ) {
        self.name = name
        self.instructions = instructions
        self.tools = tools
        self.model = model
        self.permissionMode = permissionMode
        self.memoryScope = memoryScope
    }
}
