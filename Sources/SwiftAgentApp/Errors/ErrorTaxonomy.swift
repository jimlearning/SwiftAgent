import SwiftUI

// MARK: - Error Severity

/// Severity classification driving presentation mode.
enum ErrorSeverity: Equatable {
    case fatal      // Modal overlay + red icon — blocks further interaction
    case retryable  // Top banner — user can continue using the app
    case warning    // Bottom toast — auto-dismiss after 2-3 seconds
}

// MARK: - App Error Taxonomy

/// Every error path in the application, exhaustively enumerated.
///
/// This enum is the single source of truth for:
/// - Error identity (stable `id` for dedup)
/// - Severity classification (drives `ErrorPresenter` display mode)
/// - User-visible copy (title, message)
/// - Display hints (icon, banner color, action label)
///
/// Views read display properties from the enum rather than switching on
/// individual cases, keeping presentation logic centralized and testable.
enum AppError: Identifiable, Equatable {

    // MARK: Cases

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

    // MARK: Identity

    /// Stable identifier for deduplication in the active error stack.
    var id: String {
        switch self {
        case .sandboxDenied:           return "sandboxDenied"
        case .networkReconnecting:     return "networkReconnecting"
        case .rateLimit429:            return "rateLimit429"
        case .modelError5xx:           return "modelError5xx"
        case .worktreeConflict:        return "worktreeConflict"
        case .invalidAPIKey401:        return "invalidAPIKey401"
        case .lowBalance402:           return "lowBalance402"
        case .appshotPermissionDenied: return "appshotPermissionDenied"
        case .appshotCaptureFailed:    return "appshotCaptureFailed"
        case .mcpDisconnected:         return "mcpDisconnected"
        case .skillLoadFailed:         return "skillLoadFailed"
        case .diffMergeFailed:         return "diffMergeFailed"
        case .goalPersistenceFailed:   return "goalPersistenceFailed"
        case .projectSwitchDataLoss:   return "projectSwitchDataLoss"
        case .threadListPerformance:   return "threadListPerformance"
        case .networkProxy:            return "networkProxy"
        }
    }

    // MARK: Severity

    var severity: ErrorSeverity {
        switch self {
        case .sandboxDenied:           return .fatal
        case .networkReconnecting:     return .retryable
        case .rateLimit429:            return .retryable
        case .modelError5xx:           return .retryable
        case .worktreeConflict:        return .fatal
        case .invalidAPIKey401:        return .fatal
        case .lowBalance402:           return .fatal
        case .appshotPermissionDenied: return .warning
        case .appshotCaptureFailed:    return .warning
        case .mcpDisconnected:         return .retryable
        case .skillLoadFailed:         return .warning
        case .diffMergeFailed:         return .fatal
        case .goalPersistenceFailed:   return .warning
        case .projectSwitchDataLoss:   return .warning
        case .threadListPerformance:   return .warning
        case .networkProxy:            return .retryable
        }
    }

    // MARK: Display — Title

    var title: String {
        switch self {
        case .sandboxDenied:           return "Sandbox Access Denied"
        case .networkReconnecting:     return "Network Disconnected"
        case .rateLimit429:            return "Rate Limit Reached"
        case .modelError5xx:           return "Model Error"
        case .worktreeConflict:        return "Worktree Conflict"
        case .invalidAPIKey401:        return "Invalid API Key"
        case .lowBalance402:           return "Low Balance"
        case .appshotPermissionDenied: return "Permission Required"
        case .appshotCaptureFailed:    return "Capture Failed"
        case .mcpDisconnected:         return "MCP Disconnected"
        case .skillLoadFailed:         return "Skill Load Failed"
        case .diffMergeFailed:         return "Merge Failed"
        case .goalPersistenceFailed:   return "Persistence Warning"
        case .projectSwitchDataLoss:   return "Data Recovered"
        case .threadListPerformance:   return "Large Thread List"
        case .networkProxy:            return "Proxy Required"
        }
    }

