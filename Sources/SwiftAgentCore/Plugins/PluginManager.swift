import Foundation

// MARK: - Plugin Author

/// Plugin author information matching CC's PluginAuthor.
public struct PluginAuthor: Sendable, Codable {
    public let name: String
    public let email: String?
    public let url: String?

    public init(name: String, email: String? = nil, url: String? = nil) {
        self.name = name
        self.email = email
        self.url = url
    }
}

// MARK: - Plugin Repository

/// Plugin repository configuration. Matches CC's PluginRepository.
public struct PluginRepository: Sendable, Codable {
    public let url: String
    public let branch: String
    public let lastUpdated: String?
    public let commitSha: String?

    public init(url: String, branch: String = "main", lastUpdated: String? = nil, commitSha: String? = nil) {
        self.url = url
        self.branch = branch
        self.lastUpdated = lastUpdated
        self.commitSha = commitSha
    }
}

// MARK: - Plugin Component

/// Plugin component identifiers. Matches CC's PluginComponent.
public enum PluginComponent: String, Sendable, Codable, CaseIterable {
    case commands
    case agents
    case skills
    case hooks
    case outputStyles = "output-styles"
}

// MARK: - Plugin Manifest

/// Plugin manifest matching CC's PluginManifest (plugin.json).
public struct PluginManifest: Sendable, Codable {
    public let name: String
    public let version: String?
    public let description: String?
    public let author: PluginAuthor?
    public let homepage: String?
    public let repository: String?
    public let license: String?
    public let keywords: [String]?
    public let icon: String?
    public let provider: String?
    public let dependencies: [String]?
    public let hooks: [String]?
    public let commands: [String]?
    public let commandPaths: [String]?
    public let commandsMetadata: [String: CommandMetadata]?
    public let agents: [String]?
    public let agentPaths: [String]?
    public let skills: [String]?
    public let skillPaths: [String]?
    public let outputStyles: [String]?
    public let outputStylesPaths: [String]?
    public let mcpServers: [String: JSONValue]?
    public let lspServers: [String: JSONValue]?
    public let settings: [String: JSONValue]?
    public let userConfig: [String: PluginUserConfigOption]?
    /// Glob patterns for file paths this plugin applies to.
    public let paths: [String]?

    public init(
        name: String,
        version: String? = nil,
        description: String? = nil,
        author: PluginAuthor? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        license: String? = nil,
        keywords: [String]? = nil,
        icon: String? = nil,
        provider: String? = nil,
        dependencies: [String]? = nil,
        hooks: [String]? = nil,
        commands: [String]? = nil,
        commandPaths: [String]? = nil,
        commandsMetadata: [String: CommandMetadata]? = nil,
        agents: [String]? = nil,
        agentPaths: [String]? = nil,
        skills: [String]? = nil,
        skillPaths: [String]? = nil,
        outputStyles: [String]? = nil,
        outputStylesPaths: [String]? = nil,
        mcpServers: [String: JSONValue]? = nil,
        lspServers: [String: JSONValue]? = nil,
        settings: [String: JSONValue]? = nil,
        userConfig: [String: PluginUserConfigOption]? = nil,
        paths: [String]? = nil
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.homepage = homepage
        self.repository = repository
        self.license = license
        self.keywords = keywords
        self.icon = icon
        self.provider = provider
        self.dependencies = dependencies
        self.hooks = hooks
        self.commands = commands
        self.commandPaths = commandPaths
        self.commandsMetadata = commandsMetadata
        self.agents = agents
        self.agentPaths = agentPaths
        self.skills = skills
        self.skillPaths = skillPaths
        self.outputStyles = outputStyles
        self.outputStylesPaths = outputStylesPaths
        self.mcpServers = mcpServers
        self.lspServers = lspServers
        self.settings = settings
        self.userConfig = userConfig
        self.paths = paths
    }

    enum CodingKeys: String, CodingKey {
        case name, version, description, author, homepage, repository, license, icon, provider
        case keywords, dependencies, hooks, commands, agents, skills, paths
        case commandPaths = "commandPaths"
        case commandsMetadata = "commandsMetadata"
        case agentPaths = "agentPaths"
        case skillPaths = "skillPaths"
        case outputStyles = "output-styles"
        case outputStylesPaths = "outputStylesPaths"
        case mcpServers = "mcpServers"
        case lspServers = "lspServers"
        case settings
        case userConfig = "userConfig"
    }
}

