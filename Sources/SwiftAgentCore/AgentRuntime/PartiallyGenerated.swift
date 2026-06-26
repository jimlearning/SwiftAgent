import Foundation

// MARK: - PartiallyGenerated

/// Snapshot accumulation and diffing for structured output streaming.
///
/// As the model emits partial JSON, the runtime periodically decodes it
/// into a typed `T` snapshot. `PartiallyGenerated` carries the current
/// snapshot, the previous snapshot (for diff computation), and the set
/// of property keys that changed since the last emission.
///
/// ## Usage in LanguageModelSessionImpl (Plan 02-03)
/// ```
/// var state = PartiallyGenerated<BashParams>()
/// for try await event in channel.stream {
///     if case .textDelta(let text) = event {
///         if let decoded = try? JSONDecoder().decode(BashParams.self, from: Data(text.utf8)) {
///             state.previousSnapshot = state.snapshot
///             state.snapshot = decoded
///             state.changedKeys = diffSnapshots(state.previousSnapshot, decoded)
///             state.rawAccumulatedText = text
///         }
///     }
/// }
/// ```
public struct PartiallyGenerated<T: Codable & Sendable>: Sendable {
    /// The complete snapshot of all properties accumulated so far.
    /// `nil` until the first successful decode.
    public var snapshot: T?

    /// The previous snapshot for diff computation.
    /// `nil` on the first emission.
    public var previousSnapshot: T?

    /// Property keys that changed since `previousSnapshot`.
    /// Empty on the first emission.
    public var changedKeys: Set<String>

    /// Whether generation is complete (model emitted final token).
    public var isComplete: Bool

    /// Cumulative raw text accumulated so far.
    /// For debugging and shadow-mode validation.
    public var rawAccumulatedText: String

    public init(
        snapshot: T? = nil,
        previousSnapshot: T? = nil,
        changedKeys: Set<String> = [],
        isComplete: Bool = false,
        rawAccumulatedText: String = ""
    ) {
        self.snapshot = snapshot
        self.previousSnapshot = previousSnapshot
        self.changedKeys = changedKeys
        self.isComplete = isComplete
        self.rawAccumulatedText = rawAccumulatedText
    }
}

// MARK: - Diff Helper

/// Compute the set of property keys that differ between two snapshots.
///
/// Uses `Mirror(reflecting:)` to iterate child properties and compares
/// their string representations. Keys are derived from child labels.
/// Returns keys where the value differs between `old` and `new`.
///
/// - Parameters:
///   - old: The previous snapshot.
///   - new: The current snapshot.
/// - Returns: Set of property names whose values changed.
public func diffSnapshots<T>(_ old: T, _ new: T) -> Set<String> {
    let oldMirror = Mirror(reflecting: old)
    let newMirror = Mirror(reflecting: new)

    let oldChildren = Array(oldMirror.children)
    let newChildren = Array(newMirror.children)

    let count = min(oldChildren.count, newChildren.count)
    var changed: Set<String> = []

    for i in 0..<count {
        guard let label = oldChildren[i].label,
              let _ = newChildren[i].label else {
            continue
        }
        let oldValue = String(describing: oldChildren[i].value)
        let newValue = String(describing: newChildren[i].value)
        if oldValue != newValue {
            changed.insert(label)
        }
    }

    return changed
}
