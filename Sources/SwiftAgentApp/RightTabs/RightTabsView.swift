import SwiftUI

/// Right multi-Tab workspace:
/// - Tab bar with horizontal scroll and + menu (open new tab of any type)
/// - Content area for the active tab
///
/// The previously-shown 5 top entries (Review / Terminal / Browser /
/// Files / Side chat) were redundant with the + menu's AddTabMenu
/// picker. They are removed: open a new tab of any type via the +
/// button, then close it via the per-tab × button. Empty state still
/// shows `EmptyTabPlaceholder` so the right pane never feels broken.
struct RightTabsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var tabsStore = RightTabsStore()

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
