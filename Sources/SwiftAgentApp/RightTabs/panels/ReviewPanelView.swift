import SwiftUI

/// Diff Review panel shown in the right multi-tab workspace.
/// Shows a summary of edited files with unified diff view.
///
/// Diff lines are syntax-highlighted using `MarkdownRenderer.highlightCode`
/// (which reuses the Core `RegexSyntaxHighlighter` + Monokai `CodeColors`).
/// Diff markers (`+`/`-`) retain their green/red styling; the code portion
/// gets full syntax coloring.
///
/// Per §5.3: no per-line Accept/Reject buttons.
public struct ReviewPanelView: View {
    /// A single file diff entry.
    public struct DiffEntry: Identifiable {
        public let id: String
        public let fileName: String
        public let linesAdded: Int
        public let linesRemoved: Int
        public let diffContent: String
        public let status: FileStatus

        public enum FileStatus {
            case added
            case modified
            case deleted
        }

        public init(id: String = UUID().uuidString, fileName: String, linesAdded: Int = 0, linesRemoved: Int = 0, diffContent: String = "", status: FileStatus = .modified) {
            self.id = id
            self.fileName = fileName
            self.linesAdded = linesAdded
            self.linesRemoved = linesRemoved
            self.diffContent = diffContent
            self.status = status
        }

        /// File extension sans dot, for syntax language detection.
        public var fileExtension: String {
            (fileName as NSString).pathExtension
        }

        public var statusDotColor: Color {
            switch status {
            case .added: return .success
            case .modified: return .accentPrimary
            case .deleted: return .danger
            }
        }

        public var statusLabel: String {
            switch status {
            case .added: return "A"
            case .modified: return "M"
            case .deleted: return "D"
            }
        }
    }

    public let entries: [DiffEntry]
    public var totalFilesEdited: Int { entries.count }
    public var totalAdded: Int { entries.reduce(0) { $0 + $1.linesAdded } }
    public var totalRemoved: Int { entries.reduce(0) { $0 + $1.linesRemoved } }

    @State private var expandedFileID: String?

    public init(entries: [DiffEntry] = []) {
        self.entries = entries
    }

    public var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider().background(Color.borderStrong)
            if entries.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .background(Color.bgRightPanel)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalFilesEdited) files edited")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("+\(totalAdded) \u{2212}\(totalRemoved)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(
                        totalAdded > totalRemoved ? .success : .danger
                    )
            }
            Spacer()
            Text("Review \u{2197}")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text("No changes to review")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Spacer()
        }
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    fileRow(entry)
                    if entry.id != entries.last?.id {
                        Divider().background(Color.borderSubtle)
                    }
                }
            }
        }
    }

    private func fileRow(_ entry: DiffEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    expandedFileID = expandedFileID == entry.id ? nil : entry.id
                }
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(entry.statusDotColor)
                        .frame(width: 8, height: 8)
                    Text(entry.fileName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("+\(entry.linesAdded) \u{2212}\(entry.linesRemoved)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textTertiary)
                    Image(systemName: expandedFileID == entry.id ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedFileID == entry.id, !entry.diffContent.isEmpty {
                unifiedDiffView(content: entry.diffContent, language: languageFor(entry))
            }
        }
    }

    private func languageFor(_ entry: DiffEntry) -> String? {
        MarkdownRenderer.languageFromFileExtension(entry.fileExtension)
    }

    // MARK: - Unified Diff View

    private func unifiedDiffView(content: String, language: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                    diffLine(line, language: language)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func diffLine(_ line: String, language: String?) -> some View {
        // Hunk header: `@@ -10,7 +10,8 @@ func ...`
        if line.hasPrefix("@@") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.accentPrimary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color.accentPrimary.opacity(0.06))
        }
        // Metadata: `diff --git`, `index`, `---`, `+++`
        else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
        }
        else if line.hasPrefix("---") || line.hasPrefix("+++") {
            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
        }
        // Added line
        else if line.hasPrefix("+") {
            HStack(spacing: 0) {
                Text("+")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.success)
                Text(MarkdownRenderer.highlightCode(
                    String(line.dropFirst()), language: language,
                    font: .system(size: 11, design: .monospaced),
                    foregroundColor: .success
                ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.success.opacity(0.08))
        }
        // Removed line
        else if line.hasPrefix("-") {
            HStack(spacing: 0) {
                Text("-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.danger)
                Text(MarkdownRenderer.highlightCode(
                    String(line.dropFirst()), language: language,
                    font: .system(size: 11, design: .monospaced),
                    foregroundColor: .danger
                ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.danger.opacity(0.08))
        }
        // Context line (unchanged)
        else {
            Text(MarkdownRenderer.highlightCode(
                line, language: language,
                font: .system(size: 11, design: .monospaced),
                foregroundColor: .textPrimary
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
    }
}
