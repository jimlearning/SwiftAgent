import Foundation

// MARK: - Settings

/// Top-level settings matching Claude Code's SettingsSchema.
/// Codable auto-synthesizes; all fields have defaults so partial JSON is accepted.
/// Uses the existing SandboxSettings (from SandboxSettings.swift) and ThinkingConfig.
public struct Settings: Codable, Sendable {
    // MARK: Core

    public var model: ModelConfig = .defaultModel
    public var permissionMode: PermissionMode = .default
    public var maxTokens: Int = 200_000
    public var tools: [String] = []
    public var mcpServers: [MCPServerConfig] = []
    public var hooks: [HookConfig] = []
    public var sandbox: SandboxSettings? = nil
    public var thinking: ThinkingConfig? = nil

    // MARK: General

    public var env: [String: String]? = nil
    public var respectGitignore: Bool? = nil
    public var cleanupPeriodDays: Int? = nil
    public var fileSuggestion: FileSuggestionConfig? = nil

    // MARK: Attribution

    public var attribution: AttributionConfig? = nil
    public var includeGitInstructions: Bool? = nil

    // MARK: Permissions

    public var permissions: PermissionsConfig? = nil

    // MARK: MCP

    public var enableAllProjectMcpServers: Bool? = nil
    public var enabledMcpjsonServers: [String]? = nil
    public var disabledMcpjsonServers: [String]? = nil
    public var allowedMcpServers: [String]? = nil
    public var deniedMcpServers: [String]? = nil

    // MARK: Hooks

    public var disableAllHooks: Bool? = nil
    public var allowedHttpHookUrls: [String]? = nil
    public var httpHookAllowedEnvVars: [String]? = nil

    // MARK: Plugins & Marketplaces

    public var enabledPlugins: [String]? = nil
    public var extraKnownMarketplaces: [String]? = nil
    public var strictKnownMarketplaces: Bool? = nil
    public var blockedMarketplaces: [String]? = nil
    public var pluginEntryConfigs: [String: PluginEntryConfig]? = nil

    // MARK: UI / Display

    public var outputStyle: String? = nil
    public var syntaxHighlightingDisabled: Bool? = nil
    public var statusLine: StatusLineConfig? = nil
    public var spinnerTipsEnabled: Bool? = nil
    public var spinnerVerbs: SpinnerVerbsConfig? = nil
    public var spinnerTipsOverride: SpinnerTipsOverrideConfig? = nil
    public var showThinkingSummaries: Bool? = nil
    public var prefersReducedMotion: Bool? = nil
    public var terminalTitleFromRename: Bool? = nil

    // MARK: Thinking & Models

    public var alwaysThinkingEnabled: Bool? = nil
    public var effortLevel: String? = nil
    public var fastMode: Bool? = nil
    public var fastModePerSessionOptIn: Bool? = nil
    public var modelOverrides: [String: String]? = nil
    public var availableModels: [ModelConfig]? = nil
    public var advisorModel: String? = nil
    /// Fallback model when primary model fails with repeated 529 overload errors.
    /// Matches CC's fallbackModel in query params.
    public var fallbackModel: String? = nil

    // MARK: AI Features

    public var agent: AgentSettingsConfig? = nil
    public var autoCompactEnabled: Bool? = nil
    public var autoMemoryEnabled: Bool? = nil
    public var autoMemoryDirectory: String? = nil
    public var promptSuggestionEnabled: Bool? = nil
    public var showClearContextOnPlanAccept: Bool? = nil

    // MARK: Auth / Credentials

    public var apiKeyHelper: String? = nil
    public var otelHeadersHelper: String? = nil
    public var awsCredentialExport: String? = nil
    public var awsAuthRefresh: String? = nil
    public var gcpAuthRefresh: String? = nil
    public var forceLoginMethod: String? = nil
    public var forceLoginOrgUUID: String? = nil

    // MARK: Auto Mode

