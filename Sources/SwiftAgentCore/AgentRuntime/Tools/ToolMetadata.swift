import Foundation

// InterruptBehavior is defined in Types/Tool.swift (enum InterruptBehavior: String, Sendable).

// MARK: - ToolMetadata

/// Per-tool operational data separated from the Tool protocol.
/// Populated at registration time via ToolEngine.
public struct ToolMetadata: Sendable {
    /// Search hint for tool discovery (3-10 words).
    public var searchHint: String?

    /// Whether this tool is currently enabled.
    public var isEnabled: Bool

    /// Whether this tool is read-only (safe for auto-approval).
    public var isReadOnly: Bool

    /// Whether this tool is safe to run concurrently.
    public var isConcurrencySafe: Bool

    /// Whether this tool performs destructive operations.
    public var isDestructive: Bool

    /// Tool interruption behavior during concurrent user input.
    public var interruptBehavior: InterruptBehavior

    /// Human-readable activity description for spinner display.
    public var activityDescription: String?

    /// Whether this tool requires explicit user approval.
    public var requiresApproval: Bool

    /// Permission category for this tool.
    public var permissionCategory: AgentPermission?

    public init(
        searchHint: String? = nil,
        isEnabled: Bool = true,
        isReadOnly: Bool = false,
        isConcurrencySafe: Bool = false,
        isDestructive: Bool = false,
        interruptBehavior: InterruptBehavior = .block,
        activityDescription: String? = nil,
        requiresApproval: Bool = true,
        permissionCategory: AgentPermission? = nil
    ) {
        self.searchHint = searchHint
        self.isEnabled = isEnabled
        self.isReadOnly = isReadOnly
        self.isConcurrencySafe = isConcurrencySafe
        self.isDestructive = isDestructive
        self.interruptBehavior = interruptBehavior
        self.activityDescription = activityDescription
        self.requiresApproval = requiresApproval
        self.permissionCategory = permissionCategory
    }
}
