import SwiftUI

struct GitSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Git")

            SettingsRow(label: "Default branch") {
                TextField("main", text: $viewModel.defaultGitBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .font(.system(size: 12))
                    .accessibilityLabel("Default branch")
            }

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit message template")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                TextEditor(text: $viewModel.commitMessageTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderStrong, lineWidth: 1)
                    )
                    .accessibilityLabel("Commit message template")
            }

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Push behavior") {
                Picker("", selection: $viewModel.pushBehavior) {
                    Text("Current branch").tag("current")
                    Text("Upstream").tag("upstream")
                    Text("Simple").tag("simple")
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .accessibilityLabel("Push behavior")
            }

            Spacer()
        }
        .padding(24)
    }
}
