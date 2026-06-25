import Foundation

// MARK: - Tool Callback Types

/// Permission-check callback passed to tool execution.
/// Matches Claude Code's CanUseToolFn — enables tools to check permissions
/// for sub-operations (e.g., Bash sub-commands) during execution.
///
/// CC signature: (tool, input, toolUseContext, assistantMessage, toolUseID, forceDecision?) => Promise<PermissionDecision>
public typealias CanUseToolFn = @Sendable (
    _ tool: any Tool,
    _ input: [String: JSONValue],
    _ toolUseContext: ToolUseContext,
    _ assistantMessage: Message,
    _ toolUseID: String,
    _ forceDecision: PermissionResult?
) async -> PermissionResult

/// Progress data emitted during tool execution.
/// Matches Claude Code's ToolProgressData.
public protocol ToolProgressData: Sendable {
    var type: String { get }
}

/// A progress event for a specific tool call, pairing data with the tool use ID.
/// Matches Claude Code's ToolProgress<P>.
public struct ToolProgress: Sendable {
    public let toolUseID: String
    public let data: any ToolProgressData

    public init(toolUseID: String, data: any ToolProgressData) {
        self.toolUseID = toolUseID
        self.data = data
    }
}

/// Progress stream continuation for tool call progress.
/// Matches Claude Code's ToolCallProgress<P>.
public typealias ToolCallProgress = @Sendable (ToolProgress) -> Void

// MARK: - Tool Protocol

/// Tool protocol — the core contract every tool must fulfill.
/// Mirrors Claude Code's `buildTool()` builder pattern and Tool type.
public protocol Tool: Sendable {
    /// The tool name as seen by the LLM (e.g. "Bash", "Read").
    var name: String { get }

    /// Human-readable description of what the tool does.
    /// Input-dependent — may vary based on the tool's input parameters.
    /// Matches Claude Code's `description(input, options)`.
    func description(
        input: [String: JSONValue],
        options: ToolDescriptionOptions
    ) async -> String

    /// JSON Schema for the tool's input parameters.
    var inputSchema: JSONSchema { get }

    /// Whether this tool is read-only (safe for auto-approval).
    var isReadOnly: Bool { get }

    /// Whether this tool is safe to run concurrently.
    var isConcurrencySafe: Bool { get }

    /// Optional aliases for backwards compatibility when a tool is renamed.
    var aliases: [String] { get }

    /// One-line capability phrase used by ToolSearch for keyword matching.
    /// 3–10 words, no trailing period. Prefer terms not already in the tool name.
    var searchHint: String? { get }

    /// Whether this tool is an MCP server tool.
    var isMcp: Bool { get }

    /// Whether this tool is an LSP tool.
    var isLsp: Bool { get }

    /// When true, this tool is deferred (requires ToolSearch before use).
    var shouldDefer: Bool { get }

    /// When true, this tool is never deferred — always loaded in initial prompt.
    var alwaysLoad: Bool { get }

    /// Maximum result size in characters before persisting to disk.
    var maxResultSizeChars: Int { get }

    /// MCP server/tool names for MCP tools.
    var mcpInfo: MCPToolInfo? { get }

