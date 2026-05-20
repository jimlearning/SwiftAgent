import Foundation

/// Effort levels for agent and prompt execution. Matches CC's EffortLevel.
/// From utils/effort.ts:11.
public enum EffortLevel: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
    case max
}

/// Effort value: either a named level or a numeric value. Matches CC's EffortValue.
public enum EffortValue: Codable, Sendable, Equatable {
    case level(EffortLevel)
    case number(Int)
}

extension EffortValue {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .number(int)
        } else {
            let str = try container.decode(String.self)
            guard let level = EffortLevel(rawValue: str) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown effort value: \(str)")
            }
            self = .level(level)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .level(let l): try container.encode(l.rawValue)
        case .number(let n): try container.encode(n)
        }
    }
}

/// Agent definition matching Claude Code's AgentDefinition (BaseAgentDefinition + BuiltInAgentDefinition).
/// Stored in BuiltInAgents registry, ~/.claude/agents/, and project .claude/agents/.
public struct AgentDefinition: Codable, Sendable, Identifiable {
    /// Unique identifier (UUID or agentType for built-ins).
    public let id: String
    /// Agent type name (e.g. "general-purpose", "Explore", "Plan"). Matches CC's agentType.
    public let name: String
    /// When-to-use guidance for the model. Matches CC's whenToUse.
    public let description: String
    /// System prompt. Stored pre-computed; getSystemPrompt() matches CC's lazy evaluation API.
    public let systemPrompt: String

    /// CC API parity: CC uses getSystemPrompt(): string — a lazy evaluation function.
    /// SA stores a pre-computed string and returns it via this method.
    public func getSystemPrompt() -> String { systemPrompt }
    /// Tools available to this agent. nil or ["*"] means all tools.
    /// Matches CC's tools field.
    public let tools: [String]?
    /// Tools explicitly disallowed. Matches CC's disallowedTools — inverted from allowedTools.
    /// Explore agent disallows Write, Edit, NotebookEdit, Agent, ExitPlanMode.
    public let disallowedTools: [String]?
    /// When true, CLAUDE.md is not loaded for this agent. Matches CC's omitClaudeMd.
    /// Explore agent sets this to true since it only needs fast search.
    public let omitClaudeMd: Bool
    /// Model override. nil means use default subagent model. Matches CC's model field.
    /// Built-in agents may use "inherit" to share the main agent's model.
    public let model: ModelConfig?
    /// Agent role classification. Matches CC's agentType categorization.
    public let role: AgentRole
    /// Source origin: "built-in", "user", "project", "managed". Matches CC's source.
    public let source: String?
    /// Base directory for relative paths. Matches CC's baseDir.
    public let baseDir: String?
    /// Skill names to preload. Matches CC's skills field.
    public let skills: [String]?
    /// Agent color identifier for UI. Matches CC's color.
    public let color: String?
    /// Maximum number of agentic turns. Matches CC's maxTurns.
    public let maxTurns: Int?
    /// Whether this agent always runs as a background task. Matches CC's background.
    public let background: Bool?
    /// Permission mode override for the agent. Matches CC's permissionMode.
    public let permissionMode: PermissionMode?
    /// Prepended to the first user turn. Matches CC's initialPrompt.
    public let initialPrompt: String?
    /// Effort level override for this agent. Matches CC's effort field.
    public let effort: EffortValue?
    /// Agent-specific MCP server configurations. Matches CC's mcpServers.
    public let mcpServers: [AgentMcpServerSpec]?
    /// Session-scoped hooks registered when agent starts. Matches CC's hooks.
    public let hooks: HooksSettings?
    /// Persistent memory scope for this agent. Matches CC's memory.
    public let memory: AgentMemoryScope?
    /// Sandbox isolation mode. Matches CC's isolation.
    public let isolation: String?
    /// Re-injected per-turn system reminder. Matches CC's criticalSystemReminder_EXPERIMENTAL.
    public let criticalSystemReminder: String?
    /// MCP servers required for this agent to run. Matches CC's requiredMcpServers.
    public let requiredMcpServers: [String]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        systemPrompt: String,
        tools: [String]? = nil,
        disallowedTools: [String]? = nil,
        omitClaudeMd: Bool = false,
        model: ModelConfig? = nil,
        role: AgentRole = .generalPurpose,
        source: String? = nil,
        baseDir: String? = nil,
        skills: [String]? = nil,
        color: String? = nil,
        maxTurns: Int? = nil,
        background: Bool? = nil,
        permissionMode: PermissionMode? = nil,
        initialPrompt: String? = nil,
        effort: EffortValue? = nil,
        mcpServers: [AgentMcpServerSpec]? = nil,
        hooks: HooksSettings? = nil,
        memory: AgentMemoryScope? = nil,
        isolation: String? = nil,
        criticalSystemReminder: String? = nil,
        requiredMcpServers: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.disallowedTools = disallowedTools
        self.omitClaudeMd = omitClaudeMd
        self.model = model
        self.role = role
        self.source = source
        self.baseDir = baseDir
        self.skills = skills
        self.color = color
        self.maxTurns = maxTurns
        self.background = background
        self.permissionMode = permissionMode
        self.initialPrompt = initialPrompt
        self.effort = effort
        self.mcpServers = mcpServers
        self.hooks = hooks
        self.memory = memory
        self.isolation = isolation
        self.criticalSystemReminder = criticalSystemReminder
        self.requiredMcpServers = requiredMcpServers
    }

    /// Returns effective tool list: all tools minus disallowed tools.
    /// When tools is nil or ["*"], uses all tool names from the caller-specified array.
    public func effectiveTools(allToolNames: [String]) -> [String] {
        let allowed: [String]
        if let t = tools, t != ["*"] {
            allowed = t
        } else {
            allowed = allToolNames
        }
        if let disallowed = disallowedTools {
            let disallowedSet = Set(disallowed)
            return allowed.filter { !disallowedSet.contains($0) }
        }
        return allowed
    }

    /// Legacy accessor for backward compatibility with code that used allowedTools.
    @available(*, deprecated, message: "Use effectiveTools(allToolNames:) instead")
    public var allowedTools: [String]? { tools }
}

