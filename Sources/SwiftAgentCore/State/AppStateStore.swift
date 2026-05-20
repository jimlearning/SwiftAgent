import Foundation

/// Minimal pub/sub bridge between actor state and observer code.
/// Not Sendable — used from a single context (main thread/UI).
public final class AppStateStore {
    private let state: AppState
    private let lock = NSLock()
    private var _listeners: [UUID: @Sendable (AppStateSnapshot) -> Void] = [:]

    public init(state: AppState) {
        self.state = state
    }

    public func subscribe(_ callback: @escaping @Sendable (AppStateSnapshot) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        _listeners[id] = callback
        return id
    }

    public func unsubscribe(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        _listeners[token] = nil
    }

    public func notify(snapshot: AppStateSnapshot) {
        lock.lock()
        let listeners = Array(_listeners.values)
        lock.unlock()
        for callback in listeners { callback(snapshot) }
    }

    public var actor: AppState { state }

    /// Convenience: take a snapshot from the actor and notify.
    public func takeSnapshotAndNotify() async {
        let snapshot = await state.getSnapshot()
        notify(snapshot: snapshot)
    }
}

public struct AppStateSnapshot: Sendable {
    public let isProcessing: Bool
    public let streamingOutput: String
    public let statusMessage: String
    public let isPlanModeActive: Bool
    public let isAutoModeActive: Bool
    public let tokenUsage: Usage
    public let sessionTitle: String?
}
