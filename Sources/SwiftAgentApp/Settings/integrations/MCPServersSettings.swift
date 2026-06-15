import SwiftUI

struct MCPServersSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "MCP Servers")

            Text("Configure MCP servers to extend SwiftAgent with external tools and data sources.")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)

            Divider().background(Color.borderSubtle)

            HStack {
                Text("Configured servers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add MCP server")
            }

            Text("MCP server management is available in the Plugins panel (sidebar → @)")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)

            Spacer()
        }
        .padding(24)
    }
}
