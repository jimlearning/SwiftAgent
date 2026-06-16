import Foundation

/// A file (or other artifact) that the user has attached to a thread's
/// composer but hasn't sent yet. The Files panel uses this when the
/// user picks "Add to chat" from a file's context menu.
public struct ComposerAttachment: Identifiable, Equatable, Hashable, Sendable {
    /// Case names avoid `file` / `image` / `url` because those are also
    /// valid SwiftUI / Foundation APIs and Xcode was mis-resolving the
    /// enum case as `.file` from another type. Prefixing with the
    /// domain (`attach`) keeps the call site unambiguous.
    public enum Kind: Equatable, Hashable, Sendable {
        case attachFile(path: String, displayName: String)
        case attachImage(path: String, displayName: String)
        case attachURL(string: String, displayName: String)
    }

    public let id: String
    public let kind: Kind
    public let addedAt: Date

    public init(id: String = UUID().uuidString, kind: Kind, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.addedAt = addedAt
    }

    public var displayName: String {
        switch kind {
        case .attachFile(_, let n), .attachImage(_, let n), .attachURL(_, let n):
            return n
        }
    }

    public var path: String? {
        switch kind {
        case .attachFile(let p, _), .attachImage(let p, _): return p
        case .attachURL: return nil
        }
    }
}
