import Foundation

// MARK: - AgentPermission

/// Runtime-level permission taxonomy. Not tool-level — these are
/// the capability categories that AgentRuntime gates.
///
/// Forward-compatible with predicted WWDC27 AgentSandbox and macOS
/// permission model (TCC framework extension for AI agents).
public enum AgentPermission: Sendable, CaseIterable {
    /// Read access to filesystem paths.
    case readFiles(paths: Set<String>)

    /// Write/modify access to filesystem paths.
    case writeFiles(paths: Set<String>)

    /// Network access to specified domains.
    case network(domains: Set<String>)

    /// Access to user contacts.
    case contacts

    /// Access to user calendar.
    case calendar

    /// Access to device location.
    case location

    /// Access to camera.
    case camera

    /// Access to microphone.
    case microphone

    /// Execute arbitrary shell commands.
    case runCommands

    /// Delete files or resources.
    case delete

    /// Unrestricted access (all permissions granted).
    case all

    /// Default permission set (read-only files, no network, no shell).
    case `default`

    /// Plan-only mode — no mutations allowed.
    case plan

    /// Manual CaseIterable conformance required because cases with
    /// associated values cannot be auto-synthesized. Associated-value
    /// cases return empty sets in allCases.
    public static var allCases: [AgentPermission] {
        [
            .readFiles(paths: []),
            .writeFiles(paths: []),
            .network(domains: []),
            .contacts,
            .calendar,
            .location,
            .camera,
            .microphone,
            .runCommands,
            .delete,
            .all,
            .default,
            .plan,
        ]
    }
}

// MARK: - RuntimePermissionEngine Protocol

/// Runtime-level capability gate for agent permissions.
///
/// Named RuntimePermissionEngine to avoid collision with the existing
/// `PermissionEngine` struct in `Safety/PermissionEngine.swift`. This is
/// a Phase 1 protocol definition that defines the contract for
/// runtime-level permission checks. The existing `PermissionEngine`
/// struct remains unchanged until Phase 3, when it will be updated to
/// conform to this (or a compatible) protocol.
///
/// All tool calls, memory reads/writes, and network requests pass
/// through a unified permission check via this protocol.
public protocol RuntimePermissionEngine: Sendable {
    /// Check whether the given permission is granted at the runtime level.
    ///
    /// - Parameter permission: The capability being requested.
    /// - Returns: `true` if the permission is granted.
    /// - Throws: May throw if the permission check itself encounters an error.
    func check(_ permission: AgentPermission) async throws -> Bool
}
