import Foundation

// MARK: - SDK Fast Mode State

/// Fast mode toggle state reported in SDK init messages.
/// Matches CC's FastModeState: 'off' | 'cooldown' | 'on'.
public enum FastModeState: String, Codable, Sendable, CaseIterable {
    case off
    case cooldown
    case on
}

// MARK: - SDK API Key Source

/// Where the API key was sourced from.
/// Matches CC's ApiKeySource: 'user' | 'project' | 'org' | 'temporary' | 'oauth'.
public enum ApiKeySource: String, Codable, Sendable, CaseIterable {
    case user
    case project
    case org
    case temporary
    case oauth
}

// MARK: - SDK Assistant Message Error

/// Error type for assistant messages in the SDK protocol.
/// Matches CC's SDKAssistantMessageError.
public enum SDKAssistantMessageError: String, Codable, Sendable, CaseIterable {
    case authenticationFailed = "authentication_failed"
    case billingError = "billing_error"
    case rateLimit = "rate_limit"
    case invalidRequest = "invalid_request"
    case serverError = "server_error"
    case unknown = "unknown"
    case maxOutputTokens = "max_output_tokens"
}

// MARK: - SDK Rate Limit Info

/// Rate limit status from the API.
/// Matches CC's SDKRateLimitInfo in coreSchemas.ts.
public struct SDKRateLimitInfo: Codable, Sendable {
    public var status: String  // "allowed" | "allowed_warning" | "rejected"
    public var resetsAt: Double?
    public var rateLimitType: String?  // "five_hour" | "seven_day" | "seven_day_opus" | "seven_day_sonnet" | "overage"
    public var utilization: Double?
    public var overageStatus: String?
    public var overageResetsAt: Double?
    public var overageDisabledReason: String?
    public var isUsingOverage: Bool?
    public var surpassedThreshold: Double?

    public init(
        status: String,
        resetsAt: Double? = nil,
        rateLimitType: String? = nil,
        utilization: Double? = nil,
        overageStatus: String? = nil,
        overageResetsAt: Double? = nil,
        overageDisabledReason: String? = nil,
        isUsingOverage: Bool? = nil,
        surpassedThreshold: Double? = nil
    ) {
        self.status = status
        self.resetsAt = resetsAt
        self.rateLimitType = rateLimitType
        self.utilization = utilization
        self.overageStatus = overageStatus
        self.overageResetsAt = overageResetsAt
        self.overageDisabledReason = overageDisabledReason
        self.isUsingOverage = isUsingOverage
        self.surpassedThreshold = surpassedThreshold
    }
}

// MARK: - SDK Permission Denial

/// Recorded permission denial for SDK result messages.
/// Matches CC's SDKPermissionDenial in coreSchemas.ts.
public struct SDKPermissionDenial: Codable, Sendable {
    public var toolName: String
    public var toolUseID: String
    public var toolInput: [String: JSONValue]

    public init(toolName: String, toolUseID: String, toolInput: [String: JSONValue] = [:]) {
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.toolInput = toolInput
    }
}

// MARK: - SDK Session State

/// Session state for SDK status messages.
/// Matches CC's session state: 'idle' | 'running' | 'requires_action'.
public enum SDKSessionState: String, Codable, Sendable {
    case idle
    case running
    case requiresAction = "requires_action"
}

// MARK: - SDK Result Message

/// Successful SDK result message.
/// Matches CC's SDKResultSuccess in coreSchemas.ts.
public struct SDKResultSuccess: Codable, Sendable {
    public var type: String = "result"
    public var subtype: String = "success"
    public var durationMs: Double
    public var durationApiMs: Double
    public var isError: Bool = false
    public var numTurns: Int
    public var result: String
    public var stopReason: String?
    public var totalCostUsd: Double
    public var usage: Usage?
    public var modelUsage: [String: Usage]?
    public var permissionDenials: [SDKPermissionDenial]?
    public var structuredOutput: JSONValue?
    public var fastModeState: FastModeState?
    public var uuid: String
    public var sessionId: String

