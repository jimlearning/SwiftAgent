import SwiftUI

/// A card showing an MCP server's status and tools.
struct MCPServerCard: View {
    let config: MCPConfigStore.MCPServerConfig
    let isConnected: Bool
    let tools: [String]
    let lastError: String?
    let onReconnect: () -> Void
    let onTest: () -> Void
    let onDelete: () -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { expanded.toggle() }) {
                HStack(spacing: 10) {
                    Image(systemName: isConnected ? "circle.fill" : "circle")
                        .font(.system(size: 8))
                        .foregroundColor(isConnected ? .success : .danger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.name)
                            .font(.uiLabel)
                            .foregroundColor(.textPrimary)
                        Text(config.typeName.uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }

                    Spacer()

                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 10))
                        .foregroundColor(isConnected ? .success : .textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isConnected ? Color.success.opacity(0.15) : Color.textTertiary.opacity(0.15))
                        )

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.leading, 12)

                VStack(alignment: .leading, spacing: 8) {
                    // Tools
                    Text("Tools (\(tools.count))")
                        .font(.uiCaption)
                        .foregroundColor(.textSecondary)
                    if tools.isEmpty {
                        Text("No tools discovered")
                            .font(.uiCaption)
                            .foregroundColor(.textTertiary)
                    } else {
                        ForEach(tools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Image(systemName: "wrench")
                                    .font(.system(size: 10))
                                Text(tool)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundColor(.textPrimary)
                        }
                    }

                    // Last error
                    if let error = lastError, !isConnected {
                        Text("Last error: \(error)")
                            .font(.uiCaption)
                            .foregroundColor(.danger)
                            .lineLimit(3)
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button(action: onReconnect) {
                            Text("Reconnect")
                                .font(.uiCaption)
                        }
                        .buttonStyle(.bordered)

                        Button(action: onTest) {
                            Text("Test Connection")
                                .font(.uiCaption)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.danger)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgSidebar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}
