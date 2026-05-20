import Foundation

// MARK: - Hook JSON Output (stdout/exit-code protocol)

/// The JSON that a hook process prints to stdout.
/// Mirrors Claude Code's HookJSONOutput discriminated union: async | sync.
public enum HookJSONOutput: Sendable {
    case async(AsyncHookJSONOutput)
    case sync(SyncHookJSONOutput)
}

/// Async hook response — model continues immediately; hook runs in background.
/// Matches CC's AsyncHookJSONOutput: { async: true, asyncTimeout?: number }.
public struct AsyncHookJSONOutput: Sendable {
    public let async: Bool  // always true
    public let asyncTimeout: Int?

    public init(asyncTimeout: Int? = nil) {
        self.async = true
        self.asyncTimeout = asyncTimeout
    }
}

/// Sync hook response — model waits for hook to complete.
/// Matches CC's SyncHookJSONOutput with all common fields + hookSpecificOutput union.
public struct SyncHookJSONOutput: Sendable {
    public let `continue`: Bool?
    public let suppressOutput: Bool?
    public let stopReason: String?
    public let decision: HookDecision?
    public let systemMessage: String?
    public let reason: String?
    public let hookSpecificOutput: HookSpecificOutput?

    public init(
        continue: Bool? = nil,
        suppressOutput: Bool? = nil,
        stopReason: String? = nil,
        decision: HookDecision? = nil,
        systemMessage: String? = nil,
        reason: String? = nil,
        hookSpecificOutput: HookSpecificOutput? = nil
    ) {
        self.continue = `continue`
        self.suppressOutput = suppressOutput
        self.stopReason = stopReason
        self.decision = decision
        self.systemMessage = systemMessage
        self.reason = reason
        self.hookSpecificOutput = hookSpecificOutput
    }
}

/// Approve/block decision for synchronous hook control flow.
/// Matches CC's decision: 'approve' | 'block'.
public enum HookDecision: String, Sendable {
    case approve
    case block
}

// MARK: - Hook-Specific Outputs (14 event-specific schemas)

/// Discriminated union of per-event hook outputs.
/// Matches CC's hookSpecificOutput union (15 members, discriminated by hookEventName).
public enum HookSpecificOutput: Sendable {
    case preToolUse(PreToolUseHookOutput)
    case userPromptSubmit(UserPromptSubmitHookOutput)
    case sessionStart(SessionStartHookOutput)
    case setup(SetupHookOutput)
    case subagentStart(SubagentStartHookOutput)
    case postToolUse(PostToolUseHookOutput)
    case postToolUseFailure(PostToolUseFailureHookOutput)
    case permissionDenied(PermissionDeniedHookOutput)
    case notification(NotificationHookOutput)
    case permissionRequest(PermissionRequestHookOutput)
    case elicitation(ElicitationHookOutput)
    case elicitationResult(ElicitationResultHookOutput)
    case instructionsLoaded(InstructionsLoadedHookOutput)
    case cwdChanged(CwdChangedHookOutput)
    case fileChanged(FileChangedHookOutput)
    case worktreeCreate(WorktreeCreateHookOutput)
}

/// Matches CC's PreToolUse hookSpecificOutput.
public struct PreToolUseHookOutput: Sendable {
    public let hookEventName = "PreToolUse"
    public let permissionDecision: PermissionBehavior?
    public let permissionDecisionReason: String?
    public let updatedInput: [String: JSONValue]?
    public let additionalContext: String?

    public init(
        permissionDecision: PermissionBehavior? = nil,
        permissionDecisionReason: String? = nil,
        updatedInput: [String: JSONValue]? = nil,
        additionalContext: String? = nil
    ) {
        self.permissionDecision = permissionDecision
        self.permissionDecisionReason = permissionDecisionReason
        self.updatedInput = updatedInput
        self.additionalContext = additionalContext
    }
}

