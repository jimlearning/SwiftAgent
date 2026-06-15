import SwiftUI

struct EmptyTabPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Open a tab to get started")
                .font(.uiBody)
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgRightPanel)
    }
}