    /// Execute the tool with the given input and context.
    /// Matches Claude Code's call(args, context, canUseTool, parentMessage, onProgress).
    /// - Parameters:
    ///   - input: Tool input arguments as a dictionary.
    ///   - context: Execution context (permission mode, working dir, session, etc.).
    ///   - canUseTool: Callback for sub-operation permission checks during execution.
    ///   - parentMessage: The parent assistant message that triggered this tool call.
    ///   - onProgress: Optional progress stream for streaming progress updates.
    func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn?,
        parentMessage: Message?,
        onProgress: ToolCallProgress?
    ) async throws -> ToolResult

    /// Generate system prompt content for this tool.
    /// Matches Claude Code's prompt() method — produces per-tool documentation
    /// text injected into the system prompt for the LLM.
    /// CC signature: prompt({ getToolPermissionContext, tools, agents, allowedAgentTypes }): Promise<string>
    func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String

    /// Tool-specific permission check. Called after validateInput() passes.
    func checkPermissions(input: [String: JSONValue], context: ToolUseContext) async -> PermissionResult

    /// Validate input before permission check and execution.
    /// Returns .success or a failure with message and errorCode.
    func validateInput(_ input: [String: JSONValue], context: ToolUseContext) async -> ValidationResult

    /// Whether this tool is destructive (performs irreversible operations).
    func isDestructive(_ input: [String: JSONValue]) -> Bool

    /// Whether this tool is currently enabled (may depend on env/feature flags).
    func isEnabled() -> Bool

    /// Extract a file path from the input, if applicable (for path-based rules).
    func getPath(_ input: [String: JSONValue]) -> String?

    /// User-facing display name for UI (may depend on input).
    func userFacingName(_ input: [String: JSONValue]) -> String

    /// Compact representation for auto-mode security classifier.
    /// CC: returns unknown (string or object). Defaults to "" (skip in classifier).
    func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any

    /// Map tool result to API ToolResultBlockParam format.
    func mapToolResultToToolResultBlockParam(_ content: ToolResult, toolUseID: String) -> ToolResultBlockParam

    // MARK: - Optional Protocol Members (matching Claude Code)

    /// Whether this tool is read-only given the input (input-dependent override).
    /// Default: returns the isReadOnly property.
    func isReadOnly(_ input: [String: JSONValue]) -> Bool

    /// Whether this tool is concurrency-safe given the input (input-dependent override).
    /// Default: returns the isConcurrencySafe property.
    func isConcurrencySafe(_ input: [String: JSONValue]) -> Bool

    /// What happens when the user submits a new message while this tool is running.
    /// .cancel — stop the tool and discard result. .block — keep running, new message waits.
    func interruptBehavior() -> InterruptBehavior

    /// Whether this tool has side effects beyond known schemas (e.g. network calls).
    func isOpenWorld(_ input: [String: JSONValue]) -> Bool

    /// Whether this tool requires user interaction to complete.
    func requiresUserInteraction() -> Bool

    /// Returns search/read/list classification for UI collapsing.
    /// E.g., Grep returns isSearch:true, Read returns isRead:true, Bash ls returns isList:true.
    func isSearchOrReadCommand(_ input: [String: JSONValue]) -> SearchOrReadResult

    /// Determines if two tool inputs are equivalent (for deduplication).
    func inputsEquivalent(_ a: [String: JSONValue], _ b: [String: JSONValue]) -> Bool

    /// Add legacy/derived fields to observable input before observers see it.
    /// Called on copies only — never mutates the original API-bound input.
    func backfillObservableInput(_ input: inout [String: JSONValue])

    /// Prepare a matcher for hook permission-rule patterns.
    /// Called once per hook-input pair; expensive parsing happens here.
    func preparePermissionMatcher(_ input: [String: JSONValue]) async -> PermissionMatcher

    /// Short string summary of this tool use for compact display.
    func getToolUseSummary(_ input: [String: JSONValue]) -> String?

    /// Human-readable present-tense activity description for spinner display.
    /// E.g., "Reading src/foo.ts", "Running tests", "Searching for pattern".
    func getActivityDescription(_ input: [String: JSONValue]) -> String?

    /// Background color key for user-facing name in UI.
    func userFacingNameBackgroundColor(_ input: [String: JSONValue]) -> String?

    /// Whether this tool is a transparent wrapper (e.g., REPL) delegating all rendering.
    func isTransparentWrapper() -> Bool

    /// When true, enables API-level strict mode for this tool.
    var strict: Bool { get }

    /// Zod/JSON Schema for output validation (optional).
    var outputSchema: JSONSchema? { get }

    /// Raw JSON Schema for tool input (used by MCP tools that define schema directly).
    /// Matches Claude Code's inputJSONSchema field.
    var inputJSONSchema: JSONSchema? { get }

    /// Flattened text for transcript search indexing.
    /// Matches Claude Code's extractSearchText — returns visible text for
    /// transcript search count and highlight matching.
    func extractSearchText(_ output: ToolResult) -> String

    /// Returns true when the non-verbose rendering of this output is truncated.
    /// Matches Claude Code's isResultTruncated — gates click-to-expand in UI.
    func isResultTruncated(_ output: ToolResult) -> Bool
}

// MARK: - Tool Protocol Defaults

extension Tool {
    public var isReadOnly: Bool { false }
    public var isConcurrencySafe: Bool { false }
    public var aliases: [String] { [] }
    public var searchHint: String? { nil }
    public var isMcp: Bool { false }
    public var isLsp: Bool { false }
    public var shouldDefer: Bool { false }
    public var alwaysLoad: Bool { false }
    public var maxResultSizeChars: Int { 100_000 }
    public var strict: Bool { false }
    public var outputSchema: JSONSchema? { nil }
    public var inputJSONSchema: JSONSchema? { nil }
    public var mcpInfo: MCPToolInfo? { nil }

    public func isReadOnly(_ input: [String: JSONValue]) -> Bool { isReadOnly }
    public func isConcurrencySafe(_ input: [String: JSONValue]) -> Bool { isConcurrencySafe }
    public func interruptBehavior() -> InterruptBehavior { .block }
    public func isOpenWorld(_ input: [String: JSONValue]) -> Bool { false }
    public func requiresUserInteraction() -> Bool { false }
    public func isSearchOrReadCommand(_ input: [String: JSONValue]) -> SearchOrReadResult { .none }
    public func inputsEquivalent(_ a: [String: JSONValue], _ b: [String: JSONValue]) -> Bool { false }
    public func backfillObservableInput(_ input: inout [String: JSONValue]) {}
    public func preparePermissionMatcher(_ input: [String: JSONValue]) async -> PermissionMatcher { PermissionMatcher() }
    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? { nil }
    public func getActivityDescription(_ input: [String: JSONValue]) -> String? { nil }
    public func userFacingNameBackgroundColor(_ input: [String: JSONValue]) -> String? { nil }
    public func isTransparentWrapper() -> Bool { false }
    public func extractSearchText(_ output: ToolResult) -> String { output.content }
    public func isResultTruncated(_ output: ToolResult) -> Bool { false }

    public func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String {
        await description(input: [:], options: ToolDescriptionOptions())
    }

    public func checkPermissions(input: [String: JSONValue], context: ToolUseContext) async -> PermissionResult {
        .allow(PermissionAllowDecision())
    }

    public func validateInput(_ input: [String: JSONValue], context: ToolUseContext) async -> ValidationResult {
        .success
    }

    public func isDestructive(_ input: [String: JSONValue]) -> Bool { false }

    public func isEnabled() -> Bool { true }

    public func getPath(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return path
        }
        return nil
    }

    public func userFacingName(_ input: [String: JSONValue]) -> String {
        name
    }

    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any {
        ""
    }

    public func mapToolResultToToolResultBlockParam(_ content: ToolResult, toolUseID: String) -> ToolResultBlockParam {
        ToolResultBlockParam(
            toolUseID: toolUseID,
            type: "tool_result",
            content: content.content,
            isError: content.isError
        )
    }
}

// MARK: - ToolPermissionContext

