import SwiftUI

struct BrowserSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Browser")

            SettingsRow(label: "Default search engine") {
                Picker("", selection: $viewModel.browserSearchEngine) {
                    Text("Google").tag("Google")
                    Text("DuckDuckGo").tag("DuckDuckGo")
                    Text("Bing").tag("Bing")
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .accessibilityLabel("Default search engine")
            }

            Divider().background(Color.borderSubtle)

            SettingsRow(label: "Homepage") {
                TextField("https://...", text: $viewModel.browserHomepage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .font(.system(size: 12))
                    .accessibilityLabel("Browser homepage")
            }

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Allow-list")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                TextEditor(text: $viewModel.browserAllowList)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderStrong, lineWidth: 1)
                    )
                    .accessibilityLabel("Browser allow list")
                Text("One domain per line (e.g. github.com)")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }

            Spacer()
        }
        .padding(24)
    }
}
