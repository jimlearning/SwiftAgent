import SwiftUI

struct ArchivedChatsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var archivedChats: [SampleArchivedChat] = [
        SampleArchivedChat(id: "1", title: "Refactor auth module", archivedAt: Date().addingTimeInterval(-86400 * 7)),
        SampleArchivedChat(id: "2", title: "Fix build pipeline", archivedAt: Date().addingTimeInterval(-86400 * 14)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader(title: "Archived chats")

            Text("View and manage archived conversation threads.")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)

            Divider().background(Color.borderSubtle)

            if archivedChats.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 24))
                        .foregroundColor(.textTertiary)
                    Text("No archived chats")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(archivedChats.indices, id: \.self) { index in
                        let chat = archivedChats[index]
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.title)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textPrimary)
                                Text("Archived \(chat.archivedAt, style: .relative)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            Button("Restore") {
                                archivedChats.remove(at: index)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.trailing, 4)
                            .accessibilityLabel("Restore chat")
                            Button("Delete permanently") {
                                archivedChats.remove(at: index)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.danger)
                            .accessibilityLabel("Delete chat permanently")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)

                        if index < archivedChats.count - 1 {
                            Divider().background(Color.borderSubtle.opacity(0.5))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

struct SampleArchivedChat: Identifiable {
    let id: String
    let title: String
    let archivedAt: Date
}
