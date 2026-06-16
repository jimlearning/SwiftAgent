import SwiftUI
import AppKit

/// Files panel: a proper tree browser for the current project.
///
/// Layout (top → bottom):
/// - Header: project path + refresh button
/// - Search bar (filter by file name)
/// - Tree: hierarchical disclosure groups with proper indentation;
///   folders collapse/expand; files open in an in-app text viewer
///   (markdown / swift / plain text) or in the system default app.
///
/// Selecting a file does NOT call `NSWorkspace.open` — instead it
/// populates `selectedFileContent` so the right side of the panel
/// shows the file inline. Right-click brings up a context menu with
/// "Open with default app", "Reveal in Finder", "Copy path".
public struct FilesPanelView: View {
    let tabID: String
    let projectPath: String?

    @State private var rootNodes: [FileNode] = []
    @State private var searchText: String = ""
    @State private var selectedFile: FileNode?
    @State private var selectedFileContent: String?
    @State private var expandedFolders: Set<String> = []

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)
            searchBar
            Divider().background(Color.borderSubtle)
            HStack(spacing: 0) {
                treeColumn
                    .frame(width: 220)
                Divider().background(Color.borderSubtle)
                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgRightPanel)
        .onAppear { refreshFiles() }
    }

    // MARK: - Header

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
            .help("Refresh file tree")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textTertiary)
                .font(.system(size: 11))
                .frame(width: 14)
            TextField("Filter files...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgInput.opacity(0.5))
    }

    // MARK: - Tree Column

    @ViewBuilder
    private var treeColumn: some View {
        if rootNodes.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredRootNodes) { node in
                        FileTreeRow(
                            node: node,
                            depth: 0,
                            expanded: $expandedFolders,
                            selected: $selectedFile,
                            onSelect: handleSelect
                        )
                    }
                }
            }
        }
    }

    private var filteredRootNodes: [FileNode] {
        if searchText.isEmpty { return rootNodes }
        return rootNodes.compactMap { node in filterNode(node, query: searchText.lowercased()) }
    }

    /// Returns the node if it (or any descendant) matches; prunes children that don't match.
    private func filterNode(_ node: FileNode, query: String) -> FileNode? {
        if node.isDirectory {
            let filteredChildren = node.children?.compactMap { filterNode($0, query: query) } ?? []
            if node.name.lowercased().contains(query) || !filteredChildren.isEmpty {
                var copy = node
                copy.children = filteredChildren
                return copy
            }
            return nil
        } else {
            return node.name.lowercased().contains(query) ? node : nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24, weight: .light))
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
        .padding(20)
    }

    // MARK: - Preview Column

    @ViewBuilder
    private var previewColumn: some View {
        if let selected = selectedFile {
            VStack(spacing: 0) {
                previewHeader(node: selected)
                Divider().background(Color.borderSubtle)
                if let content = selectedFileContent {
                    ScrollView([.vertical, .horizontal]) {
                        Text(content)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                    }
                } else {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
            }
        } else {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.textTertiary)
                Text("Select a file to preview")
                    .font(.uiBody)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewHeader(node: FileNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForFile(node.url))
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSWorkspace.shared.open(node.url)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .help("Open in default app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Selection handler

    private func handleSelect(_ node: FileNode) {
        guard !node.isDirectory else { return }
        selectedFile = node
        selectedFileContent = nil

        // Load file content in the background to keep UI responsive.
        let url = node.url
        Task.detached(priority: .userInitiated) {
            // Cap at 2 MB so we don't try to render gigabytes of binary.
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            if size > 2_000_000 {
                await MainActor.run {
                    selectedFileContent = "[File too large to preview (\(size) bytes)]"
                }
                return
            }
            let content = (try? String(contentsOf: url, encoding: .utf8))
                ?? "[Binary or non-UTF-8 file]"
            await MainActor.run {
                selectedFileContent = content
            }
        }
    }

    // MARK: - Helpers

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md", "markdown": return "doc.richtext"
        case "txt": return "doc.text"
        case "json", "toml", "yaml", "yml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "gitignore", "git": return "arrow.triangle.branch"
        default: return "doc"
        }
    }

    private func refreshFiles() {
        guard let path = projectPath else { rootNodes = []; return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        rootNodes = FileNode.buildTree(at: url, maxDepth: 6, maxEntriesPerDir: 500)
        // Auto-expand the root by default.
        if let firstDir = rootNodes.first {
            expandedFolders.insert(firstDir.url.path)
        }
    }
}

// MARK: - File Node

struct FileNode: Identifiable, Equatable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var id: String { url.path }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url && lhs.children?.count == rhs.children?.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    /// Recursively build a tree rooted at `url`, ignoring hidden files
    /// and VCS directories. `maxDepth` prevents stack overflow on
    /// pathological inputs; `maxEntriesPerDir` prevents huge directories
    /// (e.g. node_modules) from killing performance.
    static func buildTree(at url: URL, maxDepth: Int, maxEntriesPerDir: Int) -> [FileNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var topLevel: [FileNode] = []
        var count = 0
        for case let entry as URL in enumerator {
            if count >= maxEntriesPerDir { break }
            count += 1
            let name = entry.lastPathComponent
            // Skip noisy VCS/build dirs
            if name == "node_modules" || name == ".build" || name == "DerivedData" || name == ".git" { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values?.isDirectory ?? false
            // Depth tracking: count path components relative to root.
            let depth = entry.pathComponents.count - url.pathComponents.count
            if depth > maxDepth { continue }
            let children = isDir ? buildTree(at: entry, maxDepth: maxDepth, maxEntriesPerDir: maxEntriesPerDir) : nil
            topLevel.append(FileNode(url: entry, name: name, isDirectory: isDir, children: children))
        }
        return topLevel.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory // folders first
            }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {
    let node: FileNode
    let depth: Int
    @Binding var expanded: Set<String>
    @Binding var selected: FileNode?
    let onSelect: (FileNode) -> Void

    private var isExpanded: Bool { expanded.contains(node.url.path) }
    private var isSelected: Bool { selected?.url == node.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isDirectory, isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        depth: depth + 1,
                        expanded: $expanded,
                        selected: $selected,
                        onSelect: onSelect
                    )
                }
            }
        }
    }

    private var row: some View {
        Button {
            if node.isDirectory {
                if isExpanded {
                    expanded.remove(node.url.path)
                } else {
                    expanded.insert(node.url.path)
                }
            } else {
                selected = node
                onSelect(node)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: node.isDirectory ? (isExpanded ? "chevron.down" : "chevron.right") : "doc")
                    .font(.system(size: 9, weight: node.isDirectory ? .bold : .regular))
                    .frame(width: 12)
                    .foregroundColor(.textTertiary)
                Image(systemName: node.isDirectory ? "folder" : iconForFile(node.url))
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Text(node.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .textPrimary : .textPrimary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.leading, CGFloat(depth) * 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.bgElevated.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(
            background: Color.white.opacity(isSelected ? 0.04 : 0.06),
            cornerRadius: 4,
            padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        )
        .contextMenu {
            Button("Open with default app") { NSWorkspace.shared.open(node.url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Divider()
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md", "markdown": return "doc.richtext"
        case "json", "toml", "yaml", "yml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}
