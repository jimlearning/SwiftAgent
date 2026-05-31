import Foundation

// MARK: - Memory Types

/// Memory file type, matching Claude Code's MemoryType union.
/// Determines loading order and priority (Managed → User → Project → Local).
public enum MemoryType: String, Sendable, Comparable {
    case managed = "Managed"
    case user = "User"
    case project = "Project"
    case local = "Local"
    case autoMem = "AutoMem"

    public static func < (lhs: MemoryType, rhs: MemoryType) -> Bool {
        priority(lhs) < priority(rhs)
    }

    /// Lower number = loaded first; higher = later (overrides earlier).
    static func priority(_ type: MemoryType) -> Int {
        switch type {
        case .managed: return 0
        case .user: return 1
        case .project: return 2
        case .local: return 3
        case .autoMem: return 4
        }
    }
}

// MARK: - Memory File Info

/// A single CLAUDE.md (or included) memory file.
/// Matches Claude Code's MemoryFileInfo.
public struct MemoryFileInfo: Sendable {
    public let path: String
    public let type: MemoryType
    public var content: String
    public let parent: String?

    public init(path: String, type: MemoryType, content: String, parent: String? = nil) {
        self.path = path
        self.type = type
        self.content = content
        self.parent = parent
    }
}

// MARK: - ClaudeMdLoader

/// Loads CLAUDE.md files hierarchically, matching Claude Code's getMemoryFiles() behavior.
///
/// Loading order (reverse priority — higher index = later loaded = overrides earlier):
/// 1. Managed: `/etc/claude-code/CLAUDE.md` (enterprise policy)
/// 2. User: `~/.claude/CLAUDE.md`
/// 3. Project: `CLAUDE.md` + `.claude/CLAUDE.md` in ancestor directories (walked CWD → root)
/// 4. Local: `CLAUDE.local.md` in ancestor directories
///
/// Supports `@include` path directives for composable instruction files.
public struct ClaudeMdLoader: Sendable {

    /// Maximum depth for @include recursion (matching CC's MAX_INCLUDE_DEPTH).
    private static let maxIncludeDepth = 5

    /// Allowed text-file extensions for @include resolution.
    private static let allowedExtensions: Set<String> = [
        "md", "txt", "markdown", "mdown", "mkdn", "mkd", "rst"
    ]

    public init() {}

    // MARK: - Public API

    /// Load all CLAUDE.md files for the given working directory.
    /// Returns files in loading order (earliest first, latest last overrides).
    public func loadAll(workingDirectory: String, homeDirectory: String = NSHomeDirectory()) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []
        _ = Set<String>()

        // 1. Managed (enterprise policy)
        results.append(contentsOf: loadManaged(homeDirectory: homeDirectory))

        // 2. User
        results.append(contentsOf: loadUser(homeDirectory: homeDirectory))

        // 3. Project (walk from CWD up)
        results.append(contentsOf: loadProject(workingDirectory: workingDirectory))

        // 4. Local
        results.append(contentsOf: loadLocal(workingDirectory: workingDirectory))