/// Matches CC's UserPromptSubmit hookSpecificOutput.
public struct UserPromptSubmitHookOutput: Sendable {
    public let hookEventName = "UserPromptSubmit"
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Matches CC's SessionStart hookSpecificOutput.
public struct SessionStartHookOutput: Sendable {
    public let hookEventName = "SessionStart"
    public let additionalContext: String?
    public let initialUserMessage: String?
    public let watchPaths: [String]?

    public init(
        additionalContext: String? = nil,
        initialUserMessage: String? = nil,
        watchPaths: [String]? = nil
    ) {
        self.additionalContext = additionalContext
        self.initialUserMessage = initialUserMessage
        self.watchPaths = watchPaths
    }
}

/// Matches CC's Setup hookSpecificOutput.
public struct SetupHookOutput: Sendable {
    public let hookEventName = "Setup"
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Matches CC's SubagentStart hookSpecificOutput.
public struct SubagentStartHookOutput: Sendable {
    public let hookEventName = "SubagentStart"
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Matches CC's PostToolUse hookSpecificOutput.
public struct PostToolUseHookOutput: Sendable {
    public let hookEventName = "PostToolUse"
    public let additionalContext: String?
    public let updatedMCPToolOutput: JSONValue?

    public init(
        additionalContext: String? = nil,
        updatedMCPToolOutput: JSONValue? = nil
    ) {
        self.additionalContext = additionalContext
        self.updatedMCPToolOutput = updatedMCPToolOutput
    }
}

/// Matches CC's PostToolUseFailure hookSpecificOutput.
public struct PostToolUseFailureHookOutput: Sendable {
    public let hookEventName = "PostToolUseFailure"
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Matches CC's PermissionDenied hookSpecificOutput.
public struct PermissionDeniedHookOutput: Sendable {
    public let hookEventName = "PermissionDenied"
    public let retry: Bool?

    public init(retry: Bool? = nil) {
        self.retry = retry
    }
}

/// Matches CC's Notification hookSpecificOutput.
public struct NotificationHookOutput: Sendable {
    public let hookEventName = "Notification"
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Matches CC's PermissionRequest hookSpecificOutput.
public struct PermissionRequestHookOutput: Sendable {
    public let hookEventName = "PermissionRequest"
    public let decision: PermissionRequestDecision?

    public init(decision: PermissionRequestDecision? = nil) {
        self.decision = decision
    }
}

/// Discriminated union for PermissionRequest hook decision.
/// Matches CC: { behavior: 'allow', updatedInput?, updatedPermissions? } | { behavior: 'deny', message?, interrupt? }
public enum PermissionRequestDecision: Sendable {
    case allow(updatedInput: [String: JSONValue]? = nil, updatedPermissions: [PermissionUpdate]? = nil)
    case deny(message: String? = nil, interrupt: Bool? = nil)
}

/// Matches CC's Elicitation hookSpecificOutput.
public struct ElicitationHookOutput: Sendable {
    public let hookEventName = "Elicitation"
    public let action: ElicitationAction?
    public let content: [String: JSONValue]?

    public init(
        action: ElicitationAction? = nil,
        content: [String: JSONValue]? = nil
    ) {
        self.action = action
        self.content = content
    }
}

/// Matches CC's ElicitationResult hookSpecificOutput.
public struct ElicitationResultHookOutput: Sendable {
    public let hookEventName = "ElicitationResult"
    public let action: ElicitationAction?
    public let content: [String: JSONValue]?

    public init(
        action: ElicitationAction? = nil,
        content: [String: JSONValue]? = nil
    ) {
        self.action = action
        self.content = content
    }
}

public enum ElicitationAction: String, Sendable {
    case accept
    case decline
    case cancel
}

/// Matches CC's CwdChanged hookSpecificOutput.
public struct CwdChangedHookOutput: Sendable {
    public let hookEventName = "CwdChanged"
    public let watchPaths: [String]?

