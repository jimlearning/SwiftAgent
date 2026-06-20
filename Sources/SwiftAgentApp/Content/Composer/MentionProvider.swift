import Foundation

// MARK: - Mention Kind

/// Categories of @-mentionable items.
public enum MentionKind: String, CaseIterable, Sendable {
    case file    // Project files
    case skill   // Agent skills
    case mcp     // MCP server tools
    case thread  // Conversation threads
}

// MARK: - Mention Item

/// A single @-mention candidate displayed in the autocomplete popup.
public struct MentionItem: Identifiable, Sendable, Equatable {
    public let id: String
    /// The text inserted into the composer (e.g. `@MyFile.swift`).
    public let mentionText: String
    /// Display name (e.g. file basename, skill name).
    public let displayName: String
    /// Secondary detail (e.g. file path, skill description).
    public let detail: String?
    /// Category for icon and grouping.
    public let kind: MentionKind
    /// SF Symbol name for the icon.
    public let iconName: String

    public init(
        id: String,
        mentionText: String,
        displayName: String,
        detail: String? = nil,
        kind: MentionKind,
        iconName: String? = nil
    ) {
        self.id = id
        self.mentionText = mentionText
        self.displayName = displayName
        self.detail = detail
        self.kind = kind
        self.iconName = iconName ?? kind.defaultIcon
    }

    /// Display label: "MyFile.swift — Sources/App/"
    public var displayLabel: String {
        if let detail, !detail.isEmpty {
            return "\(displayName) — \(detail)"
        }
        return displayName
    }
}

// MARK: - Mention Provider Protocol

/// Provides @-mention candidates for the autocomplete system.
///
/// A single MentionProvider can supply items of any `MentionKind`.
/// Multiple providers are composed by `MentionService`.
public protocol MentionProvider: Sendable {
    /// The kind(s) of items this provider supplies.
    var supportedKinds: [MentionKind] { get }

    /// Fetch all mentionable items. Results are cached briefly.
    func fetchItems() async -> [MentionItem]
}

// MARK: - Default Icons

extension MentionKind {
    var defaultIcon: String {
        switch self {
        case .file:   return "doc.text"
        case .skill:  return "sparkles"
        case .mcp:    return "server.rack"
        case .thread: return "bubble.left.and.bubble.right"
        }
    }
}