    public init(
        durationMs: Double = 0,
        durationApiMs: Double = 0,
        numTurns: Int = 0,
        result: String = "",
        stopReason: String? = nil,
        totalCostUsd: Double = 0,
        usage: Usage? = nil,
        modelUsage: [String: Usage]? = nil,
        permissionDenials: [SDKPermissionDenial]? = nil,
        structuredOutput: JSONValue? = nil,
        fastModeState: FastModeState? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.durationMs = durationMs
        self.durationApiMs = durationApiMs
        self.numTurns = numTurns
        self.result = result
        self.stopReason = stopReason
        self.totalCostUsd = totalCostUsd
        self.usage = usage
        self.modelUsage = modelUsage
        self.permissionDenials = permissionDenials
        self.structuredOutput = structuredOutput
        self.fastModeState = fastModeState
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// Error SDK result message.
/// Matches CC's SDKResultError in coreSchemas.ts.
public struct SDKResultError: Codable, Sendable {
    public var type: String = "result"
    /// Error subtype: 'error_during_execution' | 'error_max_turns' | 'error_max_budget_usd' | 'error_max_structured_output_retries'
    public var subtype: String
    public var durationMs: Double
    public var durationApiMs: Double
    public var isError: Bool = true
    public var numTurns: Int
    public var stopReason: String?
    public var totalCostUsd: Double
    public var usage: Usage?
    public var modelUsage: [String: Usage]?
    public var permissionDenials: [SDKPermissionDenial]?
    public var errors: [String]
    public var fastModeState: FastModeState?
    public var uuid: String
    public var sessionId: String

    public init(
        subtype: String,
        durationMs: Double = 0,
        durationApiMs: Double = 0,
        numTurns: Int = 0,
        stopReason: String? = nil,
        totalCostUsd: Double = 0,
        usage: Usage? = nil,
        modelUsage: [String: Usage]? = nil,
        permissionDenials: [SDKPermissionDenial]? = nil,
        errors: [String] = [],
        fastModeState: FastModeState? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.subtype = subtype
        self.durationMs = durationMs
        self.durationApiMs = durationApiMs
        self.numTurns = numTurns
        self.stopReason = stopReason
        self.totalCostUsd = totalCostUsd
        self.usage = usage
        self.modelUsage = modelUsage
        self.permissionDenials = permissionDenials
        self.errors = errors
        self.fastModeState = fastModeState
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK System Init Message

/// SDK system init message — sent on session start.
/// Matches CC's SDKSystemInitMessage in coreSchemas.ts.
public struct SDKSystemInit: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "init"
    public var agents: [String]?
    public var apiKeySource: String?
    public var betas: [String]?
    public var claudeCodeVersion: String
    public var cwd: String
    public var tools: [String]
    public var mcpServers: [SDKMCPServerStatus]?
    public var model: String
    public var permissionMode: String
    public var slashCommands: [String]?
    public var outputStyle: String?
    public var skills: [String]?
    public var plugins: [SDKPluginInfo]?
    public var fastModeState: FastModeState?
    public var uuid: String
    public var sessionId: String

    public init(
        agents: [String]? = nil,
        apiKeySource: String? = nil,
        betas: [String]? = nil,
        claudeCodeVersion: String = "",
        cwd: String = "",
        tools: [String] = [],
        mcpServers: [SDKMCPServerStatus]? = nil,
        model: String = "",
        permissionMode: String = "",
        slashCommands: [String]? = nil,
        outputStyle: String? = nil,
        skills: [String]? = nil,
        plugins: [SDKPluginInfo]? = nil,
        fastModeState: FastModeState? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.agents = agents
        self.apiKeySource = apiKeySource
        self.betas = betas
        self.claudeCodeVersion = claudeCodeVersion
        self.cwd = cwd
        self.tools = tools
        self.mcpServers = mcpServers
        self.model = model
        self.permissionMode = permissionMode
        self.slashCommands = slashCommands
        self.outputStyle = outputStyle
        self.skills = skills
        self.plugins = plugins
        self.fastModeState = fastModeState
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// MCP server status in SDK init message.
public struct SDKMCPServerStatus: Codable, Sendable {
    public var name: String
    public var status: String

    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }
}

/// Plugin info in SDK init message.
public struct SDKPluginInfo: Codable, Sendable {
    public var name: String
    public var path: String
    public var source: String?

    public init(name: String, path: String, source: String? = nil) {
        self.name = name
        self.path = path
        self.source = source
    }
}

// MARK: - SDK Compact Boundary

/// SDK compact boundary system message.
/// Matches CC's SDKCompactBoundaryMessage in coreSchemas.ts.
public struct SDKCompactBoundary: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "compact_boundary"
    public var compactMetadata: SDKCompactBoundaryMetadata
    public var uuid: String
    public var sessionId: String

    public init(compactMetadata: SDKCompactBoundaryMetadata, uuid: String = "", sessionId: String = "") {
        self.compactMetadata = compactMetadata
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// Metadata within compact boundary messages.
public struct SDKCompactBoundaryMetadata: Codable, Sendable {
    public var trigger: String  // "manual" | "auto"
    public var preTokens: Int
    public var preservedSegment: SDKPreservedSegment?

    public init(trigger: String, preTokens: Int, preservedSegment: SDKPreservedSegment? = nil) {
        self.trigger = trigger
        self.preTokens = preTokens
        self.preservedSegment = preservedSegment
    }
}

/// Preserved segment in compact boundary metadata.
public struct SDKPreservedSegment: Codable, Sendable {
    public var headUuid: String
    public var anchorUuid: String
    public var tailUuid: String

    public init(headUuid: String, anchorUuid: String, tailUuid: String) {
        self.headUuid = headUuid
        self.anchorUuid = anchorUuid
        self.tailUuid = tailUuid
    }
}

// MARK: - SDK Status Message

/// SDK status system message (compacting, permission mode changes).
/// Matches CC's SDKStatusMessage in coreSchemas.ts.
public struct SDKStatusMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "status"
    public var status: String?  // "compacting" | nil
    public var permissionMode: String?
    public var uuid: String
    public var sessionId: String

    public init(
        status: String? = nil,
        permissionMode: String? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.status = status
        self.permissionMode = permissionMode
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK API Retry Message

/// API retry system message sent on retryable errors.
/// Matches CC's SDKAPIRetryMessage in coreSchemas.ts.
public struct SDKAPIRetryMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "api_retry"
    public var attempt: Int
    public var maxRetries: Int
    public var retryDelayMs: Int
    public var errorStatus: Int?
    public var error: String  // SDKAssistantMessageError value
    public var uuid: String
    public var sessionId: String

    public init(
        attempt: Int = 0,
        maxRetries: Int = 0,
        retryDelayMs: Int = 0,
        errorStatus: Int? = nil,
        error: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.attempt = attempt
        self.maxRetries = maxRetries
        self.retryDelayMs = retryDelayMs
        self.errorStatus = errorStatus
        self.error = error
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Hook Messages

/// SDK hook started system message.
/// Matches CC's SDKHookStartedMessage in coreSchemas.ts.
public struct SDKHookStartedMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "hook_started"
    public var hookId: String
    public var hookName: String
    public var hookEvent: String
    public var uuid: String
    public var sessionId: String

    public init(
        hookId: String = "",
        hookName: String = "",
        hookEvent: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.hookId = hookId
        self.hookName = hookName
        self.hookEvent = hookEvent
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// SDK hook progress system message.
/// Matches CC's SDKHookProgressMessage in coreSchemas.ts.
public struct SDKHookProgressMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "hook_progress"
    public var hookId: String
    public var hookName: String
    public var hookEvent: String
    public var stdout: String
    public var stderr: String
    public var output: String
    public var uuid: String
    public var sessionId: String

    public init(
        hookId: String = "",
        hookName: String = "",
        hookEvent: String = "",
        stdout: String = "",
        stderr: String = "",
        output: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.hookId = hookId
        self.hookName = hookName
        self.hookEvent = hookEvent
        self.stdout = stdout
        self.stderr = stderr
        self.output = output
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// SDK hook response system message.
/// Matches CC's SDKHookResponseMessage in coreSchemas.ts.
public struct SDKHookResponseMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "hook_response"
    public var hookId: String
    public var hookName: String
    public var hookEvent: String
    public var output: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int?
    public var outcome: String  // "success" | "error" | "cancelled"
    public var uuid: String
    public var sessionId: String

    public init(
        hookId: String = "",
        hookName: String = "",
        hookEvent: String = "",
        output: String = "",
        stdout: String = "",
        stderr: String = "",
        exitCode: Int? = nil,
        outcome: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.hookId = hookId
        self.hookName = hookName
        self.hookEvent = hookEvent
        self.output = output
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.outcome = outcome
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Task Messages

/// SDK task notification system message.
/// Matches CC's SDKTaskNotificationMessage in coreSchemas.ts.
public struct SDKTaskNotificationMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "task_notification"
    public var taskId: String
    public var toolUseID: String?
    public var status: String  // "completed" | "failed" | "stopped"
    public var outputFile: String
    public var summary: String
    public var usage: SDKTaskUsage?
    public var uuid: String
    public var sessionId: String

    public init(
        taskId: String = "",
        toolUseID: String? = nil,
        status: String = "",
        outputFile: String = "",
        summary: String = "",
        usage: SDKTaskUsage? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.taskId = taskId
        self.toolUseID = toolUseID
        self.status = status
        self.outputFile = outputFile
        self.summary = summary
        self.usage = usage
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// Token usage for SDK task messages.
public struct SDKTaskUsage: Codable, Sendable {
    public var totalTokens: Int
    public var toolUses: Int
    public var durationMs: Int

    public init(totalTokens: Int = 0, toolUses: Int = 0, durationMs: Int = 0) {
        self.totalTokens = totalTokens
        self.toolUses = toolUses
        self.durationMs = durationMs
    }
}

/// SDK task started system message.
/// Matches CC's SDKTaskStartedMessage in coreSchemas.ts.
public struct SDKTaskStartedMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "task_started"
    public var taskId: String
    public var toolUseID: String?
    public var description: String
    public var taskType: String?
    public var workflowName: String?
    public var prompt: String?
    public var uuid: String
    public var sessionId: String

    public init(
        taskId: String = "",
        toolUseID: String? = nil,
        description: String = "",
        taskType: String? = nil,
        workflowName: String? = nil,
        prompt: String? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.taskId = taskId
        self.toolUseID = toolUseID
        self.description = description
        self.taskType = taskType
        self.workflowName = workflowName
        self.prompt = prompt
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

/// SDK task progress system message.
/// Matches CC's SDKTaskProgressMessage in coreSchemas.ts.
public struct SDKTaskProgressMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "task_progress"
    public var taskId: String
    public var toolUseID: String?
    public var description: String
    public var usage: SDKTaskUsage?
    public var lastToolName: String?
    public var summary: String?
    public var uuid: String
    public var sessionId: String

    public init(
        taskId: String = "",
        toolUseID: String? = nil,
        description: String = "",
        usage: SDKTaskUsage? = nil,
        lastToolName: String? = nil,
        summary: String? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.taskId = taskId
        self.toolUseID = toolUseID
        self.description = description
        self.usage = usage
        self.lastToolName = lastToolName
        self.summary = summary
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Session State Changed

/// SDK session state changed system message.
/// Matches CC's SDKSessionStateChangedMessage in coreSchemas.ts.
public struct SDKSessionStateChangedMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "session_state_changed"
    public var state: String  // "idle" | "running" | "requires_action"
    public var uuid: String
    public var sessionId: String

    public init(state: String = "", uuid: String = "", sessionId: String = "") {
        self.state = state
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Tool Progress

/// SDK tool progress message.
/// Matches CC's SDKToolProgressMessage in coreSchemas.ts.
public struct SDKToolProgressMessage: Codable, Sendable {
    public var type: String = "tool_progress"
    public var toolUseID: String
    public var toolName: String
    public var parentToolUseID: String?
    public var elapsedTimeSeconds: Double
    public var taskId: String?
    public var uuid: String
    public var sessionId: String

    public init(
        toolUseID: String = "",
        toolName: String = "",
        parentToolUseID: String? = nil,
        elapsedTimeSeconds: Double = 0,
        taskId: String? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.parentToolUseID = parentToolUseID
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.taskId = taskId
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Auth Status

/// SDK auth status message (OAuth flow).
/// Matches CC's SDKAuthStatusMessage in coreSchemas.ts.
public struct SDKAuthStatusMessage: Codable, Sendable {
    public var type: String = "auth_status"
    public var isAuthenticating: Bool
    public var output: [String]
    public var error: String?
    public var uuid: String
    public var sessionId: String

    public init(
        isAuthenticating: Bool = false,
        output: [String] = [],
        error: String? = nil,
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.isAuthenticating = isAuthenticating
        self.output = output
        self.error = error
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Files Persisted

/// SDK files persisted event message.
/// Matches CC's SDKFilesPersistedEvent in coreSchemas.ts.
public struct SDKFilesPersistedEvent: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "files_persisted"
    public var files: [SDKPersistedFile]
    public var failed: [SDKPersistedFileFailure]
    public var processedAt: String
    public var uuid: String
    public var sessionId: String

    public init(
        files: [SDKPersistedFile] = [],
        failed: [SDKPersistedFileFailure] = [],
        processedAt: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.files = files
        self.failed = failed
        self.processedAt = processedAt
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

public struct SDKPersistedFile: Codable, Sendable {
    public var filename: String
    public var fileId: String

    public init(filename: String, fileId: String) {
        self.filename = filename
        self.fileId = fileId
    }
}

public struct SDKPersistedFileFailure: Codable, Sendable {
    public var filename: String
    public var error: String

    public init(filename: String, error: String) {
        self.filename = filename
        self.error = error
    }
}

// MARK: - SDK Tool Use Summary

/// SDK tool use summary message (collapsed tool results).
/// Matches CC's SDKToolUseSummaryMessage in coreSchemas.ts.
public struct SDKToolUseSummaryMessage: Codable, Sendable {
    public var type: String = "tool_use_summary"
    public var summary: String
    public var precedingToolUseIDs: [String]
    public var uuid: String
    public var sessionId: String

    public init(
        summary: String = "",
        precedingToolUseIDs: [String] = [],
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.summary = summary
        self.precedingToolUseIDs = precedingToolUseIDs
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Rate Limit Event

/// SDK rate limit event message.
/// Matches CC's SDKRateLimitEvent in coreSchemas.ts.
public struct SDKRateLimitEvent: Codable, Sendable {
    public var type: String = "rate_limit_event"
    public var rateLimitInfo: SDKRateLimitInfo
    public var uuid: String
    public var sessionId: String

    public init(rateLimitInfo: SDKRateLimitInfo, uuid: String = "", sessionId: String = "") {
        self.rateLimitInfo = rateLimitInfo
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Streamlined Messages

/// SDK streamlined text message (condensed user display).
/// Matches CC's SDKStreamlinedTextMessage in coreSchemas.ts.
public struct SDKStreamlinedTextMessage: Codable, Sendable {
    public var type: String = "streamlined_text"
    public var text: String
    public var sessionId: String
    public var uuid: String

    public init(text: String = "", sessionId: String = "", uuid: String = "") {
        self.text = text
        self.sessionId = sessionId
        self.uuid = uuid
    }
}

/// SDK streamlined tool use summary message.
/// Matches CC's SDKStreamlinedToolUseSummaryMessage in coreSchemas.ts.
public struct SDKStreamlinedToolUseSummaryMessage: Codable, Sendable {
    public var type: String = "streamlined_tool_use_summary"
    public var toolSummary: String
    public var sessionId: String
    public var uuid: String

    public init(toolSummary: String = "", sessionId: String = "", uuid: String = "") {
        self.toolSummary = toolSummary
        self.sessionId = sessionId
        self.uuid = uuid
    }
}

// MARK: - SDK Prompt Suggestion

/// SDK prompt suggestion message (auto-complete suggestions).
/// Matches CC's SDKPromptSuggestionMessage in coreSchemas.ts.
public struct SDKPromptSuggestionMessage: Codable, Sendable {
    public var type: String = "prompt_suggestion"
    public var suggestion: String
    public var uuid: String
    public var sessionId: String

    public init(suggestion: String = "", uuid: String = "", sessionId: String = "") {
        self.suggestion = suggestion
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Post Turn Summary

/// SDK post-turn summary system message (workflow progress).
/// Matches CC's SDKPostTurnSummaryMessage in coreSchemas.ts.
public struct SDKPostTurnSummaryMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "post_turn_summary"
    public var summarizesUuid: String
    public var statusCategory: String  // "blocked" | "waiting" | "completed" | "review_ready" | "failed"
    public var statusDetail: String
    public var isNoteworthy: Bool
    public var title: String
    public var description: String
    public var recentAction: String
    public var needsAction: String
    public var artifactUrls: [String]
    public var uuid: String
    public var sessionId: String

    public init(
        summarizesUuid: String = "",
        statusCategory: String = "",
        statusDetail: String = "",
        isNoteworthy: Bool = false,
        title: String = "",
        description: String = "",
        recentAction: String = "",
        needsAction: String = "",
        artifactUrls: [String] = [],
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.summarizesUuid = summarizesUuid
        self.statusCategory = statusCategory
        self.statusDetail = statusDetail
        self.isNoteworthy = isNoteworthy
        self.title = title
        self.description = description
        self.recentAction = recentAction
        self.needsAction = needsAction
        self.artifactUrls = artifactUrls
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Local Command Output

/// SDK local command output system message.
/// Matches CC's SDKLocalCommandOutputMessage in coreSchemas.ts.
public struct SDKLocalCommandOutputMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "local_command_output"
    public var content: String
    public var uuid: String
    public var sessionId: String

    public init(content: String = "", uuid: String = "", sessionId: String = "") {
        self.content = content
        self.uuid = uuid
        self.sessionId = sessionId
    }
}

// MARK: - SDK Elicitation Complete

/// SDK elicitation complete system message (MCP form/URL elicitation done).
/// Matches CC's SDKElicitationCompleteMessage in coreSchemas.ts.
public struct SDKElicitationCompleteMessage: Codable, Sendable {
    public var type: String = "system"
    public var subtype: String = "elicitation_complete"
    public var mcpServerName: String
    public var elicitationId: String
    public var uuid: String
    public var sessionId: String

    public init(
        mcpServerName: String = "",
        elicitationId: String = "",
        uuid: String = "",
        sessionId: String = ""
    ) {
        self.mcpServerName = mcpServerName
        self.elicitationId = elicitationId
        self.uuid = uuid
        self.sessionId = sessionId
    }
}