    public init(watchPaths: [String]? = nil) {
        self.watchPaths = watchPaths
    }
}

/// Matches CC's FileChanged hookSpecificOutput.
public struct FileChangedHookOutput: Sendable {
    public let hookEventName = "FileChanged"
    public let watchPaths: [String]?

    public init(watchPaths: [String]? = nil) {
        self.watchPaths = watchPaths
    }
}

/// Matches CC's InstructionsLoaded hookSpecificOutput.
public struct InstructionsLoadedHookOutput: Sendable {
    public let hookEventName = "InstructionsLoaded"
    public let filePath: String
    public let memoryType: String
    public let loadReason: String

    public init(filePath: String, memoryType: String, loadReason: String) {
        self.filePath = filePath
        self.memoryType = memoryType
        self.loadReason = loadReason
    }
}

/// Matches CC's WorktreeCreate hookSpecificOutput.
public struct WorktreeCreateHookOutput: Sendable {
    public let hookEventName = "WorktreeCreate"
    public let worktreePath: String

    public init(worktreePath: String) {
        self.worktreePath = worktreePath
    }
}

// MARK: - Hook Input (27 event-specific schemas)

/// Base fields present in every hook input.
/// Matches CC's BaseHookInput: session_id, transcript_path, cwd, permission_mode?, agent_id?, agent_type?.
public struct BaseHookInput: Sendable, Codable {
    public let sessionId: String
    public let transcriptPath: String
    public let cwd: String
    public let permissionMode: String?
    public let agentId: String?
    public let agentType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case agentId = "agent_id"
        case agentType = "agent_type"
    }

    public init(
        sessionId: String,
        transcriptPath: String,
        cwd: String,
        permissionMode: String? = nil,
        agentId: String? = nil,
        agentType: String? = nil
    ) {
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.agentId = agentId
        self.agentType = agentType
    }
}

/// Matches CC's PreToolUseHookInput.
public struct PreToolUseHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PreToolUse"
    public let toolName: String
    public let toolInput: JSONValue
    public let toolUseID: String
}

/// Matches CC's PostToolUseHookInput.
public struct PostToolUseHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PostToolUse"
    public let toolName: String
    public let toolInput: JSONValue
    public let toolResponse: JSONValue
    public let toolUseID: String
}

/// Matches CC's PostToolUseFailureHookInput.
public struct PostToolUseFailureHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PostToolUseFailure"
    public let toolName: String
    public let toolInput: JSONValue
    public let toolUseID: String
    public let error: String
    public let isInterrupt: Bool?
}

/// Matches CC's PermissionDeniedHookInput.
public struct PermissionDeniedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PermissionDenied"
    public let toolName: String
    public let toolInput: JSONValue
    public let toolUseID: String
    public let reason: String
}

/// Matches CC's NotificationHookInput.
public struct NotificationHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "Notification"
    public let message: String
    public let title: String?
    public let notificationType: String
}

/// Matches CC's UserPromptSubmitHookInput.
public struct UserPromptSubmitHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "UserPromptSubmit"
    public let prompt: String
}

/// Matches CC's SessionStartHookInput.
public struct SessionStartHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "SessionStart"
    public let source: SessionStartSource
    public let model: String?
}

public enum SessionStartSource: String, Sendable {
    case startup
    case resume
    case clear
    case compact
}

/// Matches CC's SessionEndHookInput.
public struct SessionEndHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "SessionEnd"
    public let reason: SessionEndReason
}

public enum SessionEndReason: String, Sendable {
    case clear
    case resume
    case logout
    case promptInputExit = "prompt_input_exit"
    case other
    case bypassPermissionsDisabled = "bypass_permissions_disabled"
}

/// Matches CC's StopHookInput.
public struct StopHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "Stop"
    public let stopHookActive: Bool
    public let lastAssistantMessage: String?
}