        return results
    }

    /// Load memory files and merge content into a single string for system prompt injection.
    public func loadMerged(workingDirectory: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let files = loadAll(workingDirectory: workingDirectory, homeDirectory: homeDirectory)
        return files.map { $0.content }.joined(separator: "\n\n")
    }

    // MARK: - Source Loaders

    private func loadManaged(homeDirectory: String) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []
        let managedPath = "/etc/claude-code/CLAUDE.md"
        if let content = readFileSafely(managedPath) {
            results.append(MemoryFileInfo(path: managedPath, type: .managed, content: content))
        }
        return results
    }

    private func loadUser(homeDirectory: String) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []
        let userPath = (homeDirectory as NSString).appendingPathComponent(".claude/CLAUDE.md")
        if let content = readFileSafely(userPath) {
            results.append(MemoryFileInfo(path: userPath, type: .user, content: content))
        }
        // Also load ~/.claude/rules/*.md
        let rulesDir = (homeDirectory as NSString).appendingPathComponent(".claude/rules")
        results.append(contentsOf: loadRuleFiles(in: rulesDir, type: .user))
        return results
    }

    private func loadProject(workingDirectory: String) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []

        // Walk from CWD up to filesystem root
        let ancestors = ancestorDirectories(from: workingDirectory)
        for dir in ancestors {
            // CLAUDE.md at root
            let rootMd = (dir as NSString).appendingPathComponent("CLAUDE.md")
            if let content = readFileSafely(rootMd) {
                results.append(MemoryFileInfo(path: rootMd, type: .project, content: content))
            }
            // .claude/CLAUDE.md
            let dotClaudeMd = (dir as NSString).appendingPathComponent(".claude/CLAUDE.md")
            if let content = readFileSafely(dotClaudeMd) {
                results.append(MemoryFileInfo(path: dotClaudeMd, type: .project, content: content))
            }
            // .claude/rules/*.md
            let rulesDir = (dir as NSString).appendingPathComponent(".claude/rules")
            results.append(contentsOf: loadRuleFiles(in: rulesDir, type: .project))
        }

        return results
    }

    private func loadLocal(workingDirectory: String) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []
        let ancestors = ancestorDirectories(from: workingDirectory)
        for dir in ancestors {
            let localPath = (dir as NSString).appendingPathComponent("CLAUDE.local.md")
            if let content = readFileSafely(localPath) {
                results.append(MemoryFileInfo(path: localPath, type: .local, content: content))
            }
        }
        return results
    }

    // MARK: - @include Resolution

    /// Resolve @include directives recursively. Paths like `@path/to/file.md`
    /// are resolved relative to the including file's directory.
    /// Matching CC's extractIncludePathsFromTokens() + processMemoryFile() recursion.
    public func resolveIncludes(
        in files: [MemoryFileInfo],
        depth: Int = 0
    ) -> [MemoryFileInfo] {
        guard depth < Self.maxIncludeDepth else { return files }

        var results: [MemoryFileInfo] = []
        var processed = Set<String>()

        for file in files {
            // Extract @include paths from content
            let includePaths = extractIncludePaths(from: file.content)
            for includePath in includePaths {
                guard !processed.contains(includePath) else { continue }
                processed.insert(includePath)

                let resolved = resolvePath(includePath, relativeTo: file.path)
                if let content = readFileSafely(resolved) {
                    let included = MemoryFileInfo(
                        path: resolved,
                        type: file.type,
                        content: content,
                        parent: file.path
                    )
                    results.append(included)
                    // Recursively resolve includes in the included file
                    results.append(contentsOf: resolveIncludes(in: [included], depth: depth + 1))
                }
            }
            results.append(file)
        }

        return results
    }

    // MARK: - Helpers

    /// Get ancestor directories from the given path up to root.
    private func ancestorDirectories(from path: String) -> [String] {
        let absolute = (path as NSString).standardizingPath
        _ = (absolute as NSString).pathComponents
        // Remove last component if it's a file, but here we want directories
        var dirs: [String] = []
        var current = absolute
        while !current.isEmpty && current != "/" {
            dirs.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        if current == "/" { dirs.append("/") }
        return dirs
    }

    /// Load all .md rule files from a directory.
    private func loadRuleFiles(in directory: String, type: MemoryType) -> [MemoryFileInfo] {
        var results: [MemoryFileInfo] = []
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return results
        }
        for entry in entries.sorted() where entry.hasSuffix(".md") {
            let fullPath = (directory as NSString).appendingPathComponent(entry)
            if let content = readFileSafely(fullPath) {
                results.append(MemoryFileInfo(path: fullPath, type: type, content: content))
            }
        }
        return results
    }

    /// Read a file safely (UTF-8, non-binary, return nil on any error).
    private func readFileSafely(_ path: String) -> String? {
        let isAllowed = path.hasSuffix(".md") || path.hasSuffix(".txt") || path.hasSuffix(".markdown") ||
            path.hasSuffix(".mdown") || path.hasSuffix(".mkdn") || path.hasSuffix(".mkd") ||
            path.hasSuffix(".rst") || path.contains(".claude/") || path.contains("CLAUDE")
        guard isAllowed else { return nil }
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Extract @include paths from markdown content.
    /// Matches CC's extractIncludePathsFromTokens() — finds @path references
    /// in leaf text nodes, skipping code blocks and code spans.
    private func extractIncludePaths(from content: String) -> [String] {
        var paths: [String] = []
        let lines = content.components(separatedBy: "\n")
        var inCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // Match @path patterns (word-like paths)
            if let match = extractAtPath(from: trimmed) {
                paths.append(match)
            }
        }

        return paths
    }

    /// Extract a single @path reference from a line.
    private func extractAtPath(from line: String) -> String? {
        let pattern = "@([\\w./\\\\-]+\\.(?:md|txt|markdown|mdown|mkdn|mkd|rst))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    /// Resolve a relative path against the including file's directory.
    private func resolvePath(_ includePath: String, relativeTo parentPath: String) -> String {
        if includePath.hasPrefix("/") || includePath.hasPrefix("~") {
            return (includePath as NSString).standardizingPath
        }
        let parentDir = (parentPath as NSString).deletingLastPathComponent
        return ((parentDir as NSString).appendingPathComponent(includePath) as NSString).standardizingPath
    }
}
