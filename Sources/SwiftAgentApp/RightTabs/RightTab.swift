import Foundation

struct RightTab: Identifiable, Equatable {
    let id: UUID
    let type: RightTabType
    var title: String
    let createdAt: Date

    init(id: UUID = UUID(), type: RightTabType, title: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.title = title ?? type.title
        self.createdAt = createdAt
    }
}
