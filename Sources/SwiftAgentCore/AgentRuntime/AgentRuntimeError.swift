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

extension AgentRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter):
            if let sec = retryAfter { return "Rate limited — retry after \(sec)s" }
            return "Rate limited — slow down"
        case .unauthorized(let reason): return "Unauthorized: \(reason)"
        case .serverError(let code, let body):
            let detail = body.map { ": \($0)" } ?? ""
            if code == 404 { return "HTTP 404 — endpoint or model not found\(detail)" }
            return "HTTP \(code)\(detail)"
        case .timeout: return "Request timed out"
        case .contextSizeExceeded(let max, let req): return "Context size exceeded (max \(max), requested \(req))"
        case .invalidResponse(let reason): return "Invalid response: \(reason)"
        case .storageFull(let bytes): return "Storage full (\(bytes) bytes available)"
        case .keyNotFound(let key, let ns): return "Key \"\(key)\" not found in namespace \"\(ns)\""
        case .migrationFailed(let from, let to, let reason): return "Migration v\(from) -> v\(to) failed: \(reason)"
        case .permissionDenied(let perm, let reason): return "Permission denied: \(perm) — \(reason)"
        case .sandboxViolation(let resource): return "Sandbox violation: \(resource)"
        case .toolNotFound(let name): return "Tool not found: \(name)"
        case .toolExecutionFailed(let name, let reason): return "Tool \"\(name)\" failed: \(reason)"
        case .toolValidationFailed(let name, let field, let reason): return "Tool \"\(name)\" validation failed (\(field): \(reason))"
        case .cycleDetected(let nodes): return "Graph cycle detected: \(nodes.joined(separator: " -> "))"
        case .nodeFailed(let id, let reason): return "Graph node \"\(id)\" failed: \(reason)"
        }
    }
}
