import SwiftUI

struct EnvironmentsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Environments")

            SettingsRow(label: "Environment") {
                Picker("", selection: $viewModel.currentEnvironment) {
                    Text("Local").tag("local")
                    Text("Worktree").tag("worktree")
                    Text("Cloud").tag("cloud")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .disabled(true) // Cloud disabled in v1.0
                .accessibilityLabel("Environment")
            }

            Divider().background(Color.borderSubtle)

            Text("Cloud environments are coming in a future update.")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)

            Spacer()
        }
        .padding(24)
    }
}
