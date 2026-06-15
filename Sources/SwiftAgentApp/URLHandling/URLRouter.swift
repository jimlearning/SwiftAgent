import SwiftUI

/// Handles swiftagent:// URL scheme routing (§2.5).
/// Supported URLs:
///   swiftagent://threads/new?prompt=...&path=...
///   swiftagent://threads/<uuid>
///   swiftagent://settings
@MainActor
public final class URLRouter: ObservableObject {
    @Published public var pendingOpenThreadID: String?
    @Published public var pendingNewThreadPrompt: String?
    @Published public var pendingNewThreadPath: String?
    @Published public var pendingOpenSettings: Bool = false

    /// Handle an incoming URL. Returns true if the URL was recognized.
    public func handle(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "swiftagent" else {
            return false
        }

        guard let host = url.host else { return false }

        let path = url.path

        switch host {
        case "threads":
            if path == "/new" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                pendingNewThreadPrompt = components?.queryItems?.first(where: { $0.name == "prompt" })?.value
                pendingNewThreadPath = components?.queryItems?.first(where: { $0.name == "path" })?.value
                return true
            } else if let uuid = UUID(uuidString: String(path.dropFirst())) {
                pendingOpenThreadID = uuid.uuidString
                return true
            }
        case "settings":
            pendingOpenSettings = true
            return true
        default:
            break
        }

        return false
    }

    /// Clear all pending actions after handling.
    public func clearPending() {
        pendingOpenThreadID = nil
        pendingNewThreadPrompt = nil
        pendingNewThreadPath = nil
        pendingOpenSettings = false
    }
}