/// Matches CC's StopFailureHookInput.
public struct StopFailureHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "StopFailure"
    public let error: JSONValue
    public let errorDetails: String?
    public let lastAssistantMessage: String?
}

/// Matches CC's SubagentStartHookInput.
public struct SubagentStartHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "SubagentStart"
    public let agentId: String
    public let agentType: String
}

/// Matches CC's SubagentStopHookInput.
public struct SubagentStopHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "SubagentStop"
    public let stopHookActive: Bool
    public let agentId: String
    public let agentTranscriptPath: String
    public let agentType: String
    public let lastAssistantMessage: String?
}

/// Matches CC's PreCompactHookInput.
public struct PreCompactHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PreCompact"
    public let trigger: CompactTrigger
    public let customInstructions: String?
}

public enum CompactTrigger: String, Codable, Sendable {
    case manual
    case auto
}

/// Matches CC's PostCompactHookInput.
public struct PostCompactHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PostCompact"
    public let trigger: CompactTrigger
    public let compactSummary: String
}

/// Matches CC's PermissionRequestHookInput.
public struct PermissionRequestHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "PermissionRequest"
    public let toolName: String
    public let toolInput: JSONValue
    public let permissionSuggestions: [PermissionUpdate]?
}

/// Matches CC's SetupHookInput.
public struct SetupHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "Setup"
    public let trigger: SetupTrigger
}

public enum SetupTrigger: String, Sendable {
    case `init`
    case maintenance
}

/// Matches CC's TeammateIdleHookInput.
public struct TeammateIdleHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "TeammateIdle"
    public let teammateName: String
    public let teamName: String
}

/// Matches CC's TaskCreatedHookInput.
public struct TaskCreatedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "TaskCreated"
    public let taskID: String
    public let taskSubject: String
    public let taskDescription: String?
    public let teammateName: String?
    public let teamName: String?
}

/// Matches CC's TaskCompletedHookInput.
public struct TaskCompletedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "TaskCompleted"
    public let taskID: String
    public let taskSubject: String
    public let taskDescription: String?
    public let teammateName: String?
    public let teamName: String?
}

/// Matches CC's ElicitationHookInput.
public struct ElicitationHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "Elicitation"
    public let mcpServerName: String
    public let message: String
    public let mode: ElicitationMode?
    public let url: String?
    public let elicitationID: String?
    public let requestedSchema: [String: JSONValue]?
}

public enum ElicitationMode: String, Sendable {
    case form
    case url
}

/// Matches CC's ElicitationResultHookInput.
public struct ElicitationResultHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "ElicitationResult"
    public let mcpServerName: String
    public let elicitationID: String?
    public let mode: ElicitationMode?
    public let action: ElicitationAction
    public let content: [String: JSONValue]?
}

/// Matches CC's ConfigChangeHookInput.
public struct ConfigChangeHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "ConfigChange"
    public let source: ConfigChangeSource
    public let filePath: String?
}

public enum ConfigChangeSource: String, Sendable {
    case userSettings = "user_settings"
    case projectSettings = "project_settings"
    case localSettings = "local_settings"
    case policySettings = "policy_settings"
    case skills
}

/// Matches CC's InstructionsLoadedHookInput.
public struct InstructionsLoadedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "InstructionsLoaded"
    public let filePath: String
    public let memoryType: InstructionsMemoryType
    public let loadReason: InstructionsLoadReason
    public let globs: [String]?
    public let triggerFilePath: String?
    public let parentFilePath: String?
}

public enum InstructionsMemoryType: String, Sendable {
    case user = "User"
    case project = "Project"
    case local = "Local"
    case managed = "Managed"
}

public enum InstructionsLoadReason: String, Sendable {
    case sessionStart = "session_start"
    case nestedTraversal = "nested_traversal"
    case pathGlobMatch = "path_glob_match"
    case include
    case compact
}

