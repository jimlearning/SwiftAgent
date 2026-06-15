import SwiftUI

struct RightTabsView: View {
    @StateObject private var tabsStore = RightTabsStore()

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabsStore: tabsStore)

            Divider()
                .background(Color.borderStrong)

            if let activeTab = tabsStore.activeTab {
                TabContentView(tab: activeTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                EmptyTabPlaceholder()
            }
        }
        .background(Color.bgRightPanel)
    }
}
