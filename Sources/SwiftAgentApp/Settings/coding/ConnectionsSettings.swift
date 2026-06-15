import SwiftUI

struct ConnectionsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var newConnection: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Connections")

            Text("Manage SSH and remote dev machine connections.")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)

            Divider().background(Color.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SSH Connections")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                HStack {
                    TextField("user@host:port", text: $newConnection)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .font(.system(size: 12))
                    Button("Add") {
                        let trimmed = newConnection.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.sshConnections.append(trimmed)
                            newConnection = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newConnection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .accessibilityLabel("Add SSH connection")

                if viewModel.sshConnections.isEmpty {
                    Text("No connections configured")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(viewModel.sshConnections.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "network")
                                .font(.system(size: 10))
                                .foregroundColor(.success)
                            Text(viewModel.sshConnections[index])
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Button {
                                viewModel.sshConnections.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.danger)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}
