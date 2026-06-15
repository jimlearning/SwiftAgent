import SwiftUI

/// Submenu showing installed MCP servers + skills count.
struct PluginsSubmenu: View {
    let mcpServerCount: Int
    let skillsCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mcpServerCount > 0 {
                Text("MCP Servers")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                Text("\(mcpServerCount) installed")
                    .font(.uiBody)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            if skillsCount > 0 {
                if mcpServerCount > 0 {
                    Divider().padding(.horizontal, 12)
                }
                Text("Skills")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                Text("\(skillsCount) installed")
                    .font(.uiBody)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            if mcpServerCount == 0 && skillsCount == 0 {
                Text("No plugins installed")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 200)
        .padding(.vertical, 4)
    }
}
