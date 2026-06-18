import SwiftUI

/// Debug console panel, shown as a RightTab when AgentDebugger is enabled.
///
/// ## Filter buttons
/// The row of category buttons (Lifecycle, LLM, Tool, etc.) are **toggle filters**.
/// Each one controls whether log entries of that category are shown or hidden.
/// - **Highlighted** = category is shown
/// - **Dimmed** = category is hidden
/// Click a button to toggle its category on/off. Use this to focus on specific
/// subsystems — e.g. click only "Tool" and "Streaming" to watch tool execution live.
public struct DebugPanelView: View {
    @ObservedObject private var debugLog = DebugLog.shared
    @ObservedObject private var debugger = AgentDebugger.shared
    @State private var showCopyConfirmation = false

    public var body: some View {
        if !debugger.isEnabled {
            disabledView
        } else {
            VStack(spacing: 0) {
                // ── Filter toolbar ──
                filterToolbar

                Divider().background(Color.borderSubtle)

                // ── Entry list ──
                if debugLog.filteredEntries.isEmpty {
                    emptyLogView
                } else {
                    entryList
                }
            }
            .background(Color.bgRightPanel)
        }
    }

    // MARK: - Disabled state

    private var disabledView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ladybug.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.textTertiary)
            Text("Debug Console is disabled")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
            Text("Enable it in Settings → General → Debug Console")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter toolbar

    private var filterToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Filter:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(width: 36, alignment: .trailing)

                // "All" / "None" quick toggles
                Button(action: { selectAllCategories() }) {
                    Text("All")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(allSelected ? Color.accentPrimary.opacity(0.3) : Color.bgElevated)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Show all categories")

                Button(action: { deselectAllCategories() }) {
                    Text("None")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(noneSelected ? Color.accentPrimary.opacity(0.3) : Color.bgElevated)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Hide all categories")

                Divider()
                    .frame(height: 14)
                    .background(Color.borderSubtle)

                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(DebugCategory.allCases, id: \.self) { cat in
                            Button(action: { toggleCategory(cat) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 7))
                                    Text(cat.rawValue)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(debugLog.activeCategories.contains(cat)
                                    ? categoryColor(cat).opacity(0.25)
                                    : Color.bgElevated.opacity(0.5))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(debugLog.activeCategories.contains(cat)
                                            ? categoryColor(cat).opacity(0.6)
                                            : Color.clear,
                                            lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Toggle \(cat.rawValue) entries — currently \(debugLog.activeCategories.contains(cat) ? "SHOWN" : "HIDDEN")")
                        }
                    }
                }

                Spacer()

                // Entry count + actions
                Text("\(debugLog.filteredEntries.count) entries  ·  \(debugLog.logFilePath)")
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button(action: { copyToClipboard() }) {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textTertiary)
                .help("Copy all visible entries to clipboard")

                Button(action: { debugLog.clear() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textTertiary)
                .help("Clear all entries")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color.bgElevated)
    }

    // MARK: - Entry list

    private var entryList: some View {
        ScrollViewReader { proxy in
            List(debugLog.filteredEntries.suffix(1000)) { entry in
                debugEntryRow(entry)
                    .id(entry.id)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .onChange(of: debugLog.filteredEntries.last?.id) { _, _ in
                if let last = debugLog.filteredEntries.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let last = debugLog.filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyLogView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.alignleft")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.textTertiary)
            Text("No entries yet")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)
            Text("Send a message or run an action to see debug logs here.\nUse the filter buttons above to show/hide categories.")
                .font(.system(size: 10))
                .foregroundColor(.textTertiary.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry row

    private func debugEntryRow(_ entry: DebugEntry) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(severityColor(entry.severity))
                .frame(width: 5, height: 5)

            Text(entry.formattedTimestamp)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.textTertiary)
                .frame(width: 52, alignment: .leading)

            Image(systemName: entry.category.icon)
                .font(.system(size: 8))
                .foregroundColor(categoryColor(entry.category))
                .frame(width: 12)

            Text(entry.subsystem)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(categoryColor(entry.category))
                .frame(width: 32, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(entry.severity == .error ? .danger : .textSecondary)
                .lineLimit(2)

            Spacer()

            if let first = entry.metadata.first {
                Text("\(first.key)=\(first.value)")
                    .font(.system(size: 7))
                    .foregroundColor(.textTertiary.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Filter logic

    private var allSelected: Bool {
        debugLog.activeCategories.count == DebugCategory.allCases.count
    }

    private var noneSelected: Bool {
        debugLog.activeCategories.isEmpty
    }

    private func toggleCategory(_ cat: DebugCategory) {
        if debugLog.activeCategories.contains(cat) {
            debugLog.activeCategories.remove(cat)
        } else {
            debugLog.activeCategories.insert(cat)
        }
    }

    private func selectAllCategories() {
        debugLog.activeCategories = Set(DebugCategory.allCases)
    }

    private func deselectAllCategories() {
        debugLog.activeCategories = []
    }

    private func copyToClipboard() {
        let text = debugLog.filteredEntries.map { entry in
            "[\(entry.formattedTimestamp)] [\(entry.severity.rawValue)] [\(entry.category.rawValue)] \(entry.subsystem): \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyConfirmation = false
        }
    }

    // MARK: - Colors

    private func severityColor(_ severity: DebugSeverity) -> Color {
        switch severity {
        case .debug: return .textTertiary
        case .info: return .accentPrimary
        case .warn: return .warning
        case .error: return .danger
        }
    }

    private func categoryColor(_ category: DebugCategory) -> Color {
        switch category {
        case .lifecycle: return .accentPrimary
        case .llm: return .accentPrimary
        case .tool: return .success
        case .mcp: return .warning
        case .skill: return .accentPrimary
        case .hook: return .warning
        case .permission: return .danger
        case .streaming: return .accentPrimary
        case .ui: return .textTertiary
        case .general: return .textSecondary
        }
    }
}