/// Permission context consumed by tool permission checks and description().
/// Matches Claude Code's ToolPermissionContext with all 11 fields.
public struct ToolPermissionContext: Sendable {
    /// Current permission mode (default, acceptEdits, bypassPermissions, etc.).
    public let mode: PermissionMode
    /// Working directories beyond the project root granted permission scope.
    public let additionalWorkingDirectories: [String: AdditionalWorkingDirectory]
    /// Rules that always allow tools, keyed by source (userSettings, projectSettings, etc.).
    public let alwaysAllowRules: [PermissionRuleSource: [String]]
    /// Rules that always deny tools, keyed by source.
    public let alwaysDenyRules: [PermissionRuleSource: [String]]
    /// Rules that always ask for confirmation, keyed by source.
    public let alwaysAskRules: [PermissionRuleSource: [String]]
    /// Whether bypassPermissions mode is available (e.g., via CLI flag or settings).
    public let isBypassPermissionsModeAvailable: Bool
    /// Whether auto mode is available (gated by model support and settings).
    public let isAutoModeAvailable: Bool
    /// Dangerous permission rules stripped during auto mode transitions.
    /// Restored when exiting auto/plan mode.
    public let strippedDangerousRules: [PermissionRuleSource: [String]]
    /// Whether to suppress permission prompts (e.g., in non-interactive sessions).
    public let shouldAvoidPermissionPrompts: Bool
    /// Whether to wait for async classifier checks before showing dialogs.
    public let awaitAutomatedChecksBeforeDialog: Bool
    /// Previous permission mode before entering plan mode (for restoration).
    public let prePlanMode: PermissionMode?

    public init(
        mode: PermissionMode = .default,
        additionalWorkingDirectories: [String: AdditionalWorkingDirectory] = [:],
        alwaysAllowRules: [PermissionRuleSource: [String]] = [:],
        alwaysDenyRules: [PermissionRuleSource: [String]] = [:],
        alwaysAskRules: [PermissionRuleSource: [String]] = [:],
        isBypassPermissionsModeAvailable: Bool = false,
        isAutoModeAvailable: Bool = false,
        strippedDangerousRules: [PermissionRuleSource: [String]] = [:],
        shouldAvoidPermissionPrompts: Bool = false,
        awaitAutomatedChecksBeforeDialog: Bool = false,
        prePlanMode: PermissionMode? = nil
    ) {
        self.mode = mode
        self.additionalWorkingDirectories = additionalWorkingDirectories
        self.alwaysAllowRules = alwaysAllowRules
        self.alwaysDenyRules = alwaysDenyRules
        self.alwaysAskRules = alwaysAskRules
        self.isBypassPermissionsModeAvailable = isBypassPermissionsModeAvailable
        self.isAutoModeAvailable = isAutoModeAvailable
        self.strippedDangerousRules = strippedDangerousRules
        self.shouldAvoidPermissionPrompts = shouldAvoidPermissionPrompts
        self.awaitAutomatedChecksBeforeDialog = awaitAutomatedChecksBeforeDialog
        self.prePlanMode = prePlanMode
    }
}

// MARK: - Supporting Types

/// Options passed to the tool's description() method.
/// Matches Claude Code's description options: isNonInteractiveSession, toolPermissionContext, tools.
public struct ToolDescriptionOptions: Sendable {
    public let isNonInteractiveSession: Bool
    public let toolPermissionContext: ToolPermissionContext?
    public let tools: [any Tool]?

    public init(
        isNonInteractiveSession: Bool = false,
        toolPermissionContext: ToolPermissionContext? = nil,
        tools: [any Tool]? = nil
    ) {
        self.isNonInteractiveSession = isNonInteractiveSession
        self.toolPermissionContext = toolPermissionContext
        self.tools = tools
    }
}

/// MCP tool routing information.
public struct MCPToolInfo: Sendable {
    public let serverName: String
    public let toolName: String

    public init(serverName: String, toolName: String) {
        self.serverName = serverName
        self.toolName = toolName
    }
}

/// Input validation result, matching Claude Code's ValidationResult.
public enum ValidationResult: Sendable {
    case success
    case failure(message: String, errorCode: Int)
}

/// API ToolResultBlockParam format, matching Claude Code's mapToolResultToToolResultBlockParam output.
public struct ToolResultBlockParam: Sendable {
    public let toolUseID: String
    public let type: String
    public let content: String
    public let isError: Bool?

    public init(toolUseID: String, type: String, content: String, isError: Bool? = nil) {
        self.toolUseID = toolUseID
        self.type = type
        self.content = content
        self.isError = isError
    }
}

// MARK: - JSONSchema

public struct JSONSchema: Codable, Sendable {
    public var type: String
    public var properties: [String: JSONSchemaProperty]?
    public var required: [String]?
    public var additionalProperties: Bool?
    public var description: String?

    public init(
        type: String,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
        self.description = description
    }

    /// Validate input against this schema. Returns nil on success, error string on failure.
    /// Matches CC's tool.inputSchema.parse(input) validation step.
    public func validate(_ input: [String: JSONValue]) -> String? {
        // Check required fields
        if let required = required {
            for key in required {
                if input[key] == nil {
                    return "Missing required field: '\(key)'"
                }
            }
        }

        // Check property types
        if let properties = properties {
            for (key, prop) in properties {
                guard let value = input[key] else { continue }
                if let error = validateType(value, expectedType: prop.type, key: key) {
                    return error
                }
                if let enumValues = prop.enum {
                    if case .string(let s) = value, !enumValues.contains(s) {
                        return "Invalid value for '\(key)': '\(s)' not in [\(enumValues.joined(separator: ", "))]"
                    }
                }
            }
        }

        return nil
    }

