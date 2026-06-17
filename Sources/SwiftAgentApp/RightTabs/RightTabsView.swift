import SwiftUI

/// Right multi-Tab workspace:
/// - Tab bar with horizontal scroll and + menu (open new tab of any type)
/// - Content area for the active tab
///
/// Uses the shared `RightTabsStore` from the environment (owned by
/// `EntryPoint`) so keyboard shortcuts, the + menu, and tab state all
/// reference the same store. Opening a tab via ⌘T or the + button both
/// route through the same instance.
struct RightTabsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var tabsStore: RightTabsStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(tabsStore: tabsStore)
            Divider().background(Color.borderSubtle)

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
