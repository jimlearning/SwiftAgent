import SwiftUI

struct ConfigurationSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Configuration")

            SettingsRow(label: "Default model") {
                Picker("", selection: $viewModel.defaultModel) {
                    Text("DeepSeek-V3 (chat)").tag("deepseek-chat")
                    Text("DeepSeek-R1 (reasoner)").tag("deepseek-reasoner")
                    Text("DeepSeek-V3-0324").tag("deepseek-chat-0324")
                    Text("DeepSeek-Coder-V2").tag("deepseek-coder-v2")
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