    private func validateType(_ value: JSONValue, expectedType: String, key: String) -> String? {
        switch expectedType {
        case "string":
            if case .string = value { return nil }
        case "number":
            if case .number = value { return nil }
        case "boolean":
            if case .bool = value { return nil }
        case "array":
            if case .array = value { return nil }
        case "object":
            // object can be .object or .null (nullable objects)
            if case .object = value { return nil }
            if case .null = value { return nil }
        default:
            return nil // Unknown types pass through
        }
        return "Invalid type for '\(key)': expected \(expectedType)"
    }
}



/// Non-recursive JSON schema array items descriptor.
/// Matches CC's JSON Schema `items` field for array element typing.
public struct JSONSchemaItems: Codable, Sendable {
    public var type: String
    public var description: String?
    public var `enum`: [String]?
    public var pattern: String?
    public var minimum: Double?
    public var maximum: Double?
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        description: String? = nil,
        enum: [String]? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
    }
}


public struct JSONSchemaProperty: Codable, Sendable {
    public var type: String
    public var description: String?
    public var `enum`: [String]?
    public var items: JSONSchemaItems?
    public var pattern: String?
    public var minimum: Double?
    public var maximum: Double?
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        description: String? = nil,
        enum: [String]? = nil,
        items: JSONSchemaItems? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.items = items
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
    }
}

// MARK: - ToolUseContext

/// Execution context passed to every tool call.
/// Mirrors Claude Code's ToolUseContext with options, state, and identity fields.
public struct ToolUseContext: Sendable {
    // MARK: - Core identity

    public let workingDirectory: String
    public let sessionID: String
    public var toolUseID: String?
    /// Subagent identity (nil for main thread). Matches CC's agentId.
    public let agentId: String?
    /// Subagent type name. Matches CC's agentType.
    public let agentType: String?

    // MARK: - Permission & mode

    public let mode: PermissionMode
    public let approvalToken: String?
    public let isBypassPermissionsModeAvailable: Bool
    public let isAutoModeAvailable: Bool
    public let shouldAvoidPermissionPrompts: Bool
    public let isNonInteractiveSession: Bool
    public let awaitAutomatedChecksBeforeDialog: Bool
    public let prePlanMode: PermissionMode?

    // MARK: - Permission rules

    public var additionalWorkingDirectories: [String: String]
    public var alwaysAllowRules: [PermissionRuleSource: [String]]
    public var alwaysDenyRules: [PermissionRuleSource: [String]]
    public var alwaysAskRules: [PermissionRuleSource: [String]]
    public var strippedDangerousRules: [PermissionRuleSource: [String]]?
    public var toolDecisions: [String: ToolDecision]

    // MARK: - Denial tracking

    public var localDenialTracking: DenialTrackingState?

    // MARK: - Limits & budget

    public let maxBudgetUsd: Double?
    public var fileReadingLimits: FileReadingLimits?
    public var globLimits: GlobLimits?

    // MARK: - References (set by caller)

    /// Available messages for context (not Sendable-safe; use carefully).
    public var messages: [Message]
    /// Available tools. Matches CC's options.tools.
    public var tools: [any Tool]?
    /// MCP server connections. Matches CC's options.mcpClients.
    public var mcpClients: [any Sendable]?
    /// MCP resources. Matches CC's options.mcpResources.
    public var mcpResources: [String: [any Sendable]]?
    /// Agent definitions for subagent spawning.
    public var agentDefinitions: [any Sendable]?
    /// Available slash commands.
    public var commands: [any Sendable]?
    /// Thinking configuration.
    public var thinkingConfig: ThinkingConfig?
    /// Custom system prompt override.
    public var customSystemPrompt: String?
    /// Append to default system prompt.
    public var appendSystemPrompt: String?
    /// Main loop model ID (e.g. "claude-sonnet-4-6"). Matches CC's options.mainLoopModel.
    public var mainLoopModel: String?
    /// Where this query originated (analytics). Matches CC's options.querySource.
    public let querySource: QuerySource?
    /// Whether debug mode is enabled.
    public let debug: Bool
    /// Whether verbose mode is enabled.
    public let verbose: Bool
    /// Tool refresh callback (e.g., after MCP servers connect mid-query).
    /// Matches CC's options.refreshTools.
    public var refreshTools: (@Sendable () -> [any Tool])?

    /// Interactive permission prompt handler. Called when a tool requests `.ask` permission.
    /// Matches CC's permission prompt callback flow in the TUI layer.
    public var permissionPromptHandler: PermissionPromptHandler?

    /// Interactive user input prompt handler. Called by AskUserQuestionTool to
    /// present multiple-choice questions to the user and collect their response.
    /// When set, the tool blocks until the user responds.
    /// When nil, the tool falls back to formatting the question as text output.
    public var userInputPromptHandler: UserInputPromptHandler?

    // MARK: - State accessors

    /// Read file state for staleness detection. Matches CC's readFileState.
    public var readFileState: ReadFileState?
    /// Tracks query chain identity and depth across compactions.
    /// Matches CC's queryTracking in ToolUseContext.
    public var queryTracking: QueryChainTracking?

    // MARK: - Abort signal

    /// Cancel handler for aborting long-running operations.
    public var abortSignal: (@Sendable () -> Bool)?

    /// Whether sandbox mode is enabled. Used for sandbox-auto-allow bypass.
    public var sandbox: Bool?
    /// Resolved shell executable path (e.g. /bin/zsh, /bin/bash). Matches CC's options.shell.
    public var shell: String?

    // MARK: - Notification & UI callbacks (CC: ToolUseContext closures)

