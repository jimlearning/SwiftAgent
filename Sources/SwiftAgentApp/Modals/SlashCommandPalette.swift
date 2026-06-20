import SwiftUI

// MARK: - Slash Command Palette View

/// Popover palette that appears when the user types "/" in the composer.
///
/// Shows filtered slash commands with arrow key navigation.
///
/// ## Two-phase completion
/// 1. **Command selection**: User types `/` → sees command list → picks one
/// 2. **Argument completion**: If the command has arguments, user can tab-complete them
///    from predefined values or type free-form
public struct SlashCommandPalette: View {
    @Binding var filterText: String
    let onSelect: (SlashCommandDefinition) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    // MARK: - Filtered Commands

    private var filteredCommands: [SlashCommandDefinition] {
        let query = String(filterText.dropFirst()).lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return SlashCommandRegistry.all
        }
        return SlashCommandRegistry.all.filter {
            $0.command.lowercased().contains(query)
            || $0.description.lowercased().contains(query)
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Commands")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                Spacer()
                Text("↑↓ to navigate  ↵ to select  esc to dismiss")
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if filteredCommands.isEmpty {
                Text("No matching commands")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(filteredCommands.enumerated()), id: \.element.id) { idx, cmd in
                        Button {
                            onSelect(cmd)
                        } label: {
                            commandRow(cmd, isSelected: idx == selectedIndex)
                        }
                        .buttonStyle(.plain)
                        .id(idx)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: selectedIndex) { _, newIdx in
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 420, height: 300)
        .background(Color.bgContent)
        .onAppear { selectedIndex = 0 }
        .onChange(of: filterText) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if let cmd = filteredCommands[safe: selectedIndex] {
                onSelect(cmd)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Command Row

    private func commandRow(_ cmd: SlashCommandDefinition, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Category icon
            Image(systemName: cmd.category.iconName)
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .textPrimary : .textTertiary)
                .frame(width: 16)

            // Command name
            Text(cmd.command)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentPrimary)
                .frame(width: 120, alignment: .leading)

            // Description
            Text(cmd.description)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)

            Spacer()

            // Argument count badge
            if !cmd.arguments.isEmpty {
                Text("\(cmd.arguments.count) arg\(cmd.arguments.count == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.textTertiary.opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.bgElevated : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Category Icon

extension SlashCommandDefinition.Category {
    var iconName: String {
        switch self {
        case .general: return "questionmark.circle"
        case .thread:  return "bubble.left.and.bubble.right"
        case .mode:    return "switch.2"
        case .session: return "clock"
        case .model:   return "cpu"
        case .project: return "folder"
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
