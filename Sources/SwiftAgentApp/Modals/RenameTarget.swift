import Foundation

/// Identifies what is being renamed — used by sheets and sidebar.
public enum RenameTarget: Identifiable {
    case thread(String)
    case project(String)

    public var id: String {
        switch self {
        case .thread(let id): return "thread-\(id)"
        case .project(let id): return "project-\(id)"
        }
    }
}
