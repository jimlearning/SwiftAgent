import Foundation

enum RightTabType: String, CaseIterable, Identifiable, Codable {
    case review
    case terminal
    case browser
    case files
    case sideChat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "Review"
        case .terminal: return "Terminal"
        case .browser: return "Browser"
        case .files: return "Files"
        case .sideChat: return "Side chat"
        }
    }

    var icon: String {
        switch self {
        case .review: return "checklist"
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .files: return "folder"
        case .sideChat: return "plus.circle"
        }
    }

    var shortcut: String {
        switch self {
        case .review: return "\u{2303}\u{21E7}G"
        case .terminal: return "\u{2303}`"
        case .browser: return "\u{2318}T"
        case .files: return "\u{2318}P"
        case .sideChat: return "\u{2325}\u{2318}S"
        }
    }
}
