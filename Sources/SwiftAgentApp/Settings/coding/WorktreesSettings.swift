import SwiftUI

struct WorktreesSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Worktrees")

            SettingsRow(label: "Auto-cleanup") {
                Toggle("", isOn: $viewModel.worktreeAutoCleanup)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Auto-cleanup worktrees")
            }

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Base branch") {
                TextField("main", text: $viewModel.worktreeBaseBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .font(.system(size: 12))
                    .accessibilityLabel("Base branch for worktrees")
            }

            Spacer()
        }
        .padding(24)
    }
}
