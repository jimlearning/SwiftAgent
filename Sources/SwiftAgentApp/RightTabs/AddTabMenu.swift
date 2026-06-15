import SwiftUI

struct AddTabMenu: View {
    @ObservedObject var tabsStore: RightTabsStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(RightTabType.allCases, id: \.self) { type in
                Button {
                    tabsStore.openTab(type: type)
                    tabsStore.showAddPopover = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: type.icon)
                            .frame(width: 16)
                        Text(type.title)
                            .font(.uiBody)
                        Spacer()
                        Text(type.shortcut)
                            .font(.uiCaption)
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if type != RightTabType.allCases.last {
                    Divider().padding(.leading, 36)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 200)
    }
}