    /// Push a user-facing notification. CC: addNotification.
    public var addNotification: (@Sendable (String, String) -> Void)?
    /// Append a system message to the conversation. CC: appendSystemMessage.
    public var appendSystemMessage: (@Sendable (String) -> Void)?
    /// Send an OS-level desktop notification. CC: sendOSNotification.
    public var sendOSNotification: (@Sendable (String, String) -> Void)?
    /// Set the response length for streaming. CC: setResponseLength (updater pattern).
    public var setResponseLength: (@Sendable (@Sendable (Int) -> Int) -> Void)?
    /// Push API metrics entry. CC: pushApiMetricsEntry(ttftMs: number).
    public var pushApiMetricsEntry: (@Sendable (Int) -> Void)?
    /// Track in-progress tool use IDs. CC: setInProgressToolUseIDs (updater pattern).
    public var setInProgressToolUseIDs: (@Sendable (@Sendable (Set<String>) -> Set<String>) -> Void)?
    /// Open a message selector dialog. CC: openMessageSelector.
    public var openMessageSelector: (@Sendable () -> Void)?
    /// Update file history state. CC: updateFileHistoryState (updater pattern).
    public var updateFileHistoryState: (@Sendable (@Sendable (Any) -> Any) -> Void)?
    /// Set the conversation ID for persistence. CC: setConversationId.
    public var setConversationId: (@Sendable (String) -> Void)?
    /// Handle tool input elicitation. CC: handleElicitation(serverName, params, signal) → ElicitResult.
    public var handleElicitation: (@Sendable (String, Any, @Sendable () -> Bool) async -> Any)?
    /// Set SDK status for the frontend. CC: setSDKStatus.
    public var setSDKStatus: (@Sendable (String) -> Void)?
    /// Rendered system prompt (read-only, set by caller). CC: renderedSystemPrompt.
    public var renderedSystemPrompt: String?
    /// Whether user has modified content since last rendering. CC: userModified.
    public var userModified: Bool
    /// Nested memory attachment trigger paths. CC: nestedMemoryAttachmentTriggers. Uses Set for dedup.
    public var nestedMemoryAttachmentTriggers: Set<String>?
    /// Dynamic skill directory trigger paths. CC: dynamicSkillDirTriggers. Uses Set for dedup.
    public var dynamicSkillDirTriggers: Set<String>?
    /// Discovered skill names from skill directories. CC: discoveredSkillNames. Uses Set for dedup.
    public var discoveredSkillNames: Set<String>?

    // MARK: - Missing CC fields (Iteration 56)

    /// Abort controller — triggers cancellation. CC: abortController: AbortController.
    /// SA keeps abortSignal for checking; abortController triggers the abort.
    public var abortController: (@Sendable () -> Void)?
    /// Read app state snapshot. CC: getAppState(): AppState.
    public var getAppState: (@Sendable () -> Any)?
    /// Update app state. CC: setAppState(f: (prev: AppState) => AppState): void.
    public var setAppState: (@Sendable (@Sendable (Any) -> Any) -> Void)?
    /// Session-scoped setAppState fallback. CC: setAppStateForTasks.
    public var setAppStateForTasks: (@Sendable (@Sendable (Any) -> Any) -> Void)?
    /// JSX injection for UI. CC: setToolJSX: SetToolJSXFn (React-specific).
    public var setToolJSX: (@Sendable (Any) -> Void)?
    /// CLAUDE.md paths already injected as nested_memory attachments this session.
    /// Dedup for memoryFilesToAttachments. CC: loadedNestedMemoryPaths: Set<string>.
    public var loadedNestedMemoryPaths: Set<String>?
    /// Only wired in interactive (REPL) contexts. CC: setHasInterruptibleToolInProgress.
    public var setHasInterruptibleToolInProgress: (@Sendable (Bool) -> Void)?
    /// Set spinner display mode. CC: setStreamMode(mode: SpinnerMode).
    public var setStreamMode: (@Sendable (String) -> Void)?
    /// Progress events emitted during compaction. CC: onCompactProgress.
    public var onCompactProgress: (@Sendable (Any) -> Void)?
    /// Update git attribution state. CC: updateAttributionState (updater pattern).
    public var updateAttributionState: (@Sendable (@Sendable (Any) -> Any) -> Void)?
    /// When true, canUseTool must always be called even when hooks auto-approve.
    /// Used by speculation for overlay file path rewriting. CC: requireCanUseTool.
    public var requireCanUseTool: Bool?
    /// Callback factory for requesting interactive prompts from the user.
    /// Returns a prompt callback bound to the given source name. CC: requestPrompt.
    public var requestPrompt: (@Sendable (String, String?) -> (@Sendable (Any) async -> Any)?)?
    /// Critical system reminder injected into system prompt. CC: criticalSystemReminder_EXPERIMENTAL.
    public var criticalSystemReminder_EXPERIMENTAL: String?
    /// Toggle plan mode active state. Called by EnterPlanMode / ExitPlanMode tools.
    /// Matches CC's setPlanMode(active: boolean) on AppState.
    public var setPlanModeActive: (@Sendable (Bool) -> Void)?
    /// When true, preserve toolUseResult on messages even for subagents.
    /// Used by in-process teammates. CC: preserveToolUseResults.
    public var preserveToolUseResults: Bool?
    /// Per-conversation-thread content replacement state for the tool result budget.
    /// CC: contentReplacementState: ContentReplacementState.
    public var contentReplacementState: (any Sendable)?

