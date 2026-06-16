import SwiftUI

/// Right multi-Tab workspace:
/// - Top entries (Review / Terminal / Browser / Files / Side chat) — open new tab
/// - Tab bar with horizontal scroll and + menu
/// - Content area for the active tab
struct RightTabsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var tabsStore = RightTabsStore()

    var body: some View {
        VStack(spacing: 0) {
            topEntries
            Divider().background(Color.borderSubtle)
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

    /// Top entries: 5 entries that each open a new tab of that type.
    /// Mirrors the sidebar's "New chat / Search / Plugins / Automations"
    /// style for visual consistency.
    private var topEntries: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(RightTabType.allCases.enumerated()), id: \.element.id) { _, type in
                rightTopEntry(type: type)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func rightTopEntry(type: RightTabType) -> some View {
        Button {
            tabsStore.openTab(type: type)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(.textPrimary)
                Text(type.title)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 4)
                if !type.shortcut.isEmpty {
                    Text(type.shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        )
        .help("Open new \(type.title) tab")
    }
}
