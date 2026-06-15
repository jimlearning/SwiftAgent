import SwiftUI

// MARK: - Slash Command Definition

/// A slash command available in the composer.
public struct SlashCommand: Identifiable, Equatable, Sendable {
    public let id: String
    public let command: String
    public let description: String
    public let category: Category

    public enum Category: String, CaseIterable, Sendable {
        case general
        case thread
        case mode
        case session
    }

    public init(command: String, description: String, category: Category) {
        self.id = command
        self.command = command
        self.description = description
        self.category = category
    }

    /// All available slash commands.
    public static let all: [SlashCommand] = [
        SlashCommand(command: "/help", description: "Show all available commands", category: .general),
        SlashCommand(command: "/goal", description: "Set a goal for the agent", category: .thread),
        SlashCommand(command: "/plan", description: "Toggle Plan mode", category: .mode),
        SlashCommand(command: "/skills", description: "List available skills", category: .general),
        SlashCommand(command: "/mcp", description: "Manage MCP connections", category: .general),
        SlashCommand(command: "/status", description: "Show thread status and context usage", category: .thread),
        SlashCommand(command: "/compact", description: "Compact conversation context", category: .session),
        SlashCommand(command: "/clear", description: "Clear current conversation context", category: .session),
        SlashCommand(command: "/personality", description: "Toggle between Pragmatic / Friendly", category: .mode),
        SlashCommand(command: "/exit", description: "Exit current mode", category: .session),
    ]
}

// MARK: - Slash Command Palette View

/// Popover palette that appears when user types "/" in the composer.
/// Shows filtered slash commands with arrow key navigation.
public struct SlashCommandPalette: View {
    @Binding var filterText: String
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    /// Filtered commands based on text after "/".
    private var filteredCommands: [SlashCommand] {
        let query = String(filterText.dropFirst()).lowercased()
        if query.isEmpty {
            return SlashCommand.all
        }
        return SlashCommand.all.filter {
            $0.command.lowercased().contains(query)
            || $0.description.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Commands")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            if filteredCommands.isEmpty {
                Text("No matching commands")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(16)
            } else {
                List(Array(filteredCommands.enumerated()), id: \.element.id) { idx, cmd in
                    Button {
                        onSelect(cmd)
                    } label: {
                        HStack(spacing: 8) {
                            Text(cmd.command)
                                .font(.codeTag)
                                .foregroundColor(.accentPrimary)
                                .frame(width: 100, alignment: .leading)
                            Text(cmd.description)
                                .font(.uiCaption)
                                .foregroundColor(.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(idx == selectedIndex ? Color.bgElevated : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 380, height: 300)
        .background(Color.bgContent)
        .onAppear {
            selectedIndex = 0
        }
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
