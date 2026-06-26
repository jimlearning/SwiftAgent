import Foundation

// MARK: - LanguageModelSessionConfiguration

/// Bundled configuration for creating a LanguageModelSession.
/// Mirrors Apple's FoundationModels `LanguageModelSession.init(model:tools:instructions:)`.
///
/// Named `LanguageModelSessionConfiguration` rather than nested inside
/// `LanguageModelSession` because Swift protocols cannot host nested types.
/// Apple's FoundationModels uses a class, which permits nesting.
///
/// SwiftAgent extends the base configuration with agent-level subsystems
/// (Memory, Permission, Hooks) that FoundationModels leaves to higher-level
/// frameworks like AgentKit (predicted WWDC27).
public struct LanguageModelSessionConfiguration: Sendable {
    public var model: any LanguageModel
    public var tools: [any Tool]
    public var instructions: String?
    public var memoryStore: any SessionMemoryStore
    public var permissionEngine: any SessionPermissionEngine
    public var contextManager: any SessionContextManager
    public var hookSystem: any SessionHookSystem
    public var profile: AgentProfile?

    public init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        instructions: String? = nil,
        memoryStore: any SessionMemoryStore,
        permissionEngine: any SessionPermissionEngine,
        contextManager: any SessionContextManager = NoOpSessionContextManager(),
        hookSystem: any SessionHookSystem = NoOpSessionHookSystem(),
        profile: AgentProfile? = nil
    ) {
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.memoryStore = memoryStore
        self.permissionEngine = permissionEngine
        self.contextManager = contextManager
        self.hookSystem = hookSystem
        self.profile = profile
    }
}
