import SwiftUI
import AppKit
import OSLog

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

    @EnvironmentObject var appViewModel: AppViewModel

    @State private var rootNodes: [FileNode] = []
    @State private var searchText: String = ""
    @State private var selectedFile: FileNode?
    @State private var selectedFileContent: String?
    @State private var expandedFolders: Set<String> = []
    /// Lazily-loaded children for directories beyond the initial tree depth.
    @State private var loadedChildren: [String: [FileNode]] = [:]
    @State private var treeWidth: CGFloat = 240

    private static let log = Logger(subsystem: "com.swiftagent.app", category: "FilesPanel")
    private static var mdRenderCache: [String: AttributedString] = [:]

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)
            searchBar
            Divider().background(Color.borderSubtle)
            HStack(spacing: 0) {
                treeColumn
                    .frame(width: treeWidth)
                DragDivider(width: $treeWidth, range: 160...320, edge: .trailing, color: .borderStrong)
                previewColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgRightPanel)
        .onAppear { refreshFiles() }
        .onChange(of: projectPath) { refreshFiles() }
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

    /// File tree rendered as `List` + `DisclosureGroup` so SwiftUI lazily
    /// creates only the visible rows. The old `ScrollView` + recursive
    /// `VStack`/`ForEach` eagerly instantiated every child of every expanded
    /// directory (200+ views for Sources/SwiftAgentApp), blocking the main
    /// thread during scroll layout.
    @ViewBuilder
    private var treeColumn: some View {
        if rootNodes.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredRootNodes) { node in
                    FileTreeRow(
                        node: node,
                        depth: 0,
                        expanded: $expandedFolders,
                        selected: $selectedFile,
                        loadedChildren: $loadedChildren,
                        onSelect: handleSelect,
                        onAddToChat: { fileNode in
                            appViewModel.addFileToComposer(fileNode.url)
                        },
                        projectPath: projectPath
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                        if isMarkdownFile(selected.name) {
                            Text(renderedMarkdown(file: selected.name, content: content))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        } else {
                            Text(highlightedPreview(for: selected, content: content))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                        }
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

    private func renderedMarkdown(file name: String, content: String) -> AttributedString {
        let cacheKey = "\(name):\(content.count)"
        if let cached = Self.mdRenderCache[cacheKey] {
            Self.log.debug("[MD CACHE HIT] file=\(name) len=\(content.count)")
            return cached
        }
        let start = CFAbsoluteTimeGetCurrent()
        let renderer = MarkdownRenderer(
            baseFont: .system(size: 12, weight: .regular),
            codeFont: .system(size: 11, design: .monospaced),
            foregroundColor: .textPrimary
        )
        let result = renderer.render(content)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let lines = content.components(separatedBy: .newlines).count
        if elapsed > 5 {
            Self.log.warning("[MD RENDER] file=\(name) elapsed=\(String(format: "%.1f", elapsed))ms lines=\(lines) chars=\(content.count)")
        } else {
            Self.log.debug("[MD RENDER] file=\(name) elapsed=\(String(format: "%.1f", elapsed))ms lines=\(lines) chars=\(content.count)")
        }
        Self.mdRenderCache[cacheKey] = result
        return result
    }

    private func isMarkdownFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private func highlightedPreview(for node: FileNode, content: String) -> AttributedString {
        let ext = (node.name as NSString).pathExtension
        let language = MarkdownRenderer.languageFromFileExtension(ext)
        return MarkdownRenderer.highlightCode(
            content,
            language: language,
            font: .system(size: 12, design: .monospaced),
            foregroundColor: .textPrimary
        )
    }

    private func refreshFiles() {
        guard let path = projectPath else { rootNodes = []; return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        // Offload synchronous FileManager I/O — contentsOfDirectory and
        // resourceValues block the calling thread. The tree is built eagerly
        // (maxDepth: 6) on a background thread and then published to the UI.
        // Rendering is lazy via List + DisclosureGroup, so view instantiation
        // is still capped to visible rows.
        Task.detached(priority: .userInitiated) {
            let nodes = FileNode.buildTree(at: url, maxDepth: 6, maxEntriesPerDir: 500)
            await MainActor.run {
                rootNodes = nodes
                if let firstDir = nodes.first {
                    expandedFolders.insert(firstDir.url.path)
                }
            }
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
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var nodes: [FileNode] = []
        for entry in entries.prefix(maxEntriesPerDir) {
            let name = entry.lastPathComponent
            if name == "node_modules" || name == ".build" || name == "DerivedData" || name == ".git" { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values?.isDirectory ?? false
            let children: [FileNode]? = if isDir && maxDepth > 1 {
                buildTree(at: entry, maxDepth: maxDepth - 1, maxEntriesPerDir: maxEntriesPerDir)
            } else {
                nil
            }
            nodes.append(FileNode(url: entry, name: name, isDirectory: isDir, children: children))
        }
        return nodes.sorted { lhs, rhs in
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
    /// Fallback children loaded lazily (keyed by node id).
    @Binding var loadedChildren: [String: [FileNode]]
    let onSelect: (FileNode) -> Void
    let onAddToChat: (FileNode) -> Void
    let projectPath: String?

    private var isExpanded: Bool { expanded.contains(node.url.path) }
    private var isSelected: Bool { selected?.url == node.url }

    /// Effective children: pre-built tree first, then lazily loaded fallback.
    private var effectiveChildren: [FileNode]? {
        node.children ?? loadedChildren[node.id]
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expanded.contains(node.url.path) },
            set: { newVal in
                if newVal { expanded.insert(node.url.path) }
                else { expanded.remove(node.url.path) }
            }
        )
    }

    /// Returns the list of app bundle URLs that can open this file,
    /// in the same order Finder's "Open With" submenu would show.
    /// Computed lazily so we don't hit NSWorkspace on every render.
    private var availableApps: [URL] {
        guard !node.isDirectory else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: node.url)
    }

    /// The default app for this file (used by the top "Open in default
    /// app" entry). nil for unknown types.
    private var defaultApp: URL? {
        guard !node.isDirectory else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: node.url)
    }

    var body: some View {
        if node.isDirectory {
            if let children = effectiveChildren, !children.isEmpty {
                DisclosureGroup(isExpanded: expandedBinding) {
                    ForEach(children) { child in
                        FileTreeRow(
                            node: child,
                            depth: depth + 1,
                            expanded: $expanded,
                            selected: $selected,
                            loadedChildren: $loadedChildren,
                            onSelect: onSelect,
                            onAddToChat: onAddToChat,
                            projectPath: projectPath
                        )
                    }
                } label: {
                    rowLabel
                        .contentShape(Rectangle())
                        .onTapGesture { expandedBinding.wrappedValue.toggle() }
                }
            } else if node.children?.isEmpty == true {
                // Empty directory — no children, no chevron
                rowLabel
                    .contentShape(Rectangle())
                    .onTapGesture {
                        expanded.remove(node.url.path)
                    }
            } else {
                // Children not loaded yet — tap to load and expand
                rowLabel
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let key = node.url.path
                        if expanded.contains(key) {
                            expanded.remove(key)
                        } else {
                            expanded.insert(key)
                            loadChildren()
                        }
                    }
            }
        } else {
            rowLabel
                .onTapGesture {
                    selected = node
                    onSelect(node)
                }
        }
    }

    private func loadChildren() {
        guard node.isDirectory, node.children == nil, loadedChildren[node.id] == nil else { return }
        Task.detached(priority: .userInitiated) {
            let children = FileNode.buildTree(at: node.url, maxDepth: 1, maxEntriesPerDir: 500)
            await MainActor.run {
                loadedChildren[node.id] = children
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 4) {
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
        .offset(x: -8)   // shift content left to close chevron gap; frame/bg unaffected
        .padding(.leading, 0)
        .padding(.trailing, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.bgElevated.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu { fileContextMenu }
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        // 1. Open in default app
        Button("Open in default app") {
            NSWorkspace.shared.open(node.url)
        }

        // 2. Open with >
        Menu("Open with") {
            if availableApps.isEmpty {
                Text("No app can open this file")
            } else {
                ForEach(availableApps, id: \.self) { appURL in
                    Button {
                        NSWorkspace.shared.open(
                            [node.url],
                            withApplicationAt: appURL,
                            configuration: NSWorkspace.OpenConfiguration()
                        ) { _, _ in }
                    } label: {
                        let isDefault = (appURL == defaultApp)
                        HStack {
                            Image(systemName: isDefault ? "checkmark" : "")
                                .frame(width: 14)
                            Text(appURL.deletingPathExtension().lastPathComponent)
                        }
                    }
                }
            }
        }

        Divider()

        // 3. Reveal in Finder
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }

        // 4. Copy path
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }

        Divider()

        // 5. Git operations
        if let workingDir = projectPath {
            Button("Git log") {
                gitLogForFile(node.url, workingDir: workingDir)
            }
            Button("Git diff") {
                gitDiffForFile(node.url, workingDir: workingDir)
            }
            Divider()
        }

        // 6. Add to chat
        Button("Add to chat") {
            onAddToChat(node)
        }
        .disabled(node.isDirectory)
    }

    // MARK: - Git Helpers

    /// Run `git log --oneline -5 <file>` and show in a temporary alert.
    private func gitLogForFile(_ fileURL: URL, workingDir: String) {
        let output = runGit(arguments: ["log", "--oneline", "-5", fileURL.path], cwd: workingDir)
        let alert = NSAlert()
        alert.messageText = "Git log — \(fileURL.lastPathComponent)"
        alert.informativeText = output.isEmpty ? "No commits for this file." : output
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Run `git diff <file>` and show in a temporary alert.
    private func gitDiffForFile(_ fileURL: URL, workingDir: String) {
        let output = runGit(arguments: ["diff", fileURL.path], cwd: workingDir)
        let alert = NSAlert()
        alert.messageText = "Git diff — \(fileURL.lastPathComponent)"
        alert.informativeText = output.isEmpty ? "No changes to show." : output
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func runGit(arguments: [String], cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

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
}
