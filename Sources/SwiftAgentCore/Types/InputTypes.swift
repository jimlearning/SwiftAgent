import Foundation

/// Text input and command queue types matching CC's textInputTypes.ts.

/// Vim editor modes. Matches CC's VimMode.
public enum VimMode: String, Sendable, Codable {
    case insert = "INSERT"
    case normal = "NORMAL"
}

/// Inline ghost text for mid-input command autocomplete. Matches CC's InlineGhostText.
public struct InlineGhostText: Sendable {
    public let text: String
    public let fullCommand: String
    public let insertPosition: Int

    public init(text: String, fullCommand: String, insertPosition: Int) {
        self.text = text
        self.fullCommand = fullCommand
        self.insertPosition = insertPosition
    }
}

/// Input modes for the prompt. Matches CC's PromptInputMode.
public enum PromptInputMode: String, Sendable, Codable {
    case bash
    case prompt
    case orphanedPermission = "orphaned-permission"
    case taskNotification = "task-notification"
}

/// Queue priority levels. Matches CC's QueuePriority.
public enum QueuePriority: String, Sendable, Codable {
    /// Interrupt and send immediately. Aborts any in-flight tool call.
    case now
    /// Mid-turn drain. Let current tool call finish, then send before next API round.
    case next
    /// End-of-turn drain. Wait for current turn to finish.
    case later
}

/// Orphaned permission tracking. Matches CC's OrphanedPermission.
public struct OrphanedPermission: Sendable {
    public let permissionResult: PermissionResult
    public let assistantMessage: Message

    public init(permissionResult: PermissionResult, assistantMessage: Message) {
        self.permissionResult = permissionResult
        self.assistantMessage = assistantMessage
    }
}

/// Pasted content type for paste burst detection. Matches CC's PastedContent.
public enum PastedContentType: String, Sendable, Codable {
    case text
    case image
}

/// Pasted content entry. Matches CC's PastedContent.
public struct PastedContent: Sendable {
    public let id: Int
    public let type: PastedContentType
    public let content: String

    public init(id: Int, type: PastedContentType, content: String) {
        self.id = id
        self.type = type
        self.content = content
    }
}

/// Queued command in the input pipeline. Matches CC's QueuedCommand.
public struct QueuedCommand: Sendable {
    public var value: String
    public var mode: PromptInputMode
    public var priority: QueuePriority?
    public var uuid: String?
    public var orphanedPermission: OrphanedPermission?
    public var pastedContents: [Int: PastedContent]?
    /// Input string before [Pasted text #N] placeholders were expanded.
    public var preExpansionValue: String?
    /// When true, input is treated as plain text even if it starts with `/`.
    public var skipSlashCommands: Bool
    /// When true, slash commands filtered through bridge-safe check.
    public var bridgeOrigin: Bool
    /// When true, the resulting UserMessage gets `isMeta: true`.
    public var isMeta: Bool
    /// Provenance of this command.
    public var origin: String?
    /// Workload tag for billing-header attribution.
    public var workload: String?
    /// Agent ID for routing to subagent (nil = main thread).
    public var agentId: AgentId?

    public init(
        value: String,
        mode: PromptInputMode = .prompt,
        priority: QueuePriority? = nil,
        uuid: String? = nil,
        orphanedPermission: OrphanedPermission? = nil,
        pastedContents: [Int: PastedContent]? = nil,
        preExpansionValue: String? = nil,
        skipSlashCommands: Bool = false,
        bridgeOrigin: Bool = false,
        isMeta: Bool = false,
        origin: String? = nil,
        workload: String? = nil,
        agentId: AgentId? = nil
    ) {
        self.value = value
        self.mode = mode
        self.priority = priority
        self.uuid = uuid
        self.orphanedPermission = orphanedPermission
        self.pastedContents = pastedContents
        self.preExpansionValue = preExpansionValue
        self.skipSlashCommands = skipSlashCommands
        self.bridgeOrigin = bridgeOrigin
        self.isMeta = isMeta
        self.origin = origin
        self.workload = workload
        self.agentId = agentId
    }
}

/// Reasons for exiting the CLI session.
/// Matches CC's EXIT_REASONS from coreTypes.ts.
public enum ExitReason: String, Sendable, Codable {
    case clear
    case resume
    case logout
    case promptInputExit = "prompt_input_exit"
    case other
    case bypassPermissionsDisabled = "bypass_permissions_disabled"
}
