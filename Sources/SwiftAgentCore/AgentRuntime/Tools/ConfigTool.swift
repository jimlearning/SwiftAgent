import Foundation

/// Gets or sets SwiftAgent configuration settings.
/// Matches Claude Code's ConfigTool with supported settings.
public struct ConfigTool: Tool {
    public let name = "Config"
    public let description = "Get or set SwiftAgent configuration settings."

    public struct Arguments: Codable, Sendable {
        public var setting: String
        public var value: String?

        enum CodingKeys: String, CodingKey {
            case setting
            case value
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["setting"] = JSONSchemaProperty(
            type: "string",
            description: "The setting key (e.g., \"theme\", \"model\", \"permissions.defaultMode\")"
        )
        schema.properties?["value"] = JSONSchemaProperty(
            type: "string",
            description: "The new value. Can be any JSON type. Omit to get current value."
        )
        schema.required = ["setting"]
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let setting = arguments.setting

        guard SUPPORTED_SETTINGS[setting] != nil else {
            return .string("Unknown setting: \"\(setting)\"")
        }

        let config = SUPPORTED_SETTINGS[setting]!

        // GET operation
        guard let rawValue = arguments.value else {
            let current = getSettingValue(setting)
            let displayValue = current.map { "\($0)" } ?? "undefined"
            return .string("\(setting) = \(displayValue)")
        }

        // SET operation
        let valueStr: String
        // The value comes as a String from JSON — no type switching needed
        valueStr = rawValue

        var finalValue: String
        let trimmed = valueStr.trimmingCharacters(in: .whitespaces)

        // Coerce booleans
        if config.type == "boolean" {
            let lower = trimmed.lowercased()
            if lower == "true" { finalValue = "true" }
            else if lower == "false" { finalValue = "false" }
            else {
                return .string("\(setting) requires true or false.")
            }
        } else {
            finalValue = valueStr
        }

        // Validate options
        if let options = config.options, !options.contains(finalValue) {
            return .string("Invalid value \"\(valueStr)\". Options: \(options.joined(separator: ", "))")
        }

        let previousValue = getSettingValue(setting)
        setSettingValue(setting, value: finalValue)

        return .string("""
            Set \(setting) to \(finalValue)
            Previous value: \(previousValue.map { "\($0)" } ?? "undefined")
            """)
    }

    // MARK: - Private Helpers

    private func getSettingValue(_ key: String) -> Any? {
        UserDefaults.standard.object(forKey: "config_\(key)")
    }

    private func setSettingValue(_ key: String, value: String) {
        UserDefaults.standard.set(value, forKey: "config_\(key)")
    }
}

// MARK: - Supported Settings

private struct SettingConfig {
    let type: String
    let description: String
    let options: [String]?
}

private let SUPPORTED_SETTINGS: [String: SettingConfig] = [
    "theme": SettingConfig(
        type: "string",
        description: "Color theme for the UI",
        options: ["dark", "light", "system"]
    ),
    "editorMode": SettingConfig(
        type: "string",
        description: "Key binding mode",
        options: ["normal", "vim", "emacs"]
    ),
    "verbose": SettingConfig(
        type: "boolean",
        description: "Show detailed debug output",
        options: nil
    ),
    "autoCompactEnabled": SettingConfig(
        type: "boolean",
        description: "Auto-compact when context is full",
        options: nil
    ),
    "autoMemoryEnabled": SettingConfig(
        type: "boolean",
        description: "Enable auto-memory",
        options: nil
    ),
    "fileCheckpointingEnabled": SettingConfig(
        type: "boolean",
        description: "Enable file checkpointing for code rewind",
        options: nil
    ),
    "showTurnDuration": SettingConfig(
        type: "boolean",
        description: "Show turn duration message after responses",
        options: nil
    ),
    "todoFeatureEnabled": SettingConfig(
        type: "boolean",
        description: "Enable todo/task tracking",
        options: nil
    ),
    "model": SettingConfig(
        type: "string",
        description: "Override the default model",
        options: ["sonnet", "opus", "haiku", "default"]
    ),
    "alwaysThinkingEnabled": SettingConfig(
        type: "boolean",
        description: "Enable extended thinking",
        options: nil
    ),
    "permissions.defaultMode": SettingConfig(
        type: "string",
        description: "Default permission mode for tool usage",
        options: ["default", "plan", "acceptEdits", "dontAsk", "auto"]
    ),
    "language": SettingConfig(
        type: "string",
        description: "Preferred language for responses",
        options: nil
    ),
]