    public init(
        workingDirectory: String,
        sessionID: String,
        toolUseID: String? = nil,
        agentId: String? = nil,
        agentType: String? = nil,
        mode: PermissionMode = .default,
        approvalToken: String? = nil,
        isBypassPermissionsModeAvailable: Bool = false,
        isAutoModeAvailable: Bool = false,
        shouldAvoidPermissionPrompts: Bool = false,
        isNonInteractiveSession: Bool = false,
        awaitAutomatedChecksBeforeDialog: Bool = false,
        prePlanMode: PermissionMode? = nil,
        additionalWorkingDirectories: [String: String] = [:],
        alwaysAllowRules: [PermissionRuleSource: [String]] = [:],
        alwaysDenyRules: [PermissionRuleSource: [String]] = [:],
        alwaysAskRules: [PermissionRuleSource: [String]] = [:],
        strippedDangerousRules: [PermissionRuleSource: [String]]? = nil,
        toolDecisions: [String: ToolDecision] = [:],
        localDenialTracking: DenialTrackingState? = nil,
        maxBudgetUsd: Double? = nil,
        fileReadingLimits: FileReadingLimits? = nil,
        globLimits: GlobLimits? = nil,
        messages: [Message] = [],
        tools: [any Tool]? = nil,
        mcpClients: [any Sendable]? = nil,
        mcpResources: [String: [any Sendable]]? = nil,
        agentDefinitions: [any Sendable]? = nil,
        commands: [any Sendable]? = nil,
        thinkingConfig: ThinkingConfig? = nil,
        customSystemPrompt: String? = nil,
        appendSystemPrompt: String? = nil,
        debug: Bool = false,
        verbose: Bool = false,
        readFileState: ReadFileState? = nil,
        queryTracking: QueryChainTracking? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        sandbox: Bool? = nil,
        shell: String? = nil,
        mainLoopModel: String? = nil,
        querySource: QuerySource? = nil,
        refreshTools: (@Sendable () -> [any Tool])? = nil,
        permissionPromptHandler: PermissionPromptHandler? = nil,
        userInputPromptHandler: UserInputPromptHandler? = nil,
        addNotification: (@Sendable (String, String) -> Void)? = nil,
        appendSystemMessage: (@Sendable (String) -> Void)? = nil,
        sendOSNotification: (@Sendable (String, String) -> Void)? = nil,
        setResponseLength: (@Sendable (@Sendable (Int) -> Int) -> Void)? = nil,
        pushApiMetricsEntry: (@Sendable (Int) -> Void)? = nil,
        setInProgressToolUseIDs: (@Sendable (@Sendable (Set<String>) -> Set<String>) -> Void)? = nil,
        openMessageSelector: (@Sendable () -> Void)? = nil,
        updateFileHistoryState: (@Sendable (@Sendable (Any) -> Any) -> Void)? = nil,
        setConversationId: (@Sendable (String) -> Void)? = nil,
        handleElicitation: (@Sendable (String, Any, @Sendable () -> Bool) async -> Any)? = nil,
        setSDKStatus: (@Sendable (String) -> Void)? = nil,
        renderedSystemPrompt: String? = nil,
        userModified: Bool = false,
        nestedMemoryAttachmentTriggers: Set<String>? = nil,
        dynamicSkillDirTriggers: Set<String>? = nil,
        discoveredSkillNames: Set<String>? = nil,
        // Iteration 56 — new CC-parity fields
        abortController: (@Sendable () -> Void)? = nil,
        getAppState: (@Sendable () -> Any)? = nil,
        setAppState: (@Sendable (@Sendable (Any) -> Any) -> Void)? = nil,
        setAppStateForTasks: (@Sendable (@Sendable (Any) -> Any) -> Void)? = nil,
        setToolJSX: (@Sendable (Any) -> Void)? = nil,
        loadedNestedMemoryPaths: Set<String>? = nil,
        setHasInterruptibleToolInProgress: (@Sendable (Bool) -> Void)? = nil,
        setStreamMode: (@Sendable (String) -> Void)? = nil,
        onCompactProgress: (@Sendable (Any) -> Void)? = nil,
        updateAttributionState: (@Sendable (@Sendable (Any) -> Any) -> Void)? = nil,
        requireCanUseTool: Bool? = nil,
        requestPrompt: (@Sendable (String, String?) -> (@Sendable (Any) async -> Any)?)? = nil,
        criticalSystemReminder_EXPERIMENTAL: String? = nil,
        preserveToolUseResults: Bool? = nil,
        setPlanModeActive: (@Sendable (Bool) -> Void)? = nil,
        contentReplacementState: (any Sendable)? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
        self.toolUseID = toolUseID
        self.agentId = agentId
        self.agentType = agentType
        self.mode = mode
        self.approvalToken = approvalToken
        self.isBypassPermissionsModeAvailable = isBypassPermissionsModeAvailable
        self.isAutoModeAvailable = isAutoModeAvailable
        self.shouldAvoidPermissionPrompts = shouldAvoidPermissionPrompts
        self.isNonInteractiveSession = isNonInteractiveSession
        self.awaitAutomatedChecksBeforeDialog = awaitAutomatedChecksBeforeDialog
        self.prePlanMode = prePlanMode
        self.additionalWorkingDirectories = additionalWorkingDirectories
        self.alwaysAllowRules = alwaysAllowRules
        self.alwaysDenyRules = alwaysDenyRules
        self.alwaysAskRules = alwaysAskRules
        self.strippedDangerousRules = strippedDangerousRules
        self.toolDecisions = toolDecisions
        self.localDenialTracking = localDenialTracking
        self.maxBudgetUsd = maxBudgetUsd
        self.fileReadingLimits = fileReadingLimits
        self.globLimits = globLimits
        self.messages = messages
        self.tools = tools
        self.mcpClients = mcpClients
        self.mcpResources = mcpResources
        self.agentDefinitions = agentDefinitions
        self.commands = commands
        self.thinkingConfig = thinkingConfig
        self.customSystemPrompt = customSystemPrompt
        self.appendSystemPrompt = appendSystemPrompt
        self.mainLoopModel = mainLoopModel
        self.querySource = querySource
        self.debug = debug
        self.verbose = verbose
        self.readFileState = readFileState
        self.queryTracking = queryTracking
        self.refreshTools = refreshTools
        self.permissionPromptHandler = permissionPromptHandler
        self.userInputPromptHandler = userInputPromptHandler
        self.abortSignal = abortSignal
        self.sandbox = sandbox
        self.shell = shell
        self.addNotification = addNotification
        self.appendSystemMessage = appendSystemMessage
        self.sendOSNotification = sendOSNotification
        self.setResponseLength = setResponseLength
        self.pushApiMetricsEntry = pushApiMetricsEntry
        self.setInProgressToolUseIDs = setInProgressToolUseIDs
        self.openMessageSelector = openMessageSelector
        self.updateFileHistoryState = updateFileHistoryState
        self.setConversationId = setConversationId
        self.handleElicitation = handleElicitation
        self.setSDKStatus = setSDKStatus
        self.renderedSystemPrompt = renderedSystemPrompt
        self.userModified = userModified
        self.nestedMemoryAttachmentTriggers = nestedMemoryAttachmentTriggers
        self.dynamicSkillDirTriggers = dynamicSkillDirTriggers
        self.discoveredSkillNames = discoveredSkillNames
        self.abortController = abortController
        self.getAppState = getAppState
        self.setAppState = setAppState
        self.setAppStateForTasks = setAppStateForTasks
        self.setToolJSX = setToolJSX
        self.loadedNestedMemoryPaths = loadedNestedMemoryPaths
        self.setHasInterruptibleToolInProgress = setHasInterruptibleToolInProgress
        self.setStreamMode = setStreamMode
        self.onCompactProgress = onCompactProgress
        self.updateAttributionState = updateAttributionState
        self.requireCanUseTool = requireCanUseTool
        self.requestPrompt = requestPrompt
        self.criticalSystemReminder_EXPERIMENTAL = criticalSystemReminder_EXPERIMENTAL
        self.preserveToolUseResults = preserveToolUseResults
        self.setPlanModeActive = setPlanModeActive
        self.contentReplacementState = contentReplacementState
    }
}

