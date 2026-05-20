import Foundation

/// Multi-source configuration loader with 5-layer merging.
/// Mirrors Claude Code's SETTING_SOURCES architecture.
///
/// Priority (low to high, per CC):
/// 1. userSettings    — ~/.claude/settings.json
/// 2. projectSettings — .claude/settings.json in project root
/// 3. localSettings   — .claude/settings.local.json (gitignored)
/// 4. flagSettings    — --settings CLI flag / flagFile
/// 5. policySettings  — managed-settings.json (remote, MDM/plist, HKCU)
///
/// Plugin settings are loaded separately (not in SETTING_SOURCES),
/// matching CC's pluginSettings management.
///
/// Merge strategy uses deep merge with per-key customization:
/// - extraAllowedTools: union (OR) across sources
/// - hooks: concatenated (append)
/// - enabledPlugins: union of arrays (dedup)
/// - mcpServers: deep merge by server name
/// - env: union with string dedup
/// - Scalars/objects: overlay wins (higher priority replaces)
public struct ConfigLoader: Sendable {
    /// Session-level settings cache. Matches CC's getSessionSettingsCache.
    private let sessionCache = ConfigSessionCache()

    public init() {}

    // MARK: - Main Load

    /// Load settings from all sources in CC's priority order.
    /// Plugin settings are loaded separately via `loadPluginSettings()`.
    public func load(
        userConfig: URL? = Self.defaultUserConfigPath(),
        projectConfig: URL? = Self.defaultProjectConfigPath(),
        localConfig: URL? = Self.defaultLocalConfigPath(),
        flagOverrides: Settings? = nil,
        flagFileURL: URL? = nil,
        policySettings: Settings? = nil,
        managedSettingsDir: URL? = nil
    ) throws -> Settings {
        // Check session cache first
        let cacheKey = cacheKeyFor(
            user: userConfig, project: projectConfig, local: localConfig,
            flags: flagOverrides, flagFile: flagFileURL, policy: policySettings
        )
        if let cached = sessionCache.get(cacheKey) {
            return cached
        }

        var result = Settings()

        // Layer 1: User settings (~/.claude/settings.json)
        if let url = userConfig, var s = try? loadFile(url: url) {
            s = stampHooks(s, source: .userSettings)
            result = merge(result, s)
        }

        // Layer 2: Project settings (.claude/settings.json)
        if let url = projectConfig, var s = try? loadFile(url: url) {
            s = stampHooks(s, source: .projectSettings)
            result = merge(result, s)
        }

        // Layer 3: Local settings (.claude/settings.local.json)
        if let url = localConfig, var s = try? loadFile(url: url) {
            s = stampHooks(s, source: .localSettings)
            result = merge(result, s)
        }

        // Layer 4: CLI flag settings (--settings flag or flagFile)
        if var flags = flagOverrides {
            flags = stampHooks(flags, source: .localSettings)
            result = merge(result, flags)
        }
        if let flagURL = flagFileURL, var s = try? loadFile(url: flagURL) {
            s = stampHooks(s, source: .localSettings)
            result = merge(result, s)
        }

        // Layer 5: Policy/enterprise settings (managed-settings.json)
        // CC sub-priority within policy: remote > MDM/plist > file > HKCU
        if var policy = policySettings {
            policy = stampHooks(policy, source: .policySettings)
            result = merge(result, policy)
        }
        // Load managed-settings.d/ directory (CC supports multiple sorted JSON files)
        if let managedDir = managedSettingsDir {
            result = mergeManagedSettingsDir(result, dir: managedDir)
        }

        sessionCache.set(cacheKey, result)
        return result
    }

    /// Load plugin-specific settings (separate from main SETTING_SOURCES in CC).
    public func loadPluginSettings(pluginConfigURL: URL) throws -> Settings? {
        try loadFile(url: pluginConfigURL)
    }

    // MARK: - File Loading

