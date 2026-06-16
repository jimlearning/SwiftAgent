import SwiftUI

/// Horizontal tab bar showing all open right-pane tabs + a `+` button
/// that opens an `AddTabMenu` popover.
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

                // + button — opens AddTabMenu as a popover. The Menu
                // entries have hover-highlight + full-row hit testing
                // (see AddTabMenu.swift).
                addButton
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 36)
        .background(Color.bgRightPanel)
    }

    private var addButton: some View {
        Button {
            tabsStore.showAddMenu()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        .help("Add a new right-pane tab")
        .popover(isPresented: $tabsStore.showAddPopover, arrowEdge: .bottom) {
            AddTabMenu(tabsStore: tabsStore)
        }
    }
}
