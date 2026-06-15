import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Appearance")

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

            // Light theme section
            Text("Light Theme")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .accessibilityLabel("Light theme settings")

            SettingsRow(label: "Accent") {
                TextField("#339CFF", text: $viewModel.lightAccent)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Light theme accent color")
            }

            SettingsRow(label: "Background") {
                TextField("#FFFFFF", text: $viewModel.lightBackground)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Light theme background color")
            }

            SettingsRow(label: "Foreground") {
                TextField("#1C1C1C", text: $viewModel.lightForeground)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Light theme foreground color")
            }

            SettingsRow(label: "UI font") {
                TextField("SF Pro", text: $viewModel.lightUIFont)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Light theme UI font")
            }

            SettingsRow(label: "Code font") {
                TextField("SF Mono", text: $viewModel.lightCodeFont)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Light theme code font")
            }

            Divider().background(Color.borderSubtle)

            // Dark theme section
            Text("Dark Theme")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .accessibilityLabel("Dark theme settings")

            SettingsRow(label: "Accent") {
                TextField("#339CFF", text: $viewModel.darkAccent)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Dark theme accent color")
            }

            SettingsRow(label: "Background") {
                TextField("#1C1C1C", text: $viewModel.darkBackground)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Dark theme background color")
            }

            SettingsRow(label: "Foreground") {
                TextField("#F5F5F5", text: $viewModel.darkForeground)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Dark theme foreground color")
            }

            SettingsRow(label: "UI font") {
                TextField("SF Pro", text: $viewModel.darkUIFont)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Dark theme UI font")
            }

            SettingsRow(label: "Code font") {
                TextField("SF Mono", text: $viewModel.darkCodeFont)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(.system(size: 12))
                    .accessibilityLabel("Dark theme code font")
            }

            Divider().background(Color.borderSubtle)

            // Translucent sidebar toggle
            SettingsRow(label: "Translucent sidebar") {
                Toggle("", isOn: $viewModel.translucentSidebar)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Translucent sidebar")
            }

            Divider().background(Color.borderSubtle)

            // Contrast slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Contrast")
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                HStack {
                    Slider(value: $viewModel.contrast, in: 0...100, step: 1)
                        .frame(width: 240)
                    Text("\(Int(viewModel.contrast))")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .frame(width: 30)
                }
            }
            .accessibilityLabel("Contrast slider")

            Spacer()
        }
        .padding(24)
    }
}
