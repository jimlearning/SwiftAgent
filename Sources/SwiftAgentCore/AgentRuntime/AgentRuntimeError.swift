import Foundation

/// Unified error type across ALL subsystems. Replaces fragmented
/// LLMError, DeepSeekError, and ad-hoc error propagation.
public enum AgentRuntimeError: Error, Sendable {
    // MARK: - Model Errors (from LanguageModel / LanguageModelExecutor)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized(reason: String)
    case serverError(statusCode: Int, body: String?)
    case timeout
    case contextSizeExceeded(maxTokens: Int, requestedTokens: Int)
    case invalidResponse(reason: String)

    // MARK: - Memory Errors (from MemoryStore)
    case storageFull(availableBytes: Int64)
    case keyNotFound(key: String, namespace: String)
    case migrationFailed(fromVersion: Int, toVersion: Int, reason: String)

    // MARK: - Permission Errors (from PermissionEngine)
    case permissionDenied(permission: String, reason: String)
    case sandboxViolation(resource: String)

    // MARK: - Tool Errors (from ToolEngine / Tool execution)
    case toolNotFound(name: String)
    case toolExecutionFailed(name: String, reason: String)
    case toolValidationFailed(name: String, field: String, reason: String)

    // MARK: - Graph Errors (from AgentGraph — future)
    case cycleDetected(nodes: [String])
    case nodeFailed(nodeID: String, reason: String)
}