    public var autoMode: AutoModeConfig? = nil
    public var skipDangerousModePermissionPrompt: Bool? = nil
    public var skipAutoPermissionPrompt: Bool? = nil
    public var useAutoModeDuringPlan: Bool? = nil
    /// CC uses string literal "disable" to match the Zod enum. Use `"disable"` to disable.
    public var disableAutoMode: String? = nil
    public var classifierPermissionsEnabled: Bool? = nil

    // MARK: Infrastructure

    public var defaultShell: String? = nil
    public var worktree: WorktreeConfig? = nil
    public var sshConfigs: [SSHConfig]? = nil
    public var remote: RemoteConfig? = nil

    // MARK: Misc

    /// JSON Schema reference URL. Maps to "$schema" in JSON (note: CC uses $schema key).
    public var schema: String? = nil
    public var claudeMdExcludes: [String]? = nil
    public var language: String? = nil
    public var skipWebFetchPreflight: Bool? = nil
    public var feedbackSurveyRate: Double? = nil
    public var companyAnnouncements: [String]? = nil
    public var autoUpdatesChannel: String? = nil
    public var minimumVersion: String? = nil
    public var plansDirectory: String? = nil

    // MARK: Teams / Channels

    /// Enable team channel notifications. CC: channelsEnabled.
    public var channelsEnabled: Bool? = nil
    /// Allowlist of channel plugins (enterprise). CC: allowedChannelPlugins.
    public var allowedChannelPlugins: [String]? = nil

    // MARK: Dream / Background

    /// Enable background memory consolidation (auto-dream). CC: autoDreamEnabled.
    public var autoDreamEnabled: Bool? = nil

    // MARK: Assistant Mode

    /// Assistant mode configuration. CC: assistant.
    public var assistant: String? = nil
    /// Display name for assistant mode. CC: assistantName.
    public var assistantName: String? = nil

    // MARK: Voice

    /// Enable voice mode input. CC: voiceEnabled.
    public var voiceEnabled: Bool? = nil

    // MARK: Sleep Tool

    /// Minimum sleep duration in ms for SleepTool. CC: minSleepDurationMs.
    public var minSleepDurationMs: Int? = nil
    /// Maximum sleep duration in ms for SleepTool. CC: maxSleepDurationMs.
    public var maxSleepDurationMs: Int? = nil

    // MARK: Display

    /// Default view: "chat" or "transcript". CC: defaultView.
    public var defaultView: String? = nil
    /// Prevent OS deep-link protocol handler registration. CC: disableDeepLinkRegistration.
    public var disableDeepLinkRegistration: Bool? = nil

    // MARK: Plugin Configs

    /// Per-plugin configuration keyed by plugin ID. CC: pluginConfigs.
    /// Each entry can carry nested mcpServers and options maps.
    public var pluginConfigs: [String: PluginConfigEntry]? = nil

    // MARK: Enterprise / Policy

    /// Enterprise custom trust dialog message. CC: pluginTrustMessage.
    public var pluginTrustMessage: String? = nil

    public var allowManagedHooksOnly: Bool? = nil
    public var allowManagedPermissionRulesOnly: Bool? = nil
    public var allowManagedMcpServersOnly: Bool? = nil
    /// CC supports Bool or Array of surface names. SA: Bool for now.
    public var strictPluginOnlyCustomization: Bool? = nil

    // MARK: Auth / SSO

    /// XAA/OIDC IdP configuration. CC: xaaIdp (env-gated).
    public var xaaIdp: String? = nil

    // MARK: Init

    public init(
        model: ModelConfig = .defaultModel,
        permissionMode: PermissionMode = .default,
        maxTokens: Int = 200_000,
        tools: [String] = [],
        mcpServers: [MCPServerConfig] = [],
        hooks: [HookConfig] = [],
        sandbox: SandboxSettings? = nil,
        thinking: ThinkingConfig? = nil
    ) {
        self.model = model
        self.permissionMode = permissionMode
        self.maxTokens = maxTokens
        self.tools = tools
        self.mcpServers = mcpServers
        self.hooks = hooks
        self.sandbox = sandbox
        self.thinking = thinking
    }
}