/// Matches CC's WorktreeCreateHookInput.
public struct WorktreeCreateHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "WorktreeCreate"
    public let name: String
}

/// Matches CC's WorktreeRemoveHookInput.
public struct WorktreeRemoveHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "WorktreeRemove"
    public let worktreePath: String
}

/// Matches CC's CwdChangedHookInput.
public struct CwdChangedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "CwdChanged"
    public let oldCwd: String
    public let newCwd: String
}

/// Matches CC's FileChangedHookInput.
public struct FileChangedHookInput: Sendable {
    public let base: BaseHookInput
    public let hookEventName = "FileChanged"
    public let filePath: String
    public let event: FileChangeEvent
}

public enum FileChangeEvent: String, Sendable {
    case change
    case add
    case unlink
}

// MARK: - Hook Result (execution outcome)

/// Full result of executing a hook.
/// Matches CC's HookResult interface (16 fields).
public struct HookExecutionResult: Sendable {
    public let message: Message?
    public let systemMessage: Message?
    public let blockingError: HookBlockingError?
    public let outcome: HookOutcome
    public let preventContinuation: Bool
    public let stopReason: String?
    public let permissionBehavior: PermissionResultBehavior?
    public let hookPermissionDecisionReason: String?
    public let additionalContext: String?
    public let initialUserMessage: String?
    public let updatedInput: [String: JSONValue]?
    public let updatedMCPToolOutput: JSONValue?
    public let permissionRequestResult: CCHookPermissionRequestResult?
    public let retry: Bool?

    public init(
        message: Message? = nil,
        systemMessage: Message? = nil,
        blockingError: HookBlockingError? = nil,
        outcome: HookOutcome = .success,
        preventContinuation: Bool = false,
        stopReason: String? = nil,
        permissionBehavior: PermissionResultBehavior? = nil,
        hookPermissionDecisionReason: String? = nil,
        additionalContext: String? = nil,
        initialUserMessage: String? = nil,
        updatedInput: [String: JSONValue]? = nil,
        updatedMCPToolOutput: JSONValue? = nil,
        permissionRequestResult: CCHookPermissionRequestResult? = nil,
        retry: Bool? = nil
    ) {
        self.message = message
        self.systemMessage = systemMessage
        self.blockingError = blockingError
        self.outcome = outcome
        self.preventContinuation = preventContinuation
        self.stopReason = stopReason
        self.permissionBehavior = permissionBehavior
        self.hookPermissionDecisionReason = hookPermissionDecisionReason
        self.additionalContext = additionalContext
        self.initialUserMessage = initialUserMessage
        self.updatedInput = updatedInput
        self.updatedMCPToolOutput = updatedMCPToolOutput
        self.permissionRequestResult = permissionRequestResult
        self.retry = retry
    }
}

/// Matches CC's HookResult.outcome: 'success' | 'blocking' | 'non_blocking_error' | 'cancelled'.
public enum HookOutcome: String, Sendable {
    case success
    case blocking
    case nonBlockingError = "non_blocking_error"
    case cancelled
}

/// Matches CC's HookBlockingError: { blockingError: string, command: string }.
public struct HookBlockingError: Sendable {
    public let blockingError: String
    public let command: String

    public init(blockingError: String, command: String) {
        self.blockingError = blockingError
        self.command = command
    }
}

/// Matches CC's PermissionRequestResult discriminated union.
/// { behavior: 'allow', updatedInput?, updatedPermissions? } | { behavior: 'deny', message?, interrupt? }.
public enum CCHookPermissionRequestResult: Sendable {
    case allow(updatedInput: [String: JSONValue]? = nil, updatedPermissions: [PermissionUpdate]? = nil)
    case deny(message: String? = nil, interrupt: Bool? = nil)
}

