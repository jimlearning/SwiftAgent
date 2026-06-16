import Foundation

/// Lightweight descriptor for a Skill (SKILL.md) loaded from disk.
/// Used by the AppViewModel's @Published `skills` list so the Composer
/// + menu and Settings page share the same source of truth.
public struct SkillDescriptor: Identifiable, Equatable, Hashable {
    public enum Scope: String, Equatable, Hashable {
        case user
        case project
        case system
    }

    public let id: String
    public let name: String
    public let description: String
    public let scope: Scope
    public let path: String

    public init(name: String, description: String, scope: Scope, path: String) {
        self.id = "\(scope.rawValue):\(name)"
        self.name = name
        self.description = description
        self.scope = scope
        self.path = path
    }
}