/// Command metadata for named commands from object-mapping format.
/// Matches CC's CommandMetadata from plugins/schemas.ts.
public struct CommandMetadata: Sendable, Codable {
    public let description: String?
    public let argumentHint: String?
    public let whenToUse: String?

    public init(description: String? = nil, argumentHint: String? = nil, whenToUse: String? = nil) {
        self.description = description
        self.argumentHint = argumentHint
        self.whenToUse = whenToUse
    }
}

/// User-configurable plugin option matching CC's PluginUserConfigOptionSchema.
public struct PluginUserConfigOption: Sendable, Codable {
    public let type: PluginConfigOptionType
    public let title: String
    public let description: String
    public let `required`: Bool?
    public let `default`: JSONValue?
    public let multiple: Bool?
    public let sensitive: Bool?
    public let min: Double?
    public let max: Double?

    public init(
        type: PluginConfigOptionType,
        title: String,
        description: String,
        required: Bool? = nil,
        default: JSONValue? = nil,
        multiple: Bool? = nil,
        sensitive: Bool? = nil,
        min: Double? = nil,
        max: Double? = nil
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.required = required
        self.default = `default`
        self.multiple = multiple
        self.sensitive = sensitive
        self.min = min
        self.max = max
    }
}

public enum PluginConfigOptionType: String, Sendable, Codable {
    case string
    case number
    case boolean
    case directory
    case file
}

// MARK: - Builtin Plugin Definition

/// Definition for a built-in plugin that ships with the CLI.
/// Matches CC's BuiltinPluginDefinition.
public struct BuiltinPluginDefinition: Sendable {
    public let name: String
    public let description: String
    public let version: String?
    public let skills: [BundledSkillDefinition]?
    public let hooks: [String: JSONValue]?
    public let mcpServers: [String: JSONValue]?
    public let isAvailable: @Sendable () -> Bool
    public let defaultEnabled: Bool

    public init(
        name: String,
        description: String,
        version: String? = nil,
        skills: [BundledSkillDefinition]? = nil,
        hooks: [String: JSONValue]? = nil,
        mcpServers: [String: JSONValue]? = nil,
        isAvailable: @escaping @Sendable () -> Bool = { true },
        defaultEnabled: Bool = true
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.skills = skills
        self.hooks = hooks
        self.mcpServers = mcpServers
        self.isAvailable = isAvailable
        self.defaultEnabled = defaultEnabled
    }
}

/// Bundled skill definition used by built-in plugins.
public struct BundledSkillDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let path: String

    public init(name: String, description: String, path: String) {
        self.name = name
        self.description = description
        self.path = path
    }
}

// MARK: - Plugin Config

/// Plugin configuration with repositories. Matches CC's PluginConfig.
public struct PluginConfig: Sendable, Codable {
    public let repositories: [String: PluginRepository]

    public init(repositories: [String: PluginRepository] = [:]) {
        self.repositories = repositories
    }
}

// MARK: - Loaded Plugin

/// A loaded plugin with all metadata and component paths.
/// Matches CC's LoadedPlugin.
public struct LoadedPlugin: Sendable {
    public let name: String
    public let manifest: PluginManifest
    public let path: String
    public let source: String
    public let repository: String
    public let enabled: Bool
    public let isBuiltin: Bool
    public let sha: String?
    public let commandsPath: String?
    public let commandsPaths: [String]?
    public let commandsMetadata: [String: CommandMetadata]?
    public let agentsPath: String?
    public let agentsPaths: [String]?
    public let skillsPath: String?
    public let skillsPaths: [String]?
    public let outputStylesPath: String?
    public let outputStylesPaths: [String]?
    public let hooksConfig: [String: JSONValue]?
    public let mcpServers: [String: JSONValue]?
    public let lspServers: [String: JSONValue]?
    public let settings: [String: JSONValue]?

