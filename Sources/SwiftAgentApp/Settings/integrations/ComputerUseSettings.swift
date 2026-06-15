import SwiftUI

struct ComputerUseSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Computer use")

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "desktopcomputer")
                    .font(.system(size: 40))
                    .foregroundColor(.textTertiary)

                Text("Coming in v1.1")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textSecondary)

                Text("Computer Use will allow SwiftAgent to interact with your desktop — click, type, and navigate applications on your behalf.")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }
}
