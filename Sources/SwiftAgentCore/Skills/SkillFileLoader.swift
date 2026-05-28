import Foundation

// MARK: - Skill File Loader

/// Loads skill definitions from disk and converts them to `FullCommand` objects.
///
/// Follows Claude Code's `/skills/` convention: skills are directories (or symlinks to
/// directories) containing a `SKILL.md` file. Flat `.md` files at the top level are ignored.
///
/// Directories searched:
/// - `~/.claude/skills/` — user-level skills (available across projects)
/// - `.claude/skills/` — project-level skills (override user/bundled)
///
/// Priority (first-found wins): **project > user > bundled**
public struct SkillFileLoader {

    /// The root directory for user-level skills.
    public static let userSkillsDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/skills"
    }()

    /// The relative path for project-level skills.
    public static let projectSkillsRelativePath = ".claude/skills"

    // MARK: - Loading

    /// Return the names of all available skills (from disk and bundled).
    public static func allSkillNames(workingDirectory: String) -> [String] {
        loadAllManifests(workingDirectory: workingDirectory).map { $0.name }
    }

    /// Load all skill manifests from user/project directories, merged with bundled manifests.
    /// Returns manifests only — callers must convert to FullCommand with appropriate
    /// `getPromptForCommand` depending on source (file-based vs bundled).
    ///
    /// - Parameter workingDirectory: The project root directory to look for `.claude/skills/`.
    /// - Returns: Array of `SkillManifest` objects in priority order (project > user > bundled).
    public static func loadAllManifests(workingDirectory: String) -> [SkillManifest] {
        let projectManifests = loadSkills(from: "\(workingDirectory)/\(projectSkillsRelativePath)")
        let userManifests = loadSkills(from: userSkillsDirectory)

        // Merge with priority: project > user > bundled
        var seen: Set<String> = []
        var result: [SkillManifest] = []

        // 1. Project skills (highest priority)
        for m in projectManifests {
            if seen.insert(m.name).inserted {
                result.append(m)
            }
        }

        // 2. User skills
        for m in userManifests {
            if seen.insert(m.name).inserted {
                result.append(m)
            }
        }

        // 3. Bundled skills (lowest priority — appended only if not overridden)
        let bundledManifests = bundledSkillManifests()
        for bm in bundledManifests {
            if seen.insert(bm.name).inserted {
                result.append(bm)
            }
        }

        return result
    }

    /// Load skills from a single directory.
    ///
    /// Follows Claude Code's `/skills/` convention: only directory-format skills are supported.
    /// Each entry must be a directory (or symlink to a directory) containing a `SKILL.md` file.
    /// Flat `.md` files at the top level are ignored — use `/commands/` for those.
    public static func loadSkills(from directory: String) -> [SkillManifest] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else { return [] }

        guard let entries = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var manifests: [SkillManifest] = []

        for entryURL in entries {
            // Resolve symlinks before checking .isDirectory — relative symlinks
            // (e.g. lark-mail -> ../../.agents/skills/lark-mail) are not resolved
            // by resourceValues(forKeys:) alone.
            let resolvedURL = entryURL.resolvingSymlinksInPath()
            let resourceValues = try? resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }

            let skillMDPath = resolvedURL.appendingPathComponent("SKILL.md").path
            guard fm.fileExists(atPath: skillMDPath),
                  let content = try? String(contentsOfFile: skillMDPath, encoding: .utf8),
                  let manifest = SkillYAMLParser.parse(fileContent: content, sourcePath: skillMDPath) else { continue }
            manifests.append(manifest)
        }

        // Sort by name for deterministic ordering
        manifests.sort { $0.name < $1.name }
        return manifests
    }

    // MARK: - Conversion

    /// Convert a `SkillManifest` to a `FullCommand` with `PromptCommand` type.
    public static func manifestToFullCommand(_ manifest: SkillManifest) -> FullCommand {
        let base = CommandBase(
            description: manifest.description,
            name: manifest.name,
            aliases: manifest.aliases,
            argumentHint: manifest.argumentHint,
            whenToUse: manifest.whenToUse,
            version: manifest.version,
            disableModelInvocation: manifest.disableModelInvocation,
            userInvocable: manifest.userInvocable,
            loadedFrom: .skills,
            kind: nil
        )

        let markdownBody = manifest.markdownBody
        let sourcePath = manifest.sourcePath

        let promptCmd = PromptCommand(
            progressMessage: "Launching skill: \(manifest.name)...",
            contentLength: markdownBody.count,
            argNames: nil,
            allowedTools: manifest.allowedTools,
            model: manifest.model,
            source: .userSettings,
            skillRoot: URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path,
            context: manifest.context,
            agent: manifest.agent,
            effort: manifest.effort,
            paths: manifest.paths,
            getPromptForCommand: { _, _ in
                [.text(markdownBody)]
            }
        )

        return FullCommand(base: base, type: .prompt(promptCmd))
    }

    // MARK: - Bundled Skills as Manifests

    /// Convert bundled skills to manifests for priority merging.
    /// This allows bundled skills to be overridden by project/user skills
    /// with the same name.
    private static func bundledSkillManifests() -> [SkillManifest] {
        BundledSkills.all.map { skill in
            SkillManifest(
                name: skill.name,
                description: skill.description,
                aliases: skill.aliases,
                whenToUse: skill.whenToUse,
                allowedTools: skill.allowedTools,
                model: skill.model,
                effort: skill.effort,
                context: skill.context,
                agent: skill.agent,
                paths: skill.paths,
                argumentHint: skill.argumentHint,
                disableModelInvocation: skill.disableModelInvocation,
                userInvocable: skill.userInvocable,
                version: nil,
                author: nil,
                markdownBody: "", // Bundled skills use their own getPromptForCommand
                sourcePath: "bundled://\(skill.name)"
            )
        }
    }
}
