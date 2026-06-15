import Foundation

/// The scope of a skill: where it was loaded from.
/// Priority: project > user > system
public enum SkillScope: String, CaseIterable, Sendable, Comparable {
    case project = "Project"
    case user = "User"
    case system = "System"

    public static func < (lhs: SkillScope, rhs: SkillScope) -> Bool {
        priority(lhs) < priority(rhs)
    }

    public static func priority(_ scope: SkillScope) -> Int {
        switch scope {
        case .project: return 0
        case .user: return 1
        case .system: return 2
        }
    }

    public var badgeColor: String {
        switch self {
        case .project: return "#3FB950"
        case .user: return "#339CFF"
        case .system: return "#999999"
        }
    }
}