// MARK: - Settings Validation

/// Result of settings validation.
public struct SettingsValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool = true, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

extension Settings {
    /// Validate settings matching Claude Code's Zod schema constraints.
    /// Returns errors for invalid values and warnings for suspicious/misconfigured settings.
    public func validate() -> SettingsValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Model validation
        if model.modelID.isEmpty {
            errors.append("model.modelID must not be empty")
        }
        if let minVer = minimumVersion, !isValidSemver(minVer) {
            errors.append("minimumVersion must be a valid semver (e.g. \"1.2.3\")")
        }

        // Token budget
        if maxTokens < 1000 {
            errors.append("maxTokens must be at least 1000")
        }
        if maxTokens > 1_000_000 {
            warnings.append("maxTokens > 1M may cause API errors")
        }

        // Subagent count
        if let maxSubagents = agent?.maxSubagents, maxSubagents < 0 {
            errors.append("agent.maxSubagents must be non-negative")
        }

        // MCP server validation
        for server in mcpServers {
            if server.name.isEmpty {
                errors.append("MCP server name must not be empty")
            }
            if server.transport == .stdio && server.command == nil {
                errors.append("MCP server \"\(server.name)\": stdio transport requires a command")
            }
            if (server.transport == .http || server.transport == .sse) && server.url == nil {
                errors.append("MCP server \"\(server.name)\": HTTP/SSE transport requires a URL")
            }
        }

        // Hook validation
        for hook in hooks {
            switch hook.type {
            case .command where hook.command == nil:
                errors.append("Hook \"\(hook.id)\": command type requires a command")
            case .http where hook.url == nil:
                errors.append("Hook \"\(hook.id)\": http type requires a url")
            default:
                break
            }
        }

        // Auto mode config
        if let autoMode = autoMode {
            if let allow = autoMode.allow, allow.contains(where: { $0.isEmpty }) {
                errors.append("autoMode.allow contains empty pattern")
            }
            if let deny = autoMode.deny, deny.contains(where: { $0.isEmpty }) {
                errors.append("autoMode.deny contains empty pattern")
            }
        }

        // Permission conflicts
        if let permissions = permissions {
            if let allow = permissions.allow, let deny = permissions.deny {
                let intersection = Set(allow).intersection(Set(deny))
                if !intersection.isEmpty {
                    warnings.append("Permissions allow and deny both match: \(intersection.joined(separator: ", ")) — deny takes priority")
                }
            }
        }

        // SSH config validation
        if let sshConfigs = sshConfigs {
            for ssh in sshConfigs {
                if ssh.name.isEmpty {
                    errors.append("SSH config name must not be empty")
                }
                if ssh.sshHost.isEmpty {
                    errors.append("SSH config \"\(ssh.name)\": sshHost must not be empty")
                }
            }
        }

        return SettingsValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func isValidSemver(_ version: String) -> Bool {
        let pattern = #"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - APIProvider

/// Anthropic API provider type. Matches CC's APIProvider in utils/model/providers.ts:4.
public enum APIProvider: String, Codable, Sendable, CaseIterable {
    case firstParty = "anthropic"
    case bedrock = "bedrock"
    case vertex = "vertex"
    case foundry = "foundry"
}

// MARK: - CacheScope

/// Cache scope for Anthropic API prompt caching.
/// Matches Claude Code's CacheScope in utils/api.ts:80: `'global' | 'org'`.
public enum CacheScope: String, Codable, Sendable, CaseIterable {
    case global
    case org
}

// MARK: - SystemPromptBlock

/// A block of the system prompt with optional cache scope.
/// Matches Claude Code's SystemPromptBlock in utils/api.ts:81-84.
public struct SystemPromptBlock: Codable, Sendable {
    public var text: String
    public var cacheScope: CacheScope?

    public init(text: String, cacheScope: CacheScope? = nil) {
        self.text = text
        self.cacheScope = cacheScope
    }
}

// MARK: - ModelConfig

public struct ModelConfig: Codable, Sendable {
    public var provider: APIProvider
    public var modelID: String

    public init(provider: APIProvider = .firstParty, modelID: String = "claude-sonnet-4-6") {
        self.provider = provider
        self.modelID = modelID
    }

    public static let defaultModel = ModelConfig()
}

// MARK: - MCP

public struct MCPServerConfig: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var transport: MCPTransportType
    public var command: [String]?
    public var url: String?
    public var headers: [String: String]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        transport: MCPTransportType,
        command: [String]? = nil,
        url: String? = nil,
        headers: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.url = url
        self.headers = headers
    }
}