    // MARK: Display — Message

    var message: String {
        switch self {
        case .sandboxDenied(let detail):
            return "SwiftAgent tried to access '\(detail)' outside the sandbox. Approve or deny this action."
        case .networkReconnecting:
            return "Connection lost. Attempting to reconnect..."
        case .rateLimit429(let retryAfter):
            return "Too many requests. Retrying in \(retryAfter)s."
        case .modelError5xx(let code):
            return "The model API returned error \(code). You can retry or switch providers."
        case .worktreeConflict(let detail):
            return "\(detail). Choose a base branch to resolve."
        case .invalidAPIKey401:
            return "Your API key is invalid. Update it in Settings."
        case .lowBalance402:
            return "Your account balance is low. Top up to continue."
        case .appshotPermissionDenied:
            return "SwiftAgent needs Accessibility permission to capture screen content."
        case .appshotCaptureFailed:
            return "Cannot capture screen. The target window may be obstructed."
        case .mcpDisconnected(let server):
            return "MCP server '\(server)' disconnected. Attempting to reconnect..."
        case .skillLoadFailed(let name):
            return "Failed to load skill '\(name)'. Check the skill definition for errors."
        case .diffMergeFailed(let detail):
            return "Could not apply diff: \(detail). Manual merge required."
        case .goalPersistenceFailed:
            return "Could not save goal to disk. Falling back to in-memory mode."
        case .projectSwitchDataLoss:
            return "Unsaved changes were auto-stashed. They will be recovered when you return."
        case .threadListPerformance:
            return "Large thread list detected. Using virtual scrolling."
        case .networkProxy:
            return "Network requires HTTP_PROXY configuration. Set it in your environment."
        }
    }

    // MARK: Display — SF Symbol Icon

    var icon: String {
        switch severity {
        case .fatal:     return "xmark.octagon.fill"
        case .retryable: return "arrow.clockwise.circle.fill"
        case .warning:   return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Display — Banner Color

    /// The accent color used for the banner background and bottom rule.
    var bannerColor: Color {
        switch self {
        case .networkReconnecting: return .warning
        case .rateLimit429:        return .warning
        case .modelError5xx:       return .danger
        case .mcpDisconnected:     return .warning
        case .networkProxy:        return .warning
        case .sandboxDenied,
             .worktreeConflict,
             .invalidAPIKey401,
             .lowBalance402,
             .diffMergeFailed:
            return .danger
        case .appshotPermissionDenied,
             .appshotCaptureFailed,
             .skillLoadFailed,
             .goalPersistenceFailed,
             .projectSwitchDataLoss,
             .threadListPerformance:
            return .warning
        }
    }

    // MARK: Display — Action Label

    /// Label for the primary action button shown in banners and modals.
    /// Returns `nil` when no action is available beyond dismiss.
    var actionTitle: String? {
        switch self {
        case .sandboxDenied:           return "Approve"
        case .networkReconnecting:     return nil
        case .rateLimit429:            return "Wait"
        case .modelError5xx:           return "Retry"
        case .worktreeConflict:        return "Choose Base"
        case .invalidAPIKey401:        return "Open Settings"
        case .lowBalance402:           return "Top Up"
        case .appshotPermissionDenied: return "Open Settings"
        case .appshotCaptureFailed:    return nil
        case .mcpDisconnected:         return "Reconnect"
        case .skillLoadFailed:         return nil
        case .diffMergeFailed:         return "Manual Merge"
        case .goalPersistenceFailed:   return nil
        case .projectSwitchDataLoss:   return nil
        case .threadListPerformance:   return nil
        case .networkProxy:            return "Configure"
        }
    }

    // MARK: Display — Action Color

    /// The tint color for the primary action button in modals.
    var actionColor: Color {
        switch self {
        case .sandboxDenied: return .success
        default:             return .accentPrimary
        }
    }
}
