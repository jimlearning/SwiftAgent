import Foundation

/// Sandbox settings for bash command execution.
/// Mirrors Claude Code's `SandboxSettings`.
public struct SandboxSettings: Codable, Sendable {
    public var enabled: Bool?
    public var failIfUnavailable: Bool?
    public var autoAllowBashIfSandboxed: Bool?
    public var allowUnsandboxedCommands: Bool?
    public var network: SandboxNetworkConfig?
    public var filesystem: SandboxFilesystemConfig?
    public var ignoreViolations: [String: [String]]?
    public var enableWeakerNestedSandbox: Bool?
    public var enableWeakerNetworkIsolation: Bool?
    public var excludedCommands: [String]?
    public var ripgrep: SandboxRipgrepConfig?

    public init(
        enabled: Bool? = nil,
        failIfUnavailable: Bool? = nil,
        autoAllowBashIfSandboxed: Bool? = nil,
        allowUnsandboxedCommands: Bool? = nil,
        network: SandboxNetworkConfig? = nil,
        filesystem: SandboxFilesystemConfig? = nil,
        ignoreViolations: [String: [String]]? = nil,
        enableWeakerNestedSandbox: Bool? = nil,
        enableWeakerNetworkIsolation: Bool? = nil,
        excludedCommands: [String]? = nil,
        ripgrep: SandboxRipgrepConfig? = nil
    ) {
        self.enabled = enabled
        self.failIfUnavailable = failIfUnavailable
        self.autoAllowBashIfSandboxed = autoAllowBashIfSandboxed
        self.allowUnsandboxedCommands = allowUnsandboxedCommands
        self.network = network
        self.filesystem = filesystem
        self.ignoreViolations = ignoreViolations
        self.enableWeakerNestedSandbox = enableWeakerNestedSandbox
        self.enableWeakerNetworkIsolation = enableWeakerNetworkIsolation
        self.excludedCommands = excludedCommands
        self.ripgrep = ripgrep
    }
}

/// Network restrictions for sandbox mode.
public struct SandboxNetworkConfig: Codable, Sendable {
    public var allowedDomains: [String]?
    public var allowManagedDomainsOnly: Bool?
    public var allowUnixSockets: [String]?
    public var allowAllUnixSockets: Bool?
    public var allowLocalBinding: Bool?
    public var httpProxyPort: Int?
    public var socksProxyPort: Int?

    public init(
        allowedDomains: [String]? = nil,
        allowManagedDomainsOnly: Bool? = nil,
        allowUnixSockets: [String]? = nil,
        allowAllUnixSockets: Bool? = nil,
        allowLocalBinding: Bool? = nil,
        httpProxyPort: Int? = nil,
        socksProxyPort: Int? = nil
    ) {
        self.allowedDomains = allowedDomains
        self.allowManagedDomainsOnly = allowManagedDomainsOnly
        self.allowUnixSockets = allowUnixSockets
        self.allowAllUnixSockets = allowAllUnixSockets
        self.allowLocalBinding = allowLocalBinding
        self.httpProxyPort = httpProxyPort
        self.socksProxyPort = socksProxyPort
    }
}

/// Filesystem restrictions for sandbox mode.
public struct SandboxFilesystemConfig: Codable, Sendable {
    public var allowWrite: [String]?
    public var denyWrite: [String]?
    public var denyRead: [String]?
    public var allowRead: [String]?
    public var allowManagedReadPathsOnly: Bool?

    public init(
        allowWrite: [String]? = nil,
        denyWrite: [String]? = nil,
        denyRead: [String]? = nil,
        allowRead: [String]? = nil,
        allowManagedReadPathsOnly: Bool? = nil
    ) {
        self.allowWrite = allowWrite
        self.denyWrite = denyWrite
        self.denyRead = denyRead
        self.allowRead = allowRead
        self.allowManagedReadPathsOnly = allowManagedReadPathsOnly
    }
}

/// Ripgrep configuration override for sandbox.
public struct SandboxRipgrepConfig: Codable, Sendable {
    public var command: String
    public var args: [String]?

    public init(command: String, args: [String]? = nil) {
        self.command = command
        self.args = args
    }
}