/// MCP transport types matching Claude Code's supported transports.
/// CC supports: stdio, sse, streamable-http, sse-ide, ws, ws-ide, sdk, claudeai-proxy.
public enum MCPTransportType: String, Codable, Sendable {
    case stdio
    case sse
    case http = "streamable-http"
    case sseIde = "sse-ide"
    case ws
    case wsIde = "ws-ide"
    case sdk
    case claudeaiProxy = "claudeai-proxy"
}

// MARK: - Hooks

/// Hook type — determines how the hook is executed.
/// Matches Claude Code's hook types: command (shell), http, agent, prompt.
public enum HookType: String, Codable, Sendable {
    case command
    case http
    case agent
    case prompt
    case callback
    case function
}

public struct HookConfig: Codable, Sendable, Identifiable {
    public var id: String
    public var type: HookType
    public var event: HookEvent
    /// Shell command (for command type hooks). Matches CC's `command` field.
    public var command: String?
    /// URL endpoint (for HTTP type hooks). Matches CC's `url` field.
    public var url: String?
    /// Tool name regex pattern for filtering hook execution.
    /// Matches CC's outer `matcher` — hooks grouped under the same key.
    public var matcher: String?
    /// Permission-rule syntax filter (e.g. "Bash(git *)").
    /// Matches CC's `if` field — filters hook execution by permission rules.
    public var conditionFilter: String?
    /// Shell to use for command hooks ("bash" | "powershell"). CC: `shell`.
    public var shell: String?
    /// Prompt text (for prompt/agent type hooks). CC: `prompt`.
    public var prompt: String?
    /// Model override for prompt/agent hooks. CC: `model`.
    public var model: String?
    /// HTTP headers for HTTP hooks. CC: `headers`.
    public var headers: [String: String]?
    /// Environment variables allowed in HTTP hook bodies. CC: `allowedEnvVars`.
    public var allowedEnvVars: [String]?
    /// Spinner/status message shown during hook execution. CC: `statusMessage`.
    public var statusMessage: String?
    /// Run hook once then remove. CC: `once`.
    public var once: Bool?
    /// Run asynchronously (non-blocking). CC: `async`.
    public var async: Bool?
    /// Run in background and reawaken on exit code 2. CC: `asyncRewake`.
    public var asyncRewake: Bool?
    /// Seconds before hook is killed. Matches CC's `timeout`.
    public var timeout: Int?
    /// Which settings source this hook was loaded from.
    /// Matches CC's HookSource tracking per IndividualHookConfig.
    public var source: HookSource?

    public init(
        id: String = UUID().uuidString,
        type: HookType = .command,
        event: HookEvent,
        command: String? = nil,
        url: String? = nil,
        matcher: String? = nil,
        conditionFilter: String? = nil,
        shell: String? = nil,
        prompt: String? = nil,
        model: String? = nil,
        headers: [String: String]? = nil,
        allowedEnvVars: [String]? = nil,
        statusMessage: String? = nil,
        once: Bool? = nil,
        async: Bool? = nil,
        asyncRewake: Bool? = nil,
        timeout: Int? = nil,
        source: HookSource? = nil
    ) {
        self.id = id
        self.type = type
        self.event = event
        self.command = command
        self.url = url
        self.matcher = matcher
        self.conditionFilter = conditionFilter
        self.shell = shell
        self.prompt = prompt
        self.model = model
        self.headers = headers
        self.allowedEnvVars = allowedEnvVars
        self.statusMessage = statusMessage
        self.once = once
        self.async = async
        self.asyncRewake = asyncRewake
        self.timeout = timeout
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, type, event, command, url, matcher, shell, prompt, model, source
        case headers, timeout, once, async, asyncRewake, statusMessage
        case conditionFilter = "if"
        case allowedEnvVars
    }
}

