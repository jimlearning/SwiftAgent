import Foundation

/// Unified error type across ALL subsystems. Replaces fragmented
/// LLMError, DeepSeekError, and ad-hoc error propagation.
///
/// Mirrors Apple's `LanguageModelError` pattern with dedicated info structs
/// for rich error context (FoundationModels, iOS 27+).
public enum AgentRuntimeError: Error, Sendable {

    // MARK: - Error Info Structs (Apple-aligned)

    /// Context window exceeded. Mirrors Apple's `LanguageModelError.ContextSizeExceeded`.
    public struct ContextSizeExceeded: Sendable {
        public let maxTokens: Int
        public let requestedTokens: Int

        public init(maxTokens: Int, requestedTokens: Int) {
            self.maxTokens = maxTokens
            self.requestedTokens = requestedTokens
        }
    }

    /// Rate limited with optional retry hint. Mirrors Apple's `LanguageModelError.RateLimited`.
    public struct RateLimited: Sendable {
        public let retryAfter: TimeInterval?

        public init(retryAfter: TimeInterval?) {
            self.retryAfter = retryAfter
        }
    }

    /// Model refused the request. Mirrors Apple's `LanguageModelError.Refusal`.
    public struct Refusal: Sendable {
        public let reason: String

        public init(reason: String) {
            self.reason = reason
        }
    }

    /// Request timed out. Mirrors Apple's `LanguageModelError.Timeout`.
    public struct Timeout: Sendable {
        public let duration: TimeInterval?

        public init(duration: TimeInterval?) {
            self.duration = duration
        }
    }

    /// Safety guardrail triggered. Mirrors Apple's `LanguageModelError.GuardrailViolation`.
    public struct GuardrailViolation: Sendable {
        public let guardrail: String
        public let reason: String

        public init(guardrail: String, reason: String) {
            self.guardrail = guardrail
            self.reason = reason
        }
    }

    /// Unsupported capability requested. Mirrors Apple's `LanguageModelError.UnsupportedCapability`.
    public struct UnsupportedCapability: Sendable {
        public let capability: String

        public init(capability: String) {
            self.capability = capability
        }
    }

    // MARK: - Model Errors (from LanguageModel / LanguageModelExecutor)

    case rateLimited(RateLimited)
    case unauthorized(reason: String)
    case serverError(statusCode: Int, body: String?)
    case timeout(Timeout)
    case contextSizeExceeded(ContextSizeExceeded)
    case invalidResponse(reason: String)
    case refusal(Refusal)
    case guardrailViolation(GuardrailViolation)
    case unsupportedCapability(UnsupportedCapability)

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
        case .rateLimited(let info):
            if let sec = info.retryAfter { return "Rate limited — retry after \(sec)s" }
            return "Rate limited — slow down"
        case .unauthorized(let reason): return "Unauthorized: \(reason)"
        case .serverError(let code, let body):
            let detail = body.map { ": \($0)" } ?? ""
            if code == 404 { return "HTTP 404 — endpoint or model not found\(detail)" }
            return "HTTP \(code)\(detail)"
        case .timeout(let info):
            if let dur = info.duration { return "Request timed out after \(dur)s" }
            return "Request timed out"
        case .contextSizeExceeded(let info): return "Context size exceeded (max \(info.maxTokens), requested \(info.requestedTokens))"
        case .invalidResponse(let reason): return "Invalid response: \(reason)"
        case .refusal(let info): return "Model refused: \(info.reason)"
        case .guardrailViolation(let info): return "Guardrail \"\(info.guardrail)\" violated: \(info.reason)"
        case .unsupportedCapability(let info): return "Unsupported capability: \(info.capability)"
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
