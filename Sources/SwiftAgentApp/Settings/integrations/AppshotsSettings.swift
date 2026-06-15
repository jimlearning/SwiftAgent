import SwiftUI

struct AppshotsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Appshots")

            Text("Capture your screen to give SwiftAgent visual context. Uses macOS Accessibility API.")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Enable Appshots") {
                Toggle("", isOn: $viewModel.appshotsEnabled)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable Appshots")
            }

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Permission status")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.success)
                    Text("Accessibility access granted")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                }

                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open System Settings for accessibility permissions")
            }

            Spacer()
        }
        .padding(24)
    }
}
