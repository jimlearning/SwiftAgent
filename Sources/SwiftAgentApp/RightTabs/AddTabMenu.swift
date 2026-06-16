import SwiftUI

/// Popover content for the tab bar's `+` button. Lists the 5 right
/// pane panel types. Each row is a real Button with contentShape +
/// hoverHighlight so the entire cell is clickable (the prior version
/// had the same "only text responds" bug as the sidebar before the
/// HoverHighlight modifier was introduced).
struct AddTabMenu: View {
    @ObservedObject var tabsStore: RightTabsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open new tab")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .tracking(0.5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(Array(RightTabType.allCases.enumerated()), id: \.element.id) { _, type in
                Button {
                    tabsStore.openTab(type: type)
                    tabsStore.showAddPopover = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: type.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                            .foregroundColor(.textSecondary)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(
                    background: Color.white.opacity(0.08),
                    cornerRadius: 4,
                    padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
    }
}
