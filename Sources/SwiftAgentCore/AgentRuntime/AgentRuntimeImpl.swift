import Foundation

/// Concrete actor implementation of the AgentRuntime protocol.
/// Owns the agent loop: prompt → executor → tool-call processing → transcript → memory.
/// Guards against reentrancy, routes all subsystem calls through protocol boundaries,
/// and provides both streaming (AsyncThrowingStream) and non-streaming (Transcript) APIs.
public actor AgentRuntimeImpl: AgentRuntime {

    // MARK: - Subsystem Properties (AgentRuntime conformance)

    public let modelProvider: any LanguageModel
    public let memoryStore: any RuntimeMemoryStore
    public let permissionEngine: any RuntimePermissionEngine
    public let toolEngine: any ToolEngine
    public let contextManager: any RuntimeContextManager
    public let profileManager: any ProfileManager
    public let graphEngine: (any AgentGraph)?
    public let hookSystem: any RuntimeHookSystem

    // MARK: - Internal State

    private var transcript: Transcript = Transcript()
    private var isResponding: Bool = false

    // MARK: - Initialization

    public init(
        modelProvider: any LanguageModel,
        memoryStore: any RuntimeMemoryStore,
        permissionEngine: any RuntimePermissionEngine,
        toolEngine: any ToolEngine,
        contextManager: any RuntimeContextManager = NoOpContextManager(),
        profileManager: any ProfileManager = NoOpProfileManager(),
        graphEngine: (any AgentGraph)? = nil,
        hookSystem: any RuntimeHookSystem = NoOpHookSystem()
    ) {
        self.modelProvider = modelProvider
        self.memoryStore = memoryStore
        self.permissionEngine = permissionEngine
        self.toolEngine = toolEngine
        self.contextManager = contextManager
        self.profileManager = profileManager
        self.graphEngine = graphEngine
        self.hookSystem = hookSystem
    }

    // MARK: - AgentRuntime Conformance (stubs — filled in Task 2)

    public func respond(to prompt: String) async throws -> Transcript {
        throw AgentRuntimeError.rateLimited(retryAfter: nil)
    }

    public func streamResponse(to prompt: String) -> AsyncThrowingStream<SessionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