/// Hook events matching Claude Code's HOOK_EVENTS (27 total).
/// Maps to CC's PascalCase event names sent over stdin/environment.
public enum HookEvent: String, Codable, Sendable, CaseIterable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case notification = "Notification"
    case userPromptSubmit = "UserPromptSubmit"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case permissionRequest = "PermissionRequest"
    case permissionDenied = "PermissionDenied"
    case setup = "Setup"
    case teammateIdle = "TeammateIdle"
    case taskCreated = "TaskCreated"
    case taskCompleted = "TaskCompleted"
    case elicitation = "Elicitation"
    case elicitationResult = "ElicitationResult"
    case configChange = "ConfigChange"
    case worktreeCreate = "WorktreeCreate"
    case worktreeRemove = "WorktreeRemove"
    case instructionsLoaded = "InstructionsLoaded"
    case cwdChanged = "CwdChanged"
    case fileChanged = "FileChanged"
}

// MARK: - Settings Sub-Types

/// Custom file suggestion configuration for @ mentions.
public struct FileSuggestionConfig: Codable, Sendable {
    public var type: String = "command"
    public var command: String

    public init(type: String = "command", command: String) {
        self.type = type
        self.command = command
    }
}

/// Attribution configuration for commits and PRs.
public struct AttributionConfig: Codable, Sendable {
    public var commit: String?
    public var pr: String?

    public init(commit: String? = nil, pr: String? = nil) {
        self.commit = commit
        self.pr = pr
    }
}

/// Permission rules configuration (mirrors CC's permissions object).
public struct PermissionsConfig: Codable, Sendable {
    public var allow: [String]?
    public var deny: [String]?
    public var ask: [String]?
    public var defaultMode: PermissionMode?
    /// CC uses string literal "disable" for this field. Set to "disable" to disable.
    public var disableBypassPermissionsMode: String?
    /// CC uses string literal "disable" for this field. Set to "disable" to disable.
    public var disableAutoMode: String?
    public var additionalDirectories: [String]?

    public init(
        allow: [String]? = nil,
        deny: [String]? = nil,
        ask: [String]? = nil,
        defaultMode: PermissionMode? = nil,
        disableBypassPermissionsMode: String? = nil,
        disableAutoMode: String? = nil,
        additionalDirectories: [String]? = nil
    ) {
        self.allow = allow
        self.deny = deny
        self.ask = ask
        self.defaultMode = defaultMode
        self.disableBypassPermissionsMode = disableBypassPermissionsMode
        self.disableAutoMode = disableAutoMode
        self.additionalDirectories = additionalDirectories
    }
}

/// Per-plugin entry configuration overrides.
/// Matches CC's SettingsPluginEntry config field.
public struct PluginEntryConfig: Codable, Sendable {
    public var version: String?
    public var enabled: Bool?
    public var config: [String: String]?

    public init(version: String? = nil, enabled: Bool? = nil, config: [String: String]? = nil) {
        self.version = version
        self.enabled = enabled
        self.config = config
    }
}

/// Per-plugin configuration entry for `pluginConfigs` map.
/// Matches CC's pluginConfigs record: `{ [pluginId]: { mcpServers?, options? } }`.
public struct PluginConfigEntry: Codable, Sendable {
    public var mcpServers: [String: MCPServerConfig]?
    public var options: [String: String]?

    public init(
        mcpServers: [String: MCPServerConfig]? = nil,
        options: [String: String]? = nil
    ) {
        self.mcpServers = mcpServers
        self.options = options
    }
}

/// Status line configuration. Matches CC's statusLine setting.
public struct StatusLineConfig: Codable, Sendable {
    public var type: String?
    public var command: String?
    /// Extra newline padding below the status line. Matches CC's `padding` field.
    public var padding: Int?

