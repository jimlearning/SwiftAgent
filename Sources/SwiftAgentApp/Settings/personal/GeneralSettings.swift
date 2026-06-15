import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "General")

            // Work mode picker
            SettingsRow(label: "Work mode") {
                Picker("", selection: $viewModel.workMode) {
                    Text("Agent").tag("Agent")
                    Text("Plan").tag("Plan")
                    Text("Interactive").tag("Interactive")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .accessibilityLabel("Work mode")
            }

            Divider().background(Color.borderSubtle)

            // Default permission
            SettingsRow(label: "Default permission") {
                Picker("", selection: $viewModel.defaultPermission) {
                    Text("Ask for approval").tag("Ask for approval")
                    Text("Approve for me").tag("Approve for me")
                    Text("Full access").tag("Full access")
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .accessibilityLabel("Default permission")
            }

            Divider().background(Color.borderSubtle)

            // Theme picker
            SettingsRow(label: "Theme") {
                Picker("", selection: $viewModel.theme) {
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                    Text("System").tag("System")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityLabel("Theme")
            }

            Divider().background(Color.borderSubtle)

            // API Key status
            SettingsRow(label: "DeepSeek API Key") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                        .font(.system(size: 12))
                    Text("Configured")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Helpers

struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.textPrimary)
            .accessibilityLabel("\(title) settings")
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textPrimary)
                .frame(width: 180, alignment: .leading)
            content()
            Spacer()
        }
        .accessibilityLabel(label)
    }
}
