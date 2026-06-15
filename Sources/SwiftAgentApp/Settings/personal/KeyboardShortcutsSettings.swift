import SwiftUI

/// Represents a single keyboard shortcut entry (for the settings table).
struct ShortcutEntry: Identifiable {
    let id: String
    let category: String
    let action: String
    let shortcut: String
    let alternate: String?
}

struct KeyboardShortcutsSettingsView: View {
    @State private var searchText: String = ""

    let allShortcuts: [ShortcutEntry] = ShortcutRegistry.allEntries

    var filteredShortcuts: [ShortcutEntry] {
        if searchText.isEmpty { return allShortcuts }
        let q = searchText.lowercased()
        return allShortcuts.filter {
            $0.action.lowercased().contains(q) ||
            $0.shortcut.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Keyboard shortcuts")

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                    .font(.system(size: 12))
                TextField("Filter shortcuts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bgInput)
            .cornerRadius(6)
            .accessibilityLabel("Search keyboard shortcuts")

            // Shortcut table
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Action")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Shortcut")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 120, alignment: .leading)
                    Text("Alternate")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 120, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.bgElevated)

                Divider().background(Color.borderSubtle)

                // Data rows
                ShortcutTableRows(entries: filteredShortcuts)
            }
            .background(Color.bgInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            )
            .accessibilityLabel("Keyboard shortcuts table")

            Spacer()
        }
        .padding(24)
    }
}

/// Separate view for the shortcut table rows to avoid ViewBuilder restrictions.
struct ShortcutTableRows: View {
    let entries: [ShortcutEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                let grouped = groupByCategory(entries)
                ForEach(grouped.indices, id: \.self) { groupIdx in
                    let group = grouped[groupIdx]
                    // Category header
                    HStack {
                        Text(group.category)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        Spacer()
                    }
                    .background(Color.bgSidebar)

                    ForEach(group.entries) { entry in
                        HStack(spacing: 0) {
                            Text(entry.action)
                                .font(.system(size: 12))
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.shortcut)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.accentPrimary)
                                .frame(width: 120, alignment: .leading)
                            Text(entry.alternate ?? "\u{2014}")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.textTertiary)
                                .frame(width: 120, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        Divider().background(Color.borderSubtle.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    struct CategoryGroup {
        let category: String
        let entries: [ShortcutEntry]
    }

    func groupByCategory(_ entries: [ShortcutEntry]) -> [CategoryGroup] {
        var result: [CategoryGroup] = []
        for category in categoryOrder(entries: entries) {
            let groupEntries = entries.filter { $0.category == category }
            if !groupEntries.isEmpty {
                result.append(CategoryGroup(category: category, entries: groupEntries))
            }
        }
        return result
    }

    func categoryOrder(entries: [ShortcutEntry]) -> [String] {
        let seen = NSOrderedSet(array: entries.map(\.category))
        return seen.array as? [String] ?? []
    }
}
