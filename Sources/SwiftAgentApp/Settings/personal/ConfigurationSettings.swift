import SwiftUI

struct ConfigurationSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Configuration")

            SettingsRow(label: "Default model") {
                Picker("", selection: $viewModel.defaultModel) {
                    Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                    Text("DeepSeek V4 Flash").tag("deepseek-v4-flash")
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .accessibilityLabel("Default model")
            }

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Default reasoning level") {
                Picker("", selection: $viewModel.defaultReasoningLevel) {
                    Text("Low").tag("Low")
                    Text("Medium").tag("Medium")
                    Text("High").tag("High")
                    Text("Extra High").tag("Extra High")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .accessibilityLabel("Default reasoning level")
            }

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Default sandbox mode") {
                Picker("", selection: $viewModel.defaultSandboxMode) {
                    Text("Ask").tag("ask")
                    Text("Approve").tag("approve")
                    Text("Full").tag("full")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .accessibilityLabel("Default sandbox mode")
            }

            Spacer()
        }
        .padding(24)
    }
}
