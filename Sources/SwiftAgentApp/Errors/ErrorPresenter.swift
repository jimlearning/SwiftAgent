import SwiftUI

/// Central error model that all 16 error states flow through.
enum AppError: Identifiable, Equatable {
    case sandboxDenied(String)
    case networkReconnecting
    case rateLimit429(retryAfter: Int)
    case modelError5xx(statusCode: Int)
    case worktreeConflict(String)
    case invalidAPIKey401
    case lowBalance402
    case appshotPermissionDenied
    case appshotCaptureFailed
    case mcpDisconnected(String)
    case skillLoadFailed(String)
    case diffMergeFailed(String)
    case goalPersistenceFailed
    case projectSwitchDataLoss
    case threadListPerformance
    case networkProxy

    var id: String {
        switch self {
        case .sandboxDenied: return "sandboxDenied"
        case .networkReconnecting: return "networkReconnecting"
        case .rateLimit429: return "rateLimit429"
        case .modelError5xx: return "modelError5xx"
        case .worktreeConflict: return "worktreeConflict"
        case .invalidAPIKey401: return "invalidAPIKey401"
        case .lowBalance402: return "lowBalance402"
        case .appshotPermissionDenied: return "appshotPermissionDenied"
        case .appshotCaptureFailed: return "appshotCaptureFailed"
        case .mcpDisconnected: return "mcpDisconnected"
        case .skillLoadFailed: return "skillLoadFailed"
        case .diffMergeFailed: return "diffMergeFailed"
        case .goalPersistenceFailed: return "goalPersistenceFailed"
        case .projectSwitchDataLoss: return "projectSwitchDataLoss"
        case .threadListPerformance: return "threadListPerformance"
        case .networkProxy: return "networkProxy"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .sandboxDenied: return .fatal
        case .networkReconnecting: return .retryable
        case .rateLimit429: return .retryable
        case .modelError5xx: return .retryable
        case .worktreeConflict: return .fatal
        case .invalidAPIKey401: return .fatal
        case .lowBalance402: return .fatal
        case .appshotPermissionDenied: return .warning
        case .appshotCaptureFailed: return .warning
        case .mcpDisconnected: return .retryable
        case .skillLoadFailed: return .warning
        case .diffMergeFailed: return .fatal
        case .goalPersistenceFailed: return .warning
        case .projectSwitchDataLoss: return .warning
        case .threadListPerformance: return .warning
        case .networkProxy: return .retryable
        }
    }

    var title: String {
        switch self {
        case .sandboxDenied: return "Sandbox Access Denied"
        case .networkReconnecting: return "Network Disconnected"
        case .rateLimit429: return "Rate Limit Reached"
        case .modelError5xx: return "Model Error"
        case .worktreeConflict: return "Worktree Conflict"
        case .invalidAPIKey401: return "Invalid API Key"
        case .lowBalance402: return "Low Balance"
        case .appshotPermissionDenied: return "Permission Required"
        case .appshotCaptureFailed: return "Capture Failed"
        case .mcpDisconnected: return "MCP Disconnected"
        case .skillLoadFailed: return "Skill Load Failed"
        case .diffMergeFailed: return "Merge Failed"
        case .goalPersistenceFailed: return "Persistence Warning"
        case .projectSwitchDataLoss: return "Data Recovered"
        case .threadListPerformance: return "Large Thread List"
        case .networkProxy: return "Proxy Required"
        }
    }

    var message: String {
        switch self {
        case .sandboxDenied(let detail): return "SwiftAgent tried to access '\(detail)' outside the sandbox. Approve or deny this action."
        case .networkReconnecting: return "Connection lost. Attempting to reconnect..."
        case .rateLimit429(let retryAfter): return "Too many requests. Retrying in \(retryAfter)s."
        case .modelError5xx(let code): return "DeepSeek API returned error \(code). You can retry or switch models."
        case .worktreeConflict(let detail): return "\(detail). Choose a base branch to resolve."
        case .invalidAPIKey401: return "Your API key is invalid. Update it in Settings."
        case .lowBalance402: return "Your DeepSeek account balance is low. Top up to continue."
        case .appshotPermissionDenied: return "SwiftAgent needs Accessibility permission to capture screen content."
        case .appshotCaptureFailed: return "Cannot capture screen. The target window may be obstructed."
        case .mcpDisconnected(let server): return "MCP server '\(server)' disconnected. Attempting to reconnect..."
        case .skillLoadFailed: return "" // Handled silently in logs
        case .diffMergeFailed(let detail): return "Could not apply diff: \(detail). Manual merge required."
        case .goalPersistenceFailed: return "Could not save goal to disk. Falling back to in-memory mode."
        case .projectSwitchDataLoss: return "Unsaved changes were auto-stashed. They will be recovered when you return."
        case .threadListPerformance: return "Large thread list detected. Using virtual scrolling."
        case .networkProxy: return "Network requires HTTP_PROXY configuration. Set it in your environment."
        }
    }

    var icon: String {
        switch severity {
        case .fatal: return "xmark.octagon.fill"
        case .retryable: return "arrow.clockwise.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

enum ErrorSeverity {
    case fatal      // Modal + red icon
    case retryable  // Top banner + still usable
    case warning    // Bottom toast, auto-dismiss
}

// MARK: - Error Presenter

/// Observable object that manages error presentation across the app.
@MainActor
final class ErrorPresenter: ObservableObject {
    @Published var activeErrors: [AppError] = []
    @Published var showModal: Bool = false
    @Published var currentModalError: AppError?

    static let shared = ErrorPresenter()

    /// Present a fatal error as a modal.
    func presentModal(_ error: AppError) {
        currentModalError = error
        showModal = true
    }

    /// Add a retryable or warning error to the stack.
    func present(_ error: AppError) {
        switch error.severity {
        case .fatal:
            presentModal(error)
        case .retryable, .warning:
            if !activeErrors.contains(where: { $0.id == error.id }) {
                activeErrors.append(error)
            }
        }
    }

    /// Dismiss a specific error.
    func dismiss(_ error: AppError) {
        activeErrors.removeAll { $0.id == error.id }
        if currentModalError?.id == error.id {
            showModal = false
            currentModalError = nil
        }
    }

    /// Dismiss the current modal.
    func dismissModal() {
        showModal = false
        currentModalError = nil
    }
}
