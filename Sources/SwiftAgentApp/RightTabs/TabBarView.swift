import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabsStore: RightTabsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabsStore.tabs) { tab in
                    TabLabel(
                        tab: tab,
                        isActive: tabsStore.activeTabID == tab.id,
                        onTap: { tabsStore.activate(tab.id) },
                        onClose: { tabsStore.close(tab.id) }
                    )
                }

                Button {
                    tabsStore.showAddMenu()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
                .popover(isPresented: $tabsStore.showAddPopover, arrowEdge: .bottom) {
                    AddTabMenu(tabsStore: tabsStore)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
    }
}