    /// Load a single settings file. Returns nil if file doesn't exist.
    /// Creates a backup before loading (matches CC's corruption recovery).
    public func loadFile(url: URL) throws -> Settings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Try backup recovery
            if let backupData = try? loadBackup(for: url) {
                data = backupData
            } else {
                throw error
            }
        }

        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            // Create backup of corrupted file
            createBackup(url: url, data: data)
            throw ConfigError.corruptedSettings(path: url.path, underlying: error)
        }
    }

    // MARK: - Managed Settings Directory

    /// Load and merge settings from a managed-settings.d/ directory.
    /// CC loads sorted .json files from this directory as additional policy layers.
    private func mergeManagedSettingsDir(_ base: Settings, dir: URL) -> Settings {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return base }

        let jsonFiles = entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result = base
        for fileURL in jsonFiles {
            if let s = try? loadFile(url: fileURL) {
                result = merge(result, s)
            }
        }
        return result
    }

    // MARK: - Backup/Recovery

    /// Create a backup of a settings file before overwriting.
    private func createBackup(url: URL, data: Data) {
        let backupURL = url.appendingPathExtension("bak")
        try? data.write(to: backupURL)
    }

    /// Attempt to load the most recent backup of a settings file.
    private func loadBackup(for url: URL) throws -> Data? {
        let backupURL = url.appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        return try Data(contentsOf: backupURL)
    }

    // MARK: - Hook Source Stamping

    /// Stamp hooks from a settings layer with their source.
    /// Matches CC's hook source tracking per IndividualHookConfig.
    private func stampHooks(_ settings: Settings, source: HookSource) -> Settings {
        var stamped = settings
        stamped.hooks = settings.hooks.map { hook in
            var h = hook
            h.source = source
            return h
        }
        return stamped
    }

    // MARK: - Merge

    /// Merge two settings — higher priority layer wins.
    /// Matches CC's mergeWith() + settingsMergeCustomizer:
    /// - extraAllowedTools: union across sources (OR behavior)
    /// - hooks: concatenated
    /// - enabledPlugins: union with dedup
    /// - mcpServers: deep merge by server name
    /// - env: union with string dedup
    /// - Scalars/objects: overlay wins
    public func merge(_ base: Settings, _ overlay: Settings) -> Settings {
        guard let baseData = try? JSONEncoder().encode(base),
              let overlayData = try? JSONEncoder().encode(overlay),
              var baseDict = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let overlayDict = try? JSONSerialization.jsonObject(with: overlayData) as? [String: Any] else {
            return overlay
        }

        mergeWithCustomizer(into: &baseDict, from: overlayDict)

        guard let mergedData = try? JSONSerialization.data(withJSONObject: baseDict),
              let result = try? JSONDecoder().decode(Settings.self, from: mergedData) else {
            return overlay
        }
        return result
    }

    /// Deep merge with per-key customization matching CC's settingsMergeCustomizer.
    private func mergeWithCustomizer(into base: inout [String: Any], from overlay: [String: Any]) {
        for (key, overlayValue) in overlay {
            guard let baseValue = base[key] else {
                base[key] = overlayValue
                continue
            }

            switch key {
            case "extraAllowedTools":
                // Union (OR) across sources — CC behavior
                if let baseArr = baseValue as? [String], let overlayArr = overlayValue as? [String] {
                    base[key] = Array(Set(baseArr + overlayArr))
                } else {
                    base[key] = overlayValue
                }

            case "enabledPlugins":
                // Union of arrays with dedup — CC behavior
                if let baseArr = baseValue as? [String], let overlayArr = overlayValue as? [String] {
                    base[key] = Array(Set(baseArr + overlayArr)).sorted()
                } else {
                    base[key] = overlayValue
                }

            case "hooks":
                // Concatenated (appended) — CC behavior
                if var baseArr = baseValue as? [Any], let overlayArr = overlayValue as? [Any] {
                    baseArr.append(contentsOf: overlayArr)
                    base[key] = baseArr
                } else {
                    base[key] = overlayValue
                }

            case "mcpServers":
                // Deep merge by server name — CC behavior
                if let baseArr = baseValue as? [Any], let overlayArr = overlayValue as? [Any] {
                    base[key] = mergeMCPServers(baseArr: baseArr, overlayArr: overlayArr)
                } else {
                    base[key] = overlayValue
                }

            case "env":
                // Union with string dedup — CC behavior
                if let baseArr = baseValue as? [String], let overlayArr = overlayValue as? [String] {
                    base[key] = Array(Set(baseArr + overlayArr)).sorted()
                } else {
                    base[key] = overlayValue
                }

            default:
                // Deep merge objects, overlay wins for scalars.
                // Arrays are concatenated and deduped (matching CC's settingsMergeCustomizer).
                if var baseObj = baseValue as? [String: Any], let overlayObj = overlayValue as? [String: Any] {
                    mergeWithCustomizer(into: &baseObj, from: overlayObj)
                    base[key] = baseObj
                } else if let baseArr = baseValue as? [AnyHashable], let overlayArr = overlayValue as? [AnyHashable] {
                    base[key] = Array(Set(baseArr + overlayArr))
                } else {
                    base[key] = overlayValue
                }
            }
        }
    }

    /// Merge MCP servers by name — same-name servers get deep-merged.
    private func mergeMCPServers(baseArr: [Any], overlayArr: [Any]) -> [Any] {
        var merged: [[String: Any]] = baseArr.compactMap { $0 as? [String: Any] }
        for item in overlayArr {
            guard let overlayItem = item as? [String: Any],
                  let name = overlayItem["name"] as? String else {
                continue
            }
            if let idx = merged.firstIndex(where: { ($0["name"] as? String) == name }) {
                var existing = merged[idx]
                mergeWithCustomizer(into: &existing, from: overlayItem)
                merged[idx] = existing
            } else {
                merged.append(overlayItem)
            }
        }
        return merged
    }

    // MARK: - Session Cache

    /// Compute a cache key from config source URLs.
    private func cacheKeyFor(
        user: URL?, project: URL?, local: URL?,
        flags: Settings?, flagFile: URL?, policy: Settings?
    ) -> String {
        let components: [String] = [
            user?.path ?? "no-user",
            project?.path ?? "no-project",
            local?.path ?? "no-local",
            flagFile?.path ?? (flags != nil ? "flags-set" : "no-flags"),
            policy != nil ? "policy-set" : "no-policy",
        ]
        return components.joined(separator: "|")
    }

    // MARK: - Default Paths

    /// Default user config path: ~/.claude/settings.json
    public static func defaultUserConfigPath() -> URL? {
        homeFile(".claude/settings.json")
    }

    /// Default project config path: <cwd>/.claude/settings.json
    public static func defaultProjectConfigPath() -> URL? {
        cwdFile(".claude/settings.json")
    }

    /// Default local config path: <cwd>/.claude/settings.local.json
    public static func defaultLocalConfigPath() -> URL? {
        cwdFile(".claude/settings.local.json")
    }

    /// Default managed settings directory: <cwd>/.claude/managed-settings.d/
    public static func defaultManagedSettingsDir() -> URL? {
        cwdFile(".claude/managed-settings.d")
    }

    private static func homeFile(_ relativePath: String) -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath)
    }

    private static func cwdFile(_ relativePath: String) -> URL? {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
    }
}

// MARK: - Session Cache Actor

/// Thread-safe session-level config cache.
/// Matches CC's getSessionSettingsCache.
private final class ConfigSessionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: Settings] = [:]

    func get(_ key: String) -> Settings? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func set(_ key: String, _ value: Settings) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = value
    }
}

// MARK: - Config Errors

public enum ConfigError: Error, LocalizedError {
    case corruptedSettings(path: String, underlying: Error)
    case fileNotFound(path: String)

    public var errorDescription: String? {
        switch self {
        case .corruptedSettings(let path, let error):
            return "Corrupted settings file at \(path): \(error.localizedDescription)"
        case .fileNotFound(let path):
            return "Settings file not found at \(path)"
        }
    }
}
