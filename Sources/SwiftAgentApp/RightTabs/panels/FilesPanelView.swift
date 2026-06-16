import SwiftUI
import AppKit

/// Files panel: a simple SwiftUI list of files in the current project
/// directory. Clicking a row opens it in the system's default app via
/// `NSWorkspace.open`. This is intentionally minimal — a full IDE-grade
/// file tree with rename/delete/etc. is out of scope for v1.
public struct FilesPanelView: View {
    let tabID: String
    let projectPath: String?

    @State private var files: [URL] = []
    @State private var selectedURL: URL?

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)
            if files.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .background(Color.bgRightPanel)
        .onAppear { refreshFiles() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
            Text(projectPath ?? "No project")
                .font(.uiCaption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button {
                refreshFiles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .help("Refresh file list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.self) { url in
                    fileRow(url: url)
                }
            }
        }
    }

    private func fileRow(url: URL) -> some View {
        let isSelected = selectedURL == url
        return Button {
            selectedURL = url
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconForFile(url))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .frame(width: 16)
                Text(url.lastPathComponent)
                    .font(.uiBody)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.bgElevated.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 0, padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.textTertiary)
            Text("No project open")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Text("Open a project from the sidebar to see its files.")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "toml", "yaml", "yml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "gitignore", "git": return "arrow.triangle.branch"
        default: return "doc"
        }
    }

    private func refreshFiles() {
        guard let path = projectPath else { files = []; return }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            files = []
            return
        }

        var collected: [URL] = []
        // Cap at 200 entries so the UI doesn't get bogged down on huge repos.
        for case let entry as URL in enumerator.prefix(200) {
            if collected.count >= 200 { break }
            collected.append(entry)
        }
        files = collected.sorted { $0.path < $1.path }
    }
}
