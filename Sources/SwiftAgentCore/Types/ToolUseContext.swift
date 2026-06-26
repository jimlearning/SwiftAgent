import Foundation

/// Execution context passed to tools during invocation.
/// Simplified from the original 100+-field struct — most fields were
/// consumed by the old agent loop (QueryEngine) and are no longer needed.
/// Survivors (PermissionEngine, SlashCommand, BundledSkills) use only
/// a narrow subset: sandbox, permission mode, and as a parameter type.
///
/// Extra fields (sessionID, toolUseID, permissionPromptHandler, etc.) are
/// temporary compatibility shims for deprecated Agent/ code. They will be
/// removed when those files are deleted in Plans 04-05/04-06.
public struct ToolUseContext: Sendable {
    public let workingDirectory: String
    public let mode: PermissionMode
    public var sandbox: Bool?

    // Temporary compat fields (for deprecated Agent/ code)
    public var sessionID: String = ""
    public var toolUseID: String? = nil
    public var permissionPromptHandler: (@Sendable (String, String) async -> Bool)? = nil
    public var shouldAvoidPermissionPrompts: Bool = false
    public var isBypassPermissionsModeAvailable: Bool = false

    public init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        mode: PermissionMode = .default,
        sandbox: Bool? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.mode = mode
        self.sandbox = sandbox
    }

    public static let `default` = ToolUseContext()
}
