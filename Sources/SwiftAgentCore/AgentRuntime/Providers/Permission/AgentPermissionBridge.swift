import Foundation

/// Thin adapter that wraps the existing PermissionEngine and conforms to
/// RuntimePermissionEngine. Maps AgentPermission enum cases to tool-name-based
/// permission checks that the existing pipeline understands.
///
/// This is the post-migration permission bridge. The legacy permission paths
/// are deprecated and will be removed in a future phase.
public struct AgentPermissionBridge: RuntimePermissionEngine, Sendable {

    private let engine: PermissionEngine
    private let mode: PermissionMode

    /// Create a bridge wrapping an existing PermissionEngine.
    ///
    /// - Parameters:
    ///   - engine: The existing PermissionEngine to delegate permission checks to.
    ///   - mode: The PermissionMode used for all `.check(_:)` delegations.
    public init(engine: PermissionEngine, mode: PermissionMode = .default) {
        self.engine = engine
        self.mode = mode
    }

    /// Check whether the given AgentPermission is granted.
    ///
    /// Maps each AgentPermission case to the appropriate tool name and delegates
    /// to the wrapped PermissionEngine. Uses exhaustive switch (no default case)
    /// so the compiler enforces coverage of all 13 cases.
    public func check(_ permission: AgentPermission) async throws -> Bool {
        switch permission {
        case .runCommands:
            let verdict = await engine.check(
                toolName: "Bash",
                input: [:],
                mode: mode,
                context: .default
            )
            return verdict.decision == .allow

        case .readFiles(let paths):
            let verdict = await engine.check(
                toolName: "Read",
                input: ["file_path": .string(paths.joined(separator: ","))],
                mode: mode,
                context: .default
            )
            return verdict.decision == .allow

        case .writeFiles(let paths):
            let verdict = await engine.check(
                toolName: "Write",
                input: ["file_path": .string(paths.joined(separator: ","))],
                mode: mode,
                context: .default
            )
            return verdict.decision == .allow

        case .network(let domains):
            let verdict = await engine.check(
                toolName: "WebFetch",
                input: ["url": .string(domains.joined(separator: ","))],
                mode: mode,
                context: .default
            )
            return verdict.decision == .allow

        case .all:
            return true

        case .default:
            return mode == .default

        case .plan:
            return mode == .plan

        case .contacts, .calendar, .location, .camera, .microphone, .delete:
            // Deny-by-default for unestablished permissions.
            // These have no corresponding rules in the existing PermissionEngine.
            return false
        }
    }
}