public enum AgentRole: String, Codable, Sendable {
    case generalPurpose = "general-purpose"
    case explore = "Explore"
    case plan = "Plan"
    case verification = "verification"
    case custom
}

/// Agent memory scope matching CC's AgentMemoryScope from tools/AgentTool/agentMemory.ts.
/// CC: export type AgentMemoryScope = 'user' | 'project' | 'local'
public enum AgentMemoryScope: String, Codable, Sendable {
    case user
    case project
    case local
}

/// Agent-specific MCP server spec matching CC's AgentMcpServerSpec from loadAgentsDir.ts.
public struct AgentMcpServerSpec: Codable, Sendable {
    public let name: String
    public let command: String?
    public let args: [String]?
    public let env: [String: String]?
    public let url: String?
    public let headers: [String: String]?
    public let timeout: Int?
    public let trust: Bool?

    public init(
        name: String,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        url: String? = nil,
        headers: [String: String]? = nil,
        timeout: Int? = nil,
        trust: Bool? = nil
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.trust = trust
    }
}

/// Hooks settings type alias matching CC's HooksSettings from schemas/hooks.ts.
/// CC: Partial<Record<HookEvent, HookMatcher[]>>
public struct HooksSettings: Codable, Sendable {
    public let events: [String: [String]]  // HookEvent name → HookMatcher names

    public init(events: [String: [String]] = [:]) {
        self.events = events
    }
}

public struct AgentContext: Sendable {
    public let parentSessionId: String
    public let workingDirectory: String
    public let permissionMode: PermissionMode
    public let settings: Settings

    public init(
        parentSessionId: String,
        workingDirectory: String,
        permissionMode: PermissionMode = .default,
        settings: Settings = Settings()
    ) {
        self.parentSessionId = parentSessionId
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.settings = settings
    }
}