    public init(
        name: String,
        manifest: PluginManifest,
        path: String,
        source: String,
        repository: String,
        enabled: Bool = true,
        isBuiltin: Bool = false,
        sha: String? = nil,
        commandsPath: String? = nil,
        commandsPaths: [String]? = nil,
        commandsMetadata: [String: CommandMetadata]? = nil,
        agentsPath: String? = nil,
        agentsPaths: [String]? = nil,
        skillsPath: String? = nil,
        skillsPaths: [String]? = nil,
        outputStylesPath: String? = nil,
        outputStylesPaths: [String]? = nil,
        hooksConfig: [String: JSONValue]? = nil,
        mcpServers: [String: JSONValue]? = nil,
        lspServers: [String: JSONValue]? = nil,
        settings: [String: JSONValue]? = nil
    ) {
        self.name = name
        self.manifest = manifest
        self.path = path
        self.source = source
        self.repository = repository
        self.enabled = enabled
        self.isBuiltin = isBuiltin
        self.sha = sha
        self.commandsPath = commandsPath
        self.commandsPaths = commandsPaths
        self.commandsMetadata = commandsMetadata
        self.agentsPath = agentsPath
        self.agentsPaths = agentsPaths
        self.skillsPath = skillsPath
        self.skillsPaths = skillsPaths
        self.outputStylesPath = outputStylesPath
        self.outputStylesPaths = outputStylesPaths
        self.hooksConfig = hooksConfig
        self.mcpServers = mcpServers
        self.lspServers = lspServers
        self.settings = settings
    }
}

// MARK: - Plugin Error (25 variants matching CC)

/// Plugin error discriminated union — 25 variants matching CC's PluginError.
public enum PluginErrorType: String, Sendable, Codable, CaseIterable {
    case pathNotFound = "path-not-found"
    case gitAuthFailed = "git-auth-failed"
    case gitTimeout = "git-timeout"
    case networkError = "network-error"
    case manifestParseError = "manifest-parse-error"
    case manifestValidationError = "manifest-validation-error"
    case pluginNotFound = "plugin-not-found"
    case marketplaceNotFound = "marketplace-not-found"
    case marketplaceLoadFailed = "marketplace-load-failed"
    case mcpConfigInvalid = "mcp-config-invalid"
    case mcpServerSuppressedDuplicate = "mcp-server-suppressed-duplicate"
    case lspConfigInvalid = "lsp-config-invalid"
    case hookLoadFailed = "hook-load-failed"
    case componentLoadFailed = "component-load-failed"
    case mcpbDownloadFailed = "mcpb-download-failed"
    case mcpbExtractFailed = "mcpb-extract-failed"
    case mcpbInvalidManifest = "mcpb-invalid-manifest"
    case lspServerStartFailed = "lsp-server-start-failed"
    case lspServerCrashed = "lsp-server-crashed"
    case lspRequestTimeout = "lsp-request-timeout"
    case lspRequestFailed = "lsp-request-failed"
    case marketplaceBlockedByPolicy = "marketplace-blocked-by-policy"
    case dependencyUnsatisfied = "dependency-unsatisfied"
    case pluginCacheMiss = "plugin-cache-miss"
    case genericError = "generic-error"
}

/// Structured plugin error matching CC's PluginError discriminated union.
public struct StructuredPluginError: Sendable, Error {
    public let type: PluginErrorType
    public let source: String
    public let plugin: String?
    // Context-specific fields
    public let path: String?
    public let component: PluginComponent?
    public let gitUrl: String?
    public let authType: String?
    public let operation: String?
    public let url: String?
    public let details: String?
    public let manifestPath: String?
    public let parseError: String?
    public let validationErrors: [String]?
    public let validationError: String?
    public let pluginId: String?
    public let marketplace: String?
    public let availableMarketplaces: [String]?
    public let reason: String?
    public let serverName: String?
    public let duplicateOf: String?
    public let hookPath: String?
    public let mcpbPath: String?
    public let exitCode: Int?
    public let signal: String?
    public let method: String?
    public let timeoutMs: Int?
    public let error: String?
    public let blockedByBlocklist: Bool?
    public let allowedSources: [String]?
    public let dependency: String?
    public let dependencyReason: String?
    public let installPath: String?

