import SwiftUI
import Combine

@MainActor
final class RightTabsStore: ObservableObject {
    @Published var tabs: [RightTab] = []
    @Published var activeTabID: UUID?
    @Published var showAddPopover: Bool = false

    var activeTab: RightTab? {
        tabs.first(where: { $0.id == activeTabID })
    }

    func openTab(type: RightTabType) {
        let tab = RightTab(type: type)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func close(_ id: UUID) {
        tabs.removeAll(where: { $0.id == id })
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
    }

    func activate(_ id: UUID) {
        activeTabID = id
    }

    func showAddMenu() {
        showAddPopover.toggle()
    }
}
