import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Section {
                SidebarEntryRow(icon: "pencil.tip.crop.circle", title: "New chat")
                SidebarEntryRow(icon: "magnifyingglass", title: "Search")
                SidebarEntryRow(icon: "at", title: "Plugins")
                SidebarEntryRow(icon: "clock", title: "Automations")
            }

            Section {
                Text("No projects yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
            } header: {
                Text("Projects")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
            }

            Section {
                Text("No chats yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
            } header: {
                Text("Chats (global)")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
            }

            Section {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                    Text("Settings")
                        .font(.uiLabel)
                }
                .foregroundColor(.textSecondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bgSidebar)
    }
}

private struct SidebarEntryRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(title)
                .font(.uiLabel)
        }
        .foregroundColor(.textPrimary)
        .padding(.vertical, 2)
    }
}