    /// Convenience init for error reporting without requiring all optional fields.
    public init(
        type: PluginErrorType,
        source: String,
        plugin: String? = nil,
        path: String? = nil,
        reason: String? = nil
    ) {
        self.type = type
        self.source = source
        self.plugin = plugin
        self.path = path
        self.reason = reason
        self.component = nil
        self.gitUrl = nil
        self.authType = nil
        self.operation = nil
        self.url = nil
        self.details = nil
        self.manifestPath = nil
        self.parseError = nil
        self.validationErrors = nil
        self.validationError = nil
        self.pluginId = nil
        self.marketplace = nil
        self.availableMarketplaces = nil
        self.serverName = nil
        self.duplicateOf = nil
        self.hookPath = nil
        self.mcpbPath = nil
        self.exitCode = nil
        self.signal = nil
        self.method = nil
        self.timeoutMs = nil
        self.error = nil
        self.blockedByBlocklist = nil
        self.allowedSources = nil
        self.dependency = nil
        self.dependencyReason = nil
        self.installPath = nil
    }

    public var localizedDescription: String {
        switch type {
        case .genericError: return error ?? "Unknown error"
        case .pathNotFound: return "Path not found: \(path ?? "") (\(component?.rawValue ?? ""))"
        case .gitAuthFailed: return "Git authentication failed (\(authType ?? "")): \(gitUrl ?? "")"
        case .gitTimeout: return "Git \(operation ?? "") timeout: \(gitUrl ?? "")"
        case .networkError: return "Network error: \(url ?? "")\(details.map { " - \($0)" } ?? "")"
        case .manifestParseError: return "Manifest parse error: \(parseError ?? "")"
        case .manifestValidationError: return "Manifest validation failed: \(validationErrors?.joined(separator: ", ") ?? "")"
        case .pluginNotFound: return "Plugin \(pluginId ?? "") not found in marketplace \(marketplace ?? "")"
        case .marketplaceNotFound: return "Marketplace \(marketplace ?? "") not found"
        case .marketplaceLoadFailed: return "Marketplace \(marketplace ?? "") failed to load: \(reason ?? "")"
        case .mcpConfigInvalid: return "MCP server \(serverName ?? "") invalid: \(validationError ?? "")"
        case .mcpServerSuppressedDuplicate: return "MCP server \"\(serverName ?? "")\" skipped — duplicate of \(duplicateOf ?? "")"
        case .hookLoadFailed: return "Hook load failed: \(reason ?? "")"
        case .componentLoadFailed: return "\(component?.rawValue ?? "") load failed from \(path ?? ""): \(reason ?? "")"
        case .mcpbDownloadFailed: return "Failed to download MCPB from \(url ?? ""): \(reason ?? "")"
        case .mcpbExtractFailed: return "Failed to extract MCPB \(mcpbPath ?? ""): \(reason ?? "")"
        case .mcpbInvalidManifest: return "MCPB manifest invalid at \(mcpbPath ?? ""): \(validationError ?? "")"
        case .lspConfigInvalid: return "Plugin \"\(plugin ?? "")\" has invalid LSP server config for \"\(serverName ?? "")\": \(validationError ?? "")"
        case .lspServerStartFailed: return "Plugin \"\(plugin ?? "")\" failed to start LSP server \"\(serverName ?? "")\": \(reason ?? "")"
        case .lspServerCrashed:
            if let sig = signal { return "Plugin \"\(plugin ?? "")\" LSP server \"\(serverName ?? "")\" crashed with signal \(sig)" }
            return "Plugin \"\(plugin ?? "")\" LSP server \"\(serverName ?? "")\" crashed with exit code \(exitCode.map(String.init) ?? "unknown")"
        case .lspRequestTimeout: return "Plugin \"\(plugin ?? "")\" LSP server \"\(serverName ?? "")\" timed out on \(method ?? "") request after \(timeoutMs ?? 0)ms"
        case .lspRequestFailed: return "Plugin \"\(plugin ?? "")\" LSP server \"\(serverName ?? "")\" \(method ?? "") request failed: \(error ?? "")"
        case .marketplaceBlockedByPolicy:
            if blockedByBlocklist == true { return "Marketplace '\(marketplace ?? "")' is blocked by enterprise policy" }
            return "Marketplace '\(marketplace ?? "")' is not in the allowed marketplace list"
        case .dependencyUnsatisfied:
            return "Dependency \"\(dependency ?? "")\" is \(dependencyReason == "not-enabled" ? "disabled — enable it or remove the dependency" : "not found in any configured marketplace")"
        case .pluginCacheMiss: return "Plugin \"\(plugin ?? "")\" not cached at \(installPath ?? "") — run /plugins to refresh"
        }
    }
}

