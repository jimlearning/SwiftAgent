import SwiftUI

/// A project row in the sidebar. Shows folder icon + name + expand/collapse.
struct ProjectRowView: View {
    @ObservedObject var project: ProjectViewModel
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onNewThread: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .foregroundColor(.textTertiary)

            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundColor(.accentPrimary)

            Text(project.name)
                .font(.uiLabel)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer()

            if isHovering {
                HStack(spacing: 2) {
                    Button(action: onNewThread) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textSecondary)
                    .help("New chat in project")
                }
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename") { onRename() }
            Button("New Chat in Project") { onNewThread() }
            Divider()
            Button("Delete") { showDeleteConfirm = true }
        }
        .confirmationDialog(
            "Delete project '\(project.name)'? Threads will be moved to global chats.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
