import SwiftUI
import Foundation

// MARK: - Slash Command Definition

/// A slash command with metadata and optional argument definitions.
///
/// Commands can have zero or more arguments. When the user types
/// `/command ` (with a trailing space), the palette transitions
/// to argument completion mode.
public struct SlashCommandDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    /// The command trigger (e.g. "/help", "/model").
    public let command: String
    /// Human-readable description.
    public let description: String
    /// Category for grouping in the palette.
    public let category: Category
    /// Argument definitions for tab-completion after the command.
    public let arguments: [SlashArgument]

    public enum Category: String, CaseIterable, Sendable {
        case general   // Help, status, etc.
        case thread    // Thread operations
        case mode      // Mode toggles
        case session   // Session management
        case model     // Model selection
        case project   // Project operations
    }

    public init(
        command: String,
        description: String,
        category: Category,
        arguments: [SlashArgument] = []
    ) {
        self.id = command
        self.command = command
        self.description = description
        self.category = category
        self.arguments = arguments
    }
}

// MARK: - Slash Argument

/// Describes an argument for a slash command, with optional completion values.
public struct SlashArgument: Identifiable, Equatable, Sendable {
    public let id: String
    /// Display name (e.g. "model", "path", "level").
    public let name: String
    /// Placeholder shown when no value is entered.
    public let placeholder: String
    /// If true, the argument is required.
    public let isRequired: Bool
    /// Predefined completion values. If empty, the argument is free-form.
    public let completionValues: [String]
    /// If true, the completion values are filtered by the current input.
    public let isFilterable: Bool

    public init(
        name: String,
        placeholder: String = "",
        isRequired: Bool = false,
        completionValues: [String] = [],
        isFilterable: Bool = true
    ) {
        self.id = name
        self.name = name
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.completionValues = completionValues
        self.isFilterable = isFilterable
    }
}

// MARK: - Command Registry

/// Registry of all slash commands available in the app.
///
/// Commands are defined once and surfaced through the palette.
/// Providers (like model list) can update command arguments at runtime.
@MainActor
public enum SlashCommandRegistry {
    /// All slash commands in display order.
    public static var all: [SlashCommandDefinition] {
        builtinCommands + dynamicCommands
    }

    /// Static built-in commands.
    private static let builtinCommands: [SlashCommandDefinition] = [
        SlashCommandDefinition(
            command: "/help",
            description: "Show all available commands",
            category: .general
        ),
        SlashCommandDefinition(
            command: "/goal",
            description: "Set a goal for the agent",
            category: .thread,
            arguments: [
                SlashArgument(
                    name: "goal",
                    placeholder: "Describe the goal...",
                    isRequired: true
                )
            ]
        ),
        SlashCommandDefinition(
            command: "/plan",
            description: "Toggle Plan mode",
            category: .mode
        ),
        SlashCommandDefinition(
            command: "/skills",
            description: "List available skills",
            category: .general
        ),
        SlashCommandDefinition(
            command: "/mcp",
            description: "Manage MCP connections",
            category: .general
        ),
        SlashCommandDefinition(
            command: "/status",
            description: "Show thread status and context usage",
            category: .thread
        ),
        SlashCommandDefinition(
            command: "/compact",
            description: "Compact conversation context",
            category: .session
        ),
        SlashCommandDefinition(
            command: "/clear",
            description: "Clear current conversation context",
            category: .session
        ),
        SlashCommandDefinition(
            command: "/personality",
            description: "Toggle personality mode (Pragmatic / Friendly)",
            category: .mode,
            arguments: [
                SlashArgument(
                    name: "mode",
                    placeholder: "Pragmatic or Friendly",
                    completionValues: ["pragmatic", "friendly"]
                )
            ]
        ),
        SlashCommandDefinition(
            command: "/model",
            description: "Switch the active model",
            category: .model,
            arguments: [
                SlashArgument(
                    name: "model",
                    placeholder: "Model name...",
                    completionValues: [] // Populated dynamically
                )
            ]
        ),
        SlashCommandDefinition(
            command: "/exit",
            description: "Exit current mode",
            category: .session
        ),
    ]

    /// Dynamic commands that can be updated at runtime (e.g. model list).
    private static var dynamicCommands: [SlashCommandDefinition] = []

    /// Update the model list argument for the `/model` command.
    public static func updateModelList(_ models: [String]) {
        // Rebuild the /model command with current models
        dynamicCommands = [
            SlashCommandDefinition(
                command: "/model",
                description: "Switch the active model",
                category: .model,
                arguments: [
                    SlashArgument(
                        name: "model",
                        placeholder: "Model name...",
                        completionValues: models
                    )
                ]
            )
        ]
    }

    /// Find a command by its trigger string.
    public static func find(_ command: String) -> SlashCommandDefinition? {
        all.first { $0.command == command }
    }
}