// MARK: - Plugin Load Result

/// Result of loading plugins. Matches CC's PluginLoadResult.
public struct PluginLoadResult: Sendable {
    public let enabled: [LoadedPlugin]
    public let disabled: [LoadedPlugin]
    public let errors: [StructuredPluginError]

    public init(enabled: [LoadedPlugin] = [], disabled: [LoadedPlugin] = [], errors: [StructuredPluginError] = []) {
        self.enabled = enabled
        self.disabled = disabled
        self.errors = errors
    }
}

// MARK: - Plugin Manager

/// Plugin loading and lifecycle management.
/// Matches Claude Code's pluginLoader.ts and pluginDirectories.ts.
public actor PluginManager {
    private var plugins: [String: PluginManifest] = [:]
    private var loadedPlugins: [String: LoadedPlugin] = [:]

    public init() {}

    /// Load a plugin from a plugin directory.
    /// Expects a `plugin.json` at the plugin root (matching CC convention).
    public func load(from directory: URL) throws -> PluginManifest {
        // Try .claude-plugin/plugin.json first (CC convention), then plugin.json, then manifest.json (legacy)
        let claudePluginJSON = directory.appendingPathComponent(".claude-plugin/plugin.json")
        let pluginJSON = directory.appendingPathComponent("plugin.json")
        let manifestJSON = directory.appendingPathComponent("manifest.json")

        let manifestURL: URL
        if FileManager.default.fileExists(atPath: claudePluginJSON.path) {
            manifestURL = claudePluginJSON
        } else if FileManager.default.fileExists(atPath: pluginJSON.path) {
            manifestURL = pluginJSON
        } else if FileManager.default.fileExists(atPath: manifestJSON.path) {
            manifestURL = manifestJSON
        } else {
            throw PluginManagerError.manifestNotFound(directory.path)
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

        plugins[manifest.name] = manifest
        return manifest
    }

    /// Scan a plugins root directory for subdirectories containing plugin manifests.
    /// Returns all discovered plugin manifests. Matching CC's plugin discovery pattern.
    public func scanPluginsDirectory(_ rootURL: URL) -> [PluginManifest] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var discovered: [PluginManifest] = []
        for url in contents {
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            if let manifest = try? load(from: url) {
                discovered.append(manifest)
            }
        }
        return discovered
    }

    /// Create a LoadedPlugin from a directory path, auto-detecting component paths.
    /// Matching CC's createPluginFromPath pattern.
    public func createPluginFromPath(_ pluginPath: URL, source: String = "user") throws -> LoadedPlugin {
        let manifest = try load(from: pluginPath)

        let path = pluginPath.path
        let fm = FileManager.default

        // Auto-detect component directories (matching CC's createPluginFromPath)
        func dirExists(_ name: String) -> Bool {
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(name))
        }

        let commandsPath: String? = dirExists("commands") ? (path as NSString).appendingPathComponent("commands") : nil
        let agentsPath: String? = dirExists("agents") ? (path as NSString).appendingPathComponent("agents") : nil
        let skillsPath: String? = dirExists("skills") ? (path as NSString).appendingPathComponent("skills") : nil
        let outputStylesPath: String? = dirExists("output-styles") ? (path as NSString).appendingPathComponent("output-styles") : nil

        // Collect component file paths
        var commandsPaths: [String] = []
        var agentsPaths: [String] = []
        var skillsPaths: [String] = []
        var outputStylesPaths: [String] = []

        if let cmdPath = commandsPath {
            commandsPaths = scanMarkdownFiles(in: cmdPath)
        }
        if let agentPath = agentsPath {
            agentsPaths = scanMarkdownFiles(in: agentPath)
        }
        if let skillPath = skillsPath {
            skillsPaths = scanMarkdownFiles(in: skillPath) + scanSkillDirectories(in: skillPath)
        }
        if let osPath = outputStylesPath {
            outputStylesPaths = scanMarkdownFiles(in: osPath)
        }

        let repo = URL(string: manifest.repository ?? "")?.lastPathComponent ?? "unknown"

        let loaded = LoadedPlugin(
            name: manifest.name,
            manifest: manifest,
            path: path,
            source: source,
            repository: repo,
            enabled: true,
            isBuiltin: false,
            commandsPath: commandsPath,
            commandsPaths: commandsPaths.isEmpty ? nil : commandsPaths,
            agentsPath: agentsPath,
            agentsPaths: agentsPaths.isEmpty ? nil : agentsPaths,
            skillsPath: skillsPath,
            skillsPaths: skillsPaths.isEmpty ? nil : skillsPaths,
            outputStylesPath: outputStylesPath,
            outputStylesPaths: outputStylesPaths.isEmpty ? nil : outputStylesPaths
        )

        loadedPlugins[manifest.name] = loaded
        return loaded
    }

    /// Load all plugins from the standard plugins directory (~/.claude/plugins).
    public func loadAllPlugins(from rootURL: URL) -> PluginLoadResult {
        var enabled: [LoadedPlugin] = []
        var disabled: [LoadedPlugin] = []
        var errors: [StructuredPluginError] = []

        let manifests = scanPluginsDirectory(rootURL)

        for manifest in manifests {
            let pluginDir = rootURL.appendingPathComponent(manifest.name)
            do {
                let loaded = try createPluginFromPath(pluginDir)
                if loaded.enabled {
                    enabled.append(loaded)
                } else {
                    disabled.append(loaded)
                }
            } catch {
                errors.append(StructuredPluginError(
                    type: .componentLoadFailed,
                    source: "scanner",
                    plugin: manifest.name,
                    path: pluginDir.path,
                    reason: error.localizedDescription
                ))
            }
        }

        return PluginLoadResult(enabled: enabled, disabled: disabled, errors: errors)
    }

    /// Scan a directory for .md files.
    private func scanMarkdownFiles(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return contents
            .filter { $0.hasSuffix(".md") }
            .map { (directory as NSString).appendingPathComponent($0) }
    }

    /// Scan for skill directories (subdirectories containing SKILL.md).
    private func scanSkillDirectories(in skillsPath: String) -> [String] {
        let skillsURL = URL(fileURLWithPath: skillsPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: skillsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var skillPaths: [String] = []
        for url in contents {
            let resolvedURL = url.resolvingSymlinksInPath()
            let resourceValues = try? resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }
            let skillMD = resolvedURL.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMD.path) {
                skillPaths.append(skillMD.path)
            }
        }
        return skillPaths
    }

    /// Get a loaded plugin by name (includes runtime metadata).
    public func getLoaded(name: String) -> LoadedPlugin? {
        loadedPlugins[name]
    }

    /// List all loaded plugins with runtime metadata.
    public func listLoaded() -> [LoadedPlugin] {
        Array(loadedPlugins.values)
    }

    /// Unload a plugin by name.
    public func unload(name: String) {
        plugins.removeValue(forKey: name)
    }

    /// Get a loaded plugin by name.
    public func get(name: String) -> PluginManifest? {
        plugins[name]
    }

    /// List all loaded plugins.
    public func listAll() -> [PluginManifest] {
        Array(plugins.values)
    }

    /// Validate a plugin manifest.
    public static func validate(_ manifest: PluginManifest) -> [String] {
        var issues: [String] = []
        if manifest.name.isEmpty { issues.append("name is empty") }
        if manifest.name.contains(" ") { issues.append("name must not contain spaces (use kebab-case)") }
        return issues
    }
}

/// Error type for PluginManager operations (kept simple — StructuredPluginError for detailed errors).
public enum PluginManagerError: Error, Sendable {
    case manifestNotFound(String)
    case invalidManifest(String)
}
