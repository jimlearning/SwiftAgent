import Foundation

// MARK: - ConfigTool

/// Gets or sets Claude Code configuration settings.
/// Matches Claude Code's ConfigTool with supported settings.
public struct ConfigTool: Tool {
    public let name = "Config"
    public var searchHint: String? { "get or set Claude Code settings (theme, model)" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Get or set Claude Code configuration settings." }
    /// CC: isReadOnly depends on whether a value is being set.
    /// isReadOnly(input) returns true (read-only) when value is undefined (get mode).
    /// Returns false (writable) when value is provided (set mode).
    public func isReadOnly(_ input: [String: JSONValue]) -> Bool {
        if input["value"] == nil { return true }
        return false
    }
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["setting"] = JSONSchemaProperty(type: "string", description: "The setting key (e.g., \"theme\", \"model\", \"permissions.defaultMode\")")
        schema.properties?["value"] = JSONSchemaProperty(type: "string", description: "The new value. Can be any JSON type. Omit to get current value.")
        schema.required = ["setting"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let setting) = input["setting"] else {
            return ToolResult(content: "Error: setting is required", isError: true)
        }

        guard SUPPORTED_SETTINGS[setting] != nil else {
            return ToolResult(content: "Unknown setting: \"\(setting)\"", isError: true)
        }

        let config = SUPPORTED_SETTINGS[setting]!

        // GET operation
        guard let rawValue = input["value"] else {
            let current = getSettingValue(setting, source: config.source)
            let displayValue = current.map { "\($0)" } ?? "undefined"
            return ToolResult(content: "\(setting) = \(displayValue)")
        }

        // SET operation
        let valueStr: String
        if case .string(let s) = rawValue { valueStr = s }
        else if case .bool(let b) = rawValue { valueStr = b ? "true" : "false" }
        else if case .number(let n) = rawValue { valueStr = "\(n)" }
        else { valueStr = "\(rawValue)" }

        var finalValue: String

        // Coerce booleans
        if config.type == "boolean" {
            let lower = valueStr.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "true" { finalValue = "true" }
            else if lower == "false" { finalValue = "false" }
            else {
                return ToolResult(content: "\(setting) requires true or false.", isError: true)
            }
        } else {
            finalValue = valueStr
        }

        // Validate options
        if let options = config.options, !options.contains(finalValue) {
            return ToolResult(content: "Invalid value \"\(valueStr)\". Options: \(options.joined(separator: ", "))", isError: true)
        }

        let previousValue = getSettingValue(setting, source: config.source)
        setSettingValue(setting, value: finalValue, source: config.source)

        return ToolResult(content: """
            Set \(setting) to \(finalValue)
            Previous value: \(previousValue.map { "\($0)" } ?? "undefined")
            """)
    }

    // MARK: - Private

    private func getSettingValue(_ key: String, source: String) -> Any? {
        UserDefaults.standard.object(forKey: "config_\(key)")
    }

    private func setSettingValue(_ key: String, value: String, source: String) {
        UserDefaults.standard.set(value, forKey: "config_\(key)")
    }
}

// MARK: - Supported Settings

private struct SettingConfig {
    let source: String
    let type: String
    let description: String
    let options: [String]?
}

private let SUPPORTED_SETTINGS: [String: SettingConfig] = [
    "theme": SettingConfig(source: "global", type: "string", description: "Color theme for the UI", options: ["dark", "light", "system"]),
    "editorMode": SettingConfig(source: "global", type: "string", description: "Key binding mode", options: ["normal", "vim", "emacs"]),
    "verbose": SettingConfig(source: "global", type: "boolean", description: "Show detailed debug output", options: nil),
    "autoCompactEnabled": SettingConfig(source: "global", type: "boolean", description: "Auto-compact when context is full", options: nil),
    "autoMemoryEnabled": SettingConfig(source: "settings", type: "boolean", description: "Enable auto-memory", options: nil),
    "fileCheckpointingEnabled": SettingConfig(source: "global", type: "boolean", description: "Enable file checkpointing for code rewind", options: nil),
    "showTurnDuration": SettingConfig(source: "global", type: "boolean", description: "Show turn duration message after responses", options: nil),
    "todoFeatureEnabled": SettingConfig(source: "global", type: "boolean", description: "Enable todo/task tracking", options: nil),
    "model": SettingConfig(source: "settings", type: "string", description: "Override the default model", options: ["sonnet", "opus", "haiku", "default"]),
    "alwaysThinkingEnabled": SettingConfig(source: "settings", type: "boolean", description: "Enable extended thinking", options: nil),
    "permissions.defaultMode": SettingConfig(source: "settings", type: "string", description: "Default permission mode for tool usage", options: ["default", "plan", "acceptEdits", "dontAsk", "auto"]),
    "language": SettingConfig(source: "settings", type: "string", description: "Preferred language for Claude responses", options: nil),
]