/// Matches CC's AggregatedHookResult.
public struct AggregatedHookResult: Sendable {
    public let message: Message?
    public let blockingErrors: [HookBlockingError]
    public let preventContinuation: Bool
    public let stopReason: String?
    public let hookPermissionDecisionReason: String?
    public let permissionBehavior: PermissionDecision?
    public let additionalContexts: [String]
    public let initialUserMessage: String?
    public let updatedInput: [String: JSONValue]?
    public let updatedMCPToolOutput: JSONValue?
    public let permissionRequestResult: CCHookPermissionRequestResult?
    public let retry: Bool?

    public init(
        message: Message? = nil,
        blockingErrors: [HookBlockingError] = [],
        preventContinuation: Bool = false,
        stopReason: String? = nil,
        hookPermissionDecisionReason: String? = nil,
        permissionBehavior: PermissionDecision? = nil,
        additionalContexts: [String] = [],
        initialUserMessage: String? = nil,
        updatedInput: [String: JSONValue]? = nil,
        updatedMCPToolOutput: JSONValue? = nil,
        permissionRequestResult: CCHookPermissionRequestResult? = nil,
        retry: Bool? = nil
    ) {
        self.message = message
        self.blockingErrors = blockingErrors
        self.preventContinuation = preventContinuation
        self.stopReason = stopReason
        self.hookPermissionDecisionReason = hookPermissionDecisionReason
        self.permissionBehavior = permissionBehavior
        self.additionalContexts = additionalContexts
        self.initialUserMessage = initialUserMessage
        self.updatedInput = updatedInput
        self.updatedMCPToolOutput = updatedMCPToolOutput
        self.permissionRequestResult = permissionRequestResult
        self.retry = retry
    }
}

// MARK: - Hook Progress

/// Progress update emitted during hook execution.
/// Matches CC's HookProgress: { type: 'hook_progress', hookEvent, hookName, command, promptText?, statusMessage? }.
public struct HookProgress: Sendable {
    public let type = "hook_progress"
    public let hookEvent: HookEvent
    public let hookName: String
    public let command: String
    public let promptText: String?
    public let statusMessage: String?

    public init(
        hookEvent: HookEvent,
        hookName: String,
        command: String,
        promptText: String? = nil,
        statusMessage: String? = nil
    ) {
        self.hookEvent = hookEvent
        self.hookName = hookName
        self.command = command
        self.promptText = promptText
        self.statusMessage = statusMessage
    }
}

// MARK: - Prompt Elicitation Protocol

/// Matches CC's PromptRequest: { prompt: string, message: string, options: { key, label, description? }[] }.
public struct PromptRequest: Sendable {
    public let prompt: String  // request id
    public let message: String
    public let options: [PromptRequestOption]

    public init(prompt: String, message: String, options: [PromptRequestOption] = []) {
        self.prompt = prompt
        self.message = message
        self.options = options
    }
}

public struct PromptRequestOption: Sendable {
    public let key: String
    public let label: String
    public let description: String?

    public init(key: String, label: String, description: String? = nil) {
        self.key = key
        self.label = label
        self.description = description
    }
}

/// Matches CC's PromptResponse: { prompt_response: string, selected: string }.
public struct PromptResponse: Sendable {
    public let promptResponse: String  // request id
    public let selected: String

    public init(promptResponse: String, selected: String) {
        self.promptResponse = promptResponse
        self.selected = selected
    }

    enum CodingKeys: String, CodingKey {
        case promptResponse = "prompt_response"
        case selected
    }
}

// MARK: - Hook Callback (6th hook type)

/// A hook that calls a Swift closure instead of spawning a process.
/// Matches CC's HookCallback: { type: 'callback', callback, timeout?, internal? }.
public struct HookCallback: Sendable {
    public let type = "callback"
    public let timeout: Int?
    public let isInternal: Bool

    public init(timeout: Int? = nil, isInternal: Bool = false) {
        self.timeout = timeout
        self.isInternal = isInternal
    }
}

