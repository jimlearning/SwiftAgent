import SwiftUI

struct HooksSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Hooks")

            Text("Configure pre/post command hooks in TOML format. Hooks run before and after agent tool executions.")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Hook configuration (TOML)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)

                TextEditor(text: $viewModel.hooksToml)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderStrong, lineWidth: 1)
                    )
                    .accessibilityLabel("Hook configuration editor")
            }

            Spacer()
        }
        .padding(24)
    }
}
