import SwiftUI

/// A thread row in the sidebar. Shows thread title + relative timestamp + unread dot.
struct ThreadRowView: View {
    @ObservedObject var thread: ThreadViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    @State private var isRenaming = false
    @State private var renameText = ""

    private var relativeTimeString: String {
        let interval = Date().timeIntervalSince(thread.updatedAt)
        let seconds = Int(abs(interval))

        switch seconds {
        case 0..<60: return "Now"
        case 60..<3600: return "\(seconds / 60)m"
        case 3600..<86400: return "\(seconds / 3600)h"
        case 86400..<604800: return "\(seconds / 86400)d"
        case 604800..<2592000: return "\(seconds / 604800)w"
        default: return "\(seconds / 2592000)mo"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Unread dot
            if thread.hasUnread {
                Circle()
                    .fill(Color.accentPrimary)
                    .frame(width: 8, height: 8)
            } else {
                Spacer().frame(width: 8)
            }

            // Title or inline rename
            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.uiLabel)
                    .foregroundColor(.textPrimary)
                    .onSubmit {
                        isRenaming = false
                        if !renameText.isEmpty {
                            thread.title = renameText
                        }
                    }
            } else {
                Text(thread.title)
                    .font(.uiLabel)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Worktree indicator
            if thread.executionEnv == "worktree" {
                Image(systemName: "tree")
                    .font(.system(size: 9))
                    .foregroundColor(.success)
                    .help("Running in git worktree")
            }

            // Relative timestamp
            Text(relativeTimeString)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.bgElevated : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename") {
                renameText = thread.title
                isRenaming = true
            }
            Button("Archive") {
                // Phase 3 stub
            }
            Button("Pin") {
                // Phase 3 stub — pins thread to top
            }
            Divider()
            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog(
            "Delete chat '\(thread.title)'?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
