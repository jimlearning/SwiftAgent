import Foundation

/// A file (or other artifact) that the user has attached to a thread's
/// composer but hasn't sent yet. The Files panel uses this when the
/// user picks "Add to chat" from a file's context menu.
public struct ComposerAttachment: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case file(path: String, displayName: String)
        case image(path: String, displayName: String)
        case url(string: String, displayName: String)
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
        case .file(_, let n), .image(_, let n), .url(_, let n):
            return n
        }
    }

    public var path: String? {
        switch kind {
        case .file(let p, _), .image(let p, _): return p
        case .url: return nil
        }
    }
}