extension ToolUseContext {
    /// Default context for permission checks and simple operations.
    public static let `default` = ToolUseContext(
        workingDirectory: FileManager.default.currentDirectoryPath,
        sessionID: "default"
    )
}

// MARK: - ToolUseContext Supporting Types

/// A recorded tool permission decision. Matches CC's toolDecisions map value.
public struct ToolDecision: Sendable, Codable {
    public let source: String
    public let decision: String  // "accept" | "reject"
    public let timestamp: Double

    public init(source: String, decision: String, timestamp: Double = 0) {
        self.source = source
        self.decision = decision
        self.timestamp = timestamp
    }
}

/// File reading limits. Matches CC's fileReadingLimits.
public struct FileReadingLimits: Sendable {
    public let maxTokens: Int?
    public let maxSizeBytes: Int?

    public init(maxTokens: Int? = nil, maxSizeBytes: Int? = nil) {
        self.maxTokens = maxTokens
        self.maxSizeBytes = maxSizeBytes
    }
}

/// Glob search limits. Matches CC's globLimits.
public struct GlobLimits: Sendable {
    public let maxResults: Int?

    public init(maxResults: Int? = nil) {
        self.maxResults = maxResults
    }
}

/// Tracks where a query originated — analytics dimension.
/// Matches CC's QuerySource from constants/querySource.ts.
public enum QuerySource: String, Sendable, Codable {
    case repl = "repl_main_thread"
    case compact = "compact"
    case sessionMemory = "session_memory"
    case agent = "agent"
    case skill = "skill"
    case slashCommand = "slash_command"
    case hook = "hook"
    case cron = "cron"
    case mcp = "mcp"
    case sdk = "sdk"
    case unknown = "unknown"
}

/// Tracks query chain identity and nesting depth across compactions and subagent spawns.
/// Matches CC's QueryChainTracking in Tool.ts.
public struct QueryChainTracking: Sendable {
    public let chainId: String
    public var depth: Int

    public init(chainId: String = UUID().uuidString, depth: Int = 0) {
        self.chainId = chainId
        self.depth = depth
    }
}

/// Read file state for staleness detection. Matches CC's readFileState.
public struct ReadFileState: Sendable {
    private var cache: [String: Int] = [:]

    public init() {}

    public func hash(for path: String) -> Int? {
        cache[path]
    }

    public mutating func setHash(_ hash: Int, for path: String) {
        cache[path] = hash
    }

    public func has(_ path: String) -> Bool {
        cache[path] != nil
    }
}

// MARK: - ToolOutput (Discriminated Union)

/// Structured tool output, matching Claude Code's discriminated union output schema.
/// Each variant corresponds to a tool result type (text, image, notebook, PDF, file_unchanged, parts).
public enum ToolOutput: Sendable {
    /// Plain text output.
    case text(String)
    /// Image output with base64 data.
    case image(type: String, data: String, size: Int? = nil, dimensions: (Int, Int)? = nil)
    /// Jupyter notebook output.
    case notebook(cells: [NotebookCell])
    /// PDF document output.
    case pdf(pages: [PDFPage])
    /// File was unchanged (re-read dedup).
    case fileUnchanged(path: String)
    /// Multiple output parts (for complex responses).
    case parts([ToolOutput])

