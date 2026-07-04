import Foundation

/// Thin adapter that wraps the existing PermissionEngine and conforms to
/// SessionPermissionEngine. Maps AgentPermission enum cases to tool-name-based
/// permission checks that the existing pipeline understands.
///
/// This is the post-migration permission bridge. The legacy permission paths
/// are deprecated and will be removed in a future phase.
///
/// The `mode` property is settable so the UI can toggle permission mode
/// at runtime without recreating the session.
public final class AgentPermissionBridge: SessionPermissionEngine, @unchecked Sendable {

    private let engine: PermissionEngine
    public var mode: PermissionMode

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
    public func check(_ permission: AgentPermission) async throws -> PermissionCheckResult {
        switch permission {
        case .runCommands:
            let verdict = await engine.check(
                toolName: "Bash",
                input: [:],
                mode: mode,
                context: .default
            )
            return verdict.decision == .deny
                ? .denied(reason: verdict.reason ?? "blocked by permission engine")
                : .allowed

        case .readFiles(let paths):
            // Only include file_path if actual paths exist; an empty string
            // triggers a false-positive safety deny via validatePath("").
            var input: [String: JSONValue] = [:]
            if !paths.isEmpty {
                input["file_path"] = .string(paths.joined(separator: ","))
            }
            let verdict = await engine.check(
                toolName: "Read",
                input: input,
                mode: mode,
                context: .default
            )
            return verdict.decision == .deny
                ? .denied(reason: verdict.reason ?? "blocked by permission engine")
                : .allowed

        case .writeFiles(let paths):
            var input: [String: JSONValue] = [:]
            if !paths.isEmpty {
                input["file_path"] = .string(paths.joined(separator: ","))
            }
            let verdict = await engine.check(
                toolName: "Write",
                input: input,
                mode: mode,
                context: .default
            )
            return verdict.decision == .deny
                ? .denied(reason: verdict.reason ?? "blocked by permission engine")
                : .allowed

        case .network(let domains):
            var input: [String: JSONValue] = [:]
            if !domains.isEmpty {
                input["url"] = .string(domains.joined(separator: ","))
            }
            let verdict = await engine.check(
                toolName: "WebFetch",
                input: input,
                mode: mode,
                context: .default
            )
            return verdict.decision == .deny
                ? .denied(reason: verdict.reason ?? "blocked by permission engine")
                : .allowed

        case .all:
            return .allowed

        case .default:
            return mode == .default ? .allowed : .denied(reason: "AgentPermission.default requires .default PermissionMode")

        case .plan:
            return mode == .plan ? .allowed : .denied(reason: "AgentPermission.plan requires .plan PermissionMode")

        case .contacts, .calendar, .location, .camera, .microphone, .delete:
            let verdict = await engine.check(
                toolName: permission.toolName,
                input: [:],
                mode: mode,
                context: .default
            )
            return verdict.decision == .deny
                ? .denied(reason: verdict.reason ?? "blocked by permission engine")
                : .allowed
        }
    }
}
