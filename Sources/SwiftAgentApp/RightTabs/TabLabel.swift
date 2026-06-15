import SwiftUI

struct TabLabel: View {
    let tab: RightTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.type.icon)
                .font(.system(size: 12))
            Text(tab.title)
                .font(.uiLabel)
                .lineLimit(1)
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering ? .red : .textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 80, maxWidth: 200)
        .background(isActive ? Color.bgRightPanel : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentPrimary)
                    .frame(height: 2)
            }
        }
        .foregroundColor(isActive ? .textPrimary : .textSecondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
    }
}