    /// String representation of this output (for backward compatibility).
    public var textContent: String {
        switch self {
        case .text(let s): return s
        case .image(let type, _, let size, let dims):
            var desc = "[Image: \(type)"
            if let size { desc += ", \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))" }
            if let dims { desc += ", \(dims.0)x\(dims.1)px" }
            desc += "]"
            return desc
        case .notebook(let cells):
            return cells.map(\.textContent).joined(separator: "\n\n")
        case .pdf(let pages):
            return pages.map(\.textContent).joined(separator: "\n\n")
        case .fileUnchanged(let path):
            return "[File unchanged: \(path)]"
        case .parts(let outputs):
            return outputs.map(\.textContent).joined(separator: "\n")
        }
    }
}

/// A Jupyter notebook cell.
public struct NotebookCell: Sendable {
    public let cellType: String  // "code" | "markdown"
    public let source: [String]
    public let outputs: [String]?

    public init(cellType: String, source: [String], outputs: [String]? = nil) {
        self.cellType = cellType
        self.source = source
        self.outputs = outputs
    }

    public var textContent: String {
        source.joined()
    }
}

/// A PDF page.
public struct PDFPage: Sendable {
    public let pageNumber: Int
    public let text: String

    public init(pageNumber: Int, text: String) {
        self.pageNumber = pageNumber
        self.text = text
    }

    public var textContent: String {
        "--- Page \(pageNumber) ---\n\(text)"
    }
}

// MARK: - ToolResult

/// Result from a tool execution, matching Claude Code's ToolResult<T>.
public struct ToolResult: Sendable {
    /// Structured output data (maps to `data` in Claude Code's generic ToolResult<T>).
    /// When nil, falls back to deprecated `content` string.
    public var data: ToolOutput?
    /// Primary output content (deprecated in favor of `data`; kept for backward compatibility).
    public var content: String
    /// Whether the result represents an error.
    public var isError: Bool
    /// New messages to inject into the conversation (matching CC's newMessages).
    public var newMessages: [Message]?
    /// MCP protocol metadata passthrough for SDK consumers.
    public var mcpMeta: MCPMeta?
    /// Function that modifies ToolUseContext after tool execution.
    /// Matches CC's contextModifier: (context: ToolUseContext) => ToolUseContext.
    public var contextModifier: (@Sendable (ToolUseContext) -> ToolUseContext)?
    /// Whether this result was persisted to disk (too large for inline).
    /// Matches CC's persistedToDisk flag on ToolResult.
    public var persistedToDisk: Bool
    /// Path to the persisted file on disk, if persisted.
    /// Matches CC's persistDirPath on ToolResult.
    public var persistDirPath: String?

    public init(
        content: String,
        isError: Bool = false,
        newMessages: [Message]? = nil,
        mcpMeta: MCPMeta? = nil,
        contextModifier: (@Sendable (ToolUseContext) -> ToolUseContext)? = nil,
        persistedToDisk: Bool = false,
        persistDirPath: String? = nil
    ) {
        self.data = nil
        self.content = content
        self.isError = isError
        self.newMessages = newMessages
        self.mcpMeta = mcpMeta
        self.contextModifier = contextModifier
        self.persistedToDisk = persistedToDisk
        self.persistDirPath = persistDirPath
    }

    public init(
        data: ToolOutput,
        isError: Bool = false,
        newMessages: [Message]? = nil,
        mcpMeta: MCPMeta? = nil,
        contextModifier: (@Sendable (ToolUseContext) -> ToolUseContext)? = nil,
        persistedToDisk: Bool = false,
        persistDirPath: String? = nil
    ) {
        self.data = data
        self.content = data.textContent
        self.isError = isError
        self.newMessages = newMessages
        self.mcpMeta = mcpMeta
        self.contextModifier = contextModifier
        self.persistedToDisk = persistedToDisk
        self.persistDirPath = persistDirPath
    }
}

/// MCP protocol metadata, matching Claude Code's mcpMeta field.
public struct MCPMeta: Codable, Sendable {
    public var _meta: [String: JSONValue]?
    public var structuredContent: [String: JSONValue]?

    public init(_meta: [String: JSONValue]? = nil, structuredContent: [String: JSONValue]? = nil) {
        self._meta = _meta
        self.structuredContent = structuredContent
    }
}

// MARK: - InterruptBehavior

/// Controls behavior when user submits input during tool execution.
/// Matches Claude Code's interruptBehavior(): 'cancel' | 'block'.
public enum InterruptBehavior: String, Sendable {
    /// Stop the tool and discard its result.
    case cancel
    /// Keep running; the new message waits.
    case block
}

// MARK: - SearchOrReadResult

/// Classification for UI collapsing of search/read operations.
/// Matches Claude Code's isSearchOrReadCommand() return type.
public struct SearchOrReadResult: Sendable, Equatable {
    public let isSearch: Bool
    public let isRead: Bool
    public let isList: Bool

    public init(isSearch: Bool = false, isRead: Bool = false, isList: Bool = false) {
        self.isSearch = isSearch
        self.isRead = isRead
        self.isList = isList
    }

    /// No special classification.
    public static let none = SearchOrReadResult()
}

// MARK: - PermissionMatcher

/// Closure-based matcher for hook permission-rule patterns.
/// Matches Claude Code's preparePermissionMatcher return.
public struct PermissionMatcher: Sendable {
    private let _matches: @Sendable (String) -> Bool

    public init(matches: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self._matches = matches
    }

    public func matches(pattern: String) -> Bool {
        _matches(pattern)
    }
}
