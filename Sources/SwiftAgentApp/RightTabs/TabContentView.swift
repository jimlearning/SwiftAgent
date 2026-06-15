import SwiftUI

struct TabContentView: View {
    let tab: RightTab

    var body: some View {
        switch tab.type {
        case .review:
            ReviewPanelView()
        case .terminal:
            placeholderView(title: "Terminal", icon: "terminal")
        case .browser:
            placeholderView(title: "Browser", icon: "globe")
        case .files:
            placeholderView(title: "Files", icon: "folder")
        case .sideChat:
            placeholderView(title: "Side chat", icon: "plus.circle")
        }
    }

    private func placeholderView(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text("\(title) — coming in Phase 5")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgRightPanel)
    }
}
