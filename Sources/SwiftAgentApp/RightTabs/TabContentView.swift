import SwiftUI

struct TabContentView: View {
    let tab: RightTab

    var body: some View {
        VStack {
            Spacer()
            Text("\(tab.type.title) panel — coming in a future phase")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgRightPanel)
    }
}
