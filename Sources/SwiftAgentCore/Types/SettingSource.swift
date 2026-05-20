import Foundation

/// Where a configuration setting originated.
/// Mirrors Claude Code's `SettingSource`.
public enum SettingSource: String, Codable, Sendable, CaseIterable {
    case userSettings
    case projectSettings
    case localSettings
    case flagSettings
    case policySettings
}

/// Editable setting sources (excludes policy and flag overrides).
public typealias EditableSettingSource = SettingSource
public let editableSettingSources: [SettingSource] = [.localSettings, .projectSettings, .userSettings]

/// Where a skill or command was loaded from.
/// Mirrors Claude Code's `LoadedFrom`.
public enum LoadedFrom: String, Codable, Sendable {
    case commandsDEPRECATED = "commands_DEPRECATED"
    case skills
    case plugin
    case managed
    case bundled
    case mcp
}
