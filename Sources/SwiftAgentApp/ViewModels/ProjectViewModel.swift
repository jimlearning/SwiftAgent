import SwiftUI

/// View model for a single project (sidebar display).
@MainActor
public final class ProjectViewModel: ObservableObject, Identifiable {
    public let id: String

    @Published public var name: String
    @Published public var path: String
    @Published public var threads: [ThreadViewModel] = []
    @Published public var isExpanded: Bool = true

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    /// Update from a persisted project record.
    public func update(from project: PersistedProject) {
        self.name = project.name
        self.path = project.path
    }
}