/// Context passed to callback hooks for state access.
/// Matches CC's HookCallbackContext.
public struct HookCallbackContext: Sendable {
    public let getAppState: @Sendable () -> Any
    public let updateAttributionState: @Sendable (Any) -> Void

    public init(
        getAppState: @escaping @Sendable () -> Any,
        updateAttributionState: @escaping @Sendable (Any) -> Void
    ) {
        self.getAppState = getAppState
        self.updateAttributionState = updateAttributionState
    }
}

/// A matcher that selects which hooks to run based on pattern matching.
/// Matches CC's HookCallbackMatcher: { matcher?, hooks[], pluginName? }.
public struct HookCallbackMatcher: Sendable {
    public let matcher: String?
    public let hooks: [HookCallback]
    public let pluginName: String?

    public init(matcher: String? = nil, hooks: [HookCallback], pluginName: String? = nil) {
        self.matcher = matcher
        self.hooks = hooks
        self.pluginName = pluginName
    }
}

// MARK: - Hook JSON Output Parsing Bridge

/// Codable bridge type for parsing hook stdout JSON into structured fields.
/// Matches CC's parseHookJSONOutput — tries to decode the JSON object
/// and maps fields (continue, decision, reason, systemMessage, stopReason,
/// suppressOutput, hookSpecificOutput) to HookResult.
internal struct HookJSONOutputDecodable: Codable {
    var `continue`: Bool?
    var decision: String?
    var reason: String?
    var systemMessage: String?
    var stopReason: String?
    var suppressOutput: Bool?
    var async: Bool?
    var asyncTimeout: Int?
    var permissionDecision: String?
    var permissionDecisionReason: String?
    var updatedInput: [String: JSONValue]?
    var additionalContext: String?
    var hookSpecificOutput: [String: JSONValue]?

    /// Map parsed JSON fields to HookResult.
    /// Matches CC's hook result resolution logic in executeHooks.ts.
    func toHookResult(fallbackOutput: String, exitCode: Int32) -> HookResult {
        // Async response: hook continues in background
        if async == true {
            return .continue
        }

        // Decision-based: 'block' → blocking error, 'approve' → continue
        if let decision = decision {
            switch decision {
            case "block":
                let blockReason = reason ?? systemMessage ?? "Hook blocked continuation"
                return .blockingError(reason: blockReason)
            case "approve":
                // If there's updated input, return .modify
                if let updatedInput = updatedInput, let jsonData = try? JSONEncoder().encode(updatedInput),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    return .modify(input: jsonStr)
                }
                if let additionalContext = additionalContext {
                    return .modify(input: additionalContext)
                }
                return .continue
            default:
                break
            }
        }

        // Permission decision: allow/deny
        if let permDecision = permissionDecision {
            switch permDecision {
            case "deny":
                return .blockingError(reason: permissionDecisionReason ?? "Hook denied permission")
            case "allow":
                if let updatedInput = updatedInput, let jsonData = try? JSONEncoder().encode(updatedInput),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    return .modify(input: jsonStr)
                }
                return .continue
            default:
                break
            }
        }

        // Continue flag explicitly set
        if let shouldContinue = self.continue {
            if shouldContinue {
                if let updatedInput = updatedInput, let jsonData = try? JSONEncoder().encode(updatedInput),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    return .modify(input: jsonStr)
                }
                return .continue
            } else {
                let stopMsg = stopReason ?? reason ?? "Hook requested stop"
                return .stop(reason: stopMsg)
            }
        }

        // System message: inject into conversation
        if systemMessage != nil {
            return .continue
        }

        // Fallback: exit-code-based protocol
        switch exitCode {
        case 0:
            return .continue
        case 2:
            return .blockingError(reason: fallbackOutput.isEmpty ? "Hook blocked continuation" : fallbackOutput)
        default:
            return .nonBlockingError(message: fallbackOutput.isEmpty ? "Hook exited with code \(exitCode)" : fallbackOutput)
        }
    }
}