    public init(type: String? = nil, command: String? = nil, padding: Int? = nil) {
        self.type = type
        self.command = command
        self.padding = padding
    }
}

/// Agent settings (subagent types and configuration).
public struct AgentSettingsConfig: Codable, Sendable {
    public var allowedAgentTypes: [String]?
    public var defaultAgentType: String?
    public var maxSubagents: Int?

    public init(
        allowedAgentTypes: [String]? = nil,
        defaultAgentType: String? = nil,
        maxSubagents: Int? = nil
    ) {
        self.allowedAgentTypes = allowedAgentTypes
        self.defaultAgentType = defaultAgentType
        self.maxSubagents = maxSubagents
    }
}

/// Worktree configuration.
public struct WorktreeConfig: Codable, Sendable {
    public var enabled: Bool?
    public var command: String?

    public init(enabled: Bool? = nil, command: String? = nil) {
        self.enabled = enabled
        self.command = command
    }
}

/// Auto mode classifier configuration. Matches CC's autoMode object.
public struct AutoModeConfig: Codable, Sendable {
    public var allow: [String]?
    public var softDeny: [String]?
    public var deny: [String]?
    public var environment: [String: String]?

    public init(
        allow: [String]? = nil,
        softDeny: [String]? = nil,
        deny: [String]? = nil,
        environment: [String: String]? = nil
    ) {
        self.allow = allow
        self.softDeny = softDeny
        self.deny = deny
        self.environment = environment
    }

    enum CodingKeys: String, CodingKey {
        case allow
        case softDeny = "soft_deny"
        case deny
        case environment
    }
}

/// SSH connection configuration. Matches CC's sshConfigs entries.
public struct SSHConfig: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var sshHost: String
    public var sshPort: Int?
    public var sshIdentityFile: String?
    public var startDirectory: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        sshHost: String,
        sshPort: Int? = nil,
        sshIdentityFile: String? = nil,
        startDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshIdentityFile = sshIdentityFile
        self.startDirectory = startDirectory
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case sshHost = "sshHost"
        case sshPort = "sshPort"
        case sshIdentityFile = "sshIdentityFile"
        case startDirectory = "startDirectory"
    }
}

/// Remote session configuration. Matches CC's remote field.
public struct RemoteConfig: Codable, Sendable {
    public var defaultEnvironmentId: String?

    public init(defaultEnvironmentId: String? = nil) {
        self.defaultEnvironmentId = defaultEnvironmentId
    }

    enum CodingKeys: String, CodingKey {
        case defaultEnvironmentId = "defaultEnvironmentId"
    }
}

/// Custom spinner verb customization. Matches CC's spinnerVerbs field.
public struct SpinnerVerbsConfig: Codable, Sendable {
    public var mode: String  // "append" | "replace"
    public var verbs: [String]

    public init(mode: String = "append", verbs: [String] = []) {
        self.mode = mode
        self.verbs = verbs
    }
}

/// Custom spinner tips override. Matches CC's spinnerTipsOverride field.
public struct SpinnerTipsOverrideConfig: Codable, Sendable {
    public var excludeDefault: Bool?
    public var tips: [String]

    public init(excludeDefault: Bool? = nil, tips: [String] = []) {
        self.excludeDefault = excludeDefault
        self.tips = tips
    }
}

// MARK: - Model Key & Canonical Model Table

/// Short key identifying a Claude model family+version.
/// Matches Claude Code's ModelKey (keyof ALL_MODEL_CONFIGS) in utils/model/configs.ts.
public enum ModelKey: String, Codable, Sendable, CaseIterable {
    case haiku35
    case haiku45
    case sonnet35
    case sonnet37
    case sonnet40
    case sonnet45
    case sonnet46
    case opus40
    case opus41
    case opus45
    case opus46

    /// Resolve to the canonical first-party model ID.
    public var canonicalID: String {
        guard let config = ALL_MODEL_CONFIGS[self] else { return "" }
        return config.firstParty
    }
}

/// Model ID strings for each provider.
/// Matches Claude Code's ModelConfig = Record<APIProvider, ModelName> in utils/model/configs.ts.
public struct ModelProviderConfig: Codable, Sendable {
    public let firstParty: String
    public let bedrock: String
    public let vertex: String
    public let foundry: String

    public init(firstParty: String, bedrock: String, vertex: String, foundry: String) {
        self.firstParty = firstParty
        self.bedrock = bedrock
        self.vertex = vertex
        self.foundry = foundry
    }
}

/// All known Claude model configurations keyed by ModelKey.
/// Matches Claude Code's ALL_MODEL_CONFIGS in utils/model/configs.ts.
public let ALL_MODEL_CONFIGS: [ModelKey: ModelProviderConfig] = [
    .haiku35: ModelProviderConfig(
        firstParty: "claude-3-5-haiku-20241022",
        bedrock: "us.anthropic.claude-3-5-haiku-20241022-v1:0",
        vertex: "claude-3-5-haiku@20241022",
        foundry: "claude-3-5-haiku"
    ),
    .haiku45: ModelProviderConfig(
        firstParty: "claude-haiku-4-5-20251001",
        bedrock: "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        vertex: "claude-haiku-4-5@20251001",
        foundry: "claude-haiku-4-5"
    ),
    .sonnet35: ModelProviderConfig(
        firstParty: "claude-3-5-sonnet-20241022",
        bedrock: "anthropic.claude-3-5-sonnet-20241022-v2:0",
        vertex: "claude-3-5-sonnet-v2@20241022",
        foundry: "claude-3-5-sonnet"
    ),
    .sonnet37: ModelProviderConfig(
        firstParty: "claude-3-7-sonnet-20250219",
        bedrock: "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
        vertex: "claude-3-7-sonnet@20250219",
        foundry: "claude-3-7-sonnet"
    ),
    .sonnet40: ModelProviderConfig(
        firstParty: "claude-sonnet-4-20250514",
        bedrock: "us.anthropic.claude-sonnet-4-20250514-v1:0",
        vertex: "claude-sonnet-4@20250514",
        foundry: "claude-sonnet-4"
    ),
    .sonnet45: ModelProviderConfig(
        firstParty: "claude-sonnet-4-5-20250929",
        bedrock: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        vertex: "claude-sonnet-4-5@20250929",
        foundry: "claude-sonnet-4-5"
    ),
    .sonnet46: ModelProviderConfig(
        firstParty: "claude-sonnet-4-6",
        bedrock: "us.anthropic.claude-sonnet-4-6",
        vertex: "claude-sonnet-4-6",
        foundry: "claude-sonnet-4-6"
    ),
    .opus40: ModelProviderConfig(
        firstParty: "claude-opus-4-20250514",
        bedrock: "us.anthropic.claude-opus-4-20250514-v1:0",
        vertex: "claude-opus-4@20250514",
        foundry: "claude-opus-4"
    ),
    .opus41: ModelProviderConfig(
        firstParty: "claude-opus-4-1-20250805",
        bedrock: "us.anthropic.claude-opus-4-1-20250805-v1:0",
        vertex: "claude-opus-4-1@20250805",
        foundry: "claude-opus-4-1"
    ),
    .opus45: ModelProviderConfig(
        firstParty: "claude-opus-4-5-20251101",
        bedrock: "us.anthropic.claude-opus-4-5-20251101-v1:0",
        vertex: "claude-opus-4-5@20251101",
        foundry: "claude-opus-4-5"
    ),
    .opus46: ModelProviderConfig(
        firstParty: "claude-opus-4-6",
        bedrock: "us.anthropic.claude-opus-4-6-v1",
        vertex: "claude-opus-4-6",
        foundry: "claude-opus-4-6"
    ),
]

/// Canonical model ID list (all first-party model IDs).
/// Matches CC's CANONICAL_MODEL_IDS in utils/model/configs.ts.
public let CANONICAL_MODEL_IDS: [String] = ALL_MODEL_CONFIGS.values.map(\.firstParty)
