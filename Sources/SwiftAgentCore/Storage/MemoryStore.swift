import Foundation

// MARK: - Memory Type Taxonomy

/// Memory type matching CC's four-type memory taxonomy.
/// Matches CC's memdir/memoryTypes.ts MemoryEntryType.
public enum MemoryEntryType: String, Codable, Sendable, CaseIterable {
    case user
    case feedback
    case project
    case reference
}

/// A single memory entry with parsed frontmatter and body.
/// Matches CC's MemoryEntry in memdir/memoryScan.ts.
public struct MemoryEntry: Sendable, Identifiable {
    public let name: String
    public let description: String
    public let type: MemoryEntryType
    public let body: String
    public let filePath: URL
    public let lastModified: Date

    public var id: String { name }

    public init(
        name: String,
        description: String = "",
        type: MemoryEntryType = .project,
        body: String = "",
        filePath: URL,
        lastModified: Date = Date()
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.body = body
        self.filePath = filePath
        self.lastModified = lastModified
    }
}

// MARK: - Memory Directory Manager

/// Manages persistent memory using CC's `memdir/` architecture.
/// Mirrors Claude Code's memory directory system:
/// - ~/.claude/projects/<sanitized-git-root>/memory/ for individual memories
/// - MEMORY.md as the entrypoint index
/// - team/ subdirectory for shared team memories
/// - logs/YYYY/MM/ for daily append-only logs (assistant mode)
public final class MemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private let memoryDir: URL
    private let teamDir: URL?
    private let fileManager: FileManager

    // MARK: - Constants

    /// Max lines to read from MEMORY.md (matching CC's 200-line truncation).
    private static let maxEntrypointLines = 200
    /// Max bytes to read from MEMORY.md (matching CC's 25KB limit).
    private static let maxEntrypointBytes = 25_000
    /// Max memory files to scan for relevance (matching CC's limit).
    private static let maxMemoryFiles = 200

    // MARK: - Initialization

    /// Initialize with a project directory. Memory is stored at:
    /// ~/.claude/projects/<sanitized-path>/memory/
    public init(projectDir: String = FileManager.default.currentDirectoryPath) {
        self.fileManager = FileManager.default
        self.projectDir = projectDir
        let sanitized = Self.sanitizeProjectPath(projectDir)
        let baseDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(sanitized)/memory")
        self.memoryDir = baseDir
        let team = baseDir.appendingPathComponent("team")
        self.teamDir = fileManager.fileExists(atPath: team.path) ? team : nil
        try? fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
    }

    /// Initialize with explicit memory directory path.
    public init(memoryDir: URL) {
        self.fileManager = FileManager.default
        self.projectDir = FileManager.default.currentDirectoryPath
        self.memoryDir = memoryDir
        let team = memoryDir.appendingPathComponent("team")
        self.teamDir = fileManager.fileExists(atPath: team.path) ? team : nil
        try? fileManager.createDirectory(at: memoryDir, withIntermediateDirectories: true)
    }

    // MARK: - Path Sanitization

    /// Sanitize a project path for use as a directory name.
    /// Matches CC's path sanitization: remove leading /, replace / with -.
    private static func sanitizeProjectPath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).standardized.path
        var sanitized = resolved.hasPrefix("/") ? String(resolved.dropFirst()) : resolved
        sanitized = sanitized.replacingOccurrences(of: "/", with: "-")
        sanitized = sanitized.replacingOccurrences(of: " ", with: "_")
        return sanitized.lowercased()
    }

    // MARK: - Entrypoint (MEMORY.md)

    /// Read the MEMORY.md entrypoint index.
    /// Matches CC's loading of the MEMORY.md pointer file.
    public func readEntrypoint() -> String? {
        let url = memoryDir.appendingPathComponent("MEMORY.md")
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        // Apply line and byte limits
        let lines = content.components(separatedBy: .newlines)
        let truncated = lines.prefix(Self.maxEntrypointLines)
        let result = truncated.joined(separator: "\n")
        if result.utf8.count > Self.maxEntrypointBytes {
            return String(result.prefix(Self.maxEntrypointBytes))
        }
        return result
    }

    /// Write the MEMORY.md entrypoint index.
    /// Each entry should be one line: `- [Title](file.md) — one-line hook`
    public func writeEntrypoint(_ content: String) throws {
        let url = memoryDir.appendingPathComponent("MEMORY.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Add a pointer to MEMORY.md for a memory file.
    /// Matches CC's two-step save: write memory file, then update index.
    public func addEntrypointPointer(title: String, fileName: String, description: String) throws {
        var content = readEntrypoint() ?? "# Memory\n\n"
        let line = "- [\(title)](\(fileName)) — \(description)\n"
        content += line
        try writeEntrypoint(content)
    }

    // MARK: - Memory Files

    /// Write a memory file with YAML frontmatter.
    /// Matches CC's memory file format: frontmatter with name, description, type.
    public func writeMemory(_ entry: MemoryEntry) throws {
        let fileName = entry.name.hasSuffix(".md") ? entry.name : "\(entry.name).md"
        let url = memoryDir.appendingPathComponent(fileName)
        let frontmatter = """
        ---
        name: \(entry.name)
        description: \(entry.description)
        metadata:
          type: \(entry.type.rawValue)
        ---

        \(entry.body)
        """
        try frontmatter.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Read a single memory file.
    public func readMemory(fileName: String) -> MemoryEntry? {
        let url = memoryDir.appendingPathComponent(fileName)
        return readMemoryFile(at: url)
    }

    /// Delete a memory file.
    public func deleteMemory(fileName: String) throws {
        let url = memoryDir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Memory Scanning

    /// Scan the memory directory for all memory files.
    /// Matches CC's memoryScan: reads .md files, parses frontmatter, sorts by mtime.
    public func scanAll() -> [MemoryEntry] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: memoryDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mdFiles = entries
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
            .sorted { (a: URL, b: URL) -> Bool in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return dateA > dateB
            }
            .prefix(Self.maxMemoryFiles)

        return Array(mdFiles).compactMap { readMemoryFile(at: $0) }
    }

    /// Find relevant memories for a given query context.
    /// Matches CC's findRelevantMemories: scans manifest, selects up to 5.
    /// Without an LLM sub-agent, we use a simpler heuristic based on recency and type.
    public func findRelevant(query: String, limit: Int = 5) -> [MemoryEntry] {
        let all = scanAll()
        guard !all.isEmpty else { return [] }

        // Score by recency and keyword match
        let now = Date()
        let scored: [(MemoryEntry, Double)] = all.map { entry in
            var score = 0.0
            // Recency: newer memories score higher (decay over 30 days)
            let ageInDays = now.timeIntervalSince(entry.lastModified) / 86400
            score += max(0, 1.0 - ageInDays / 30.0) * 0.5
            // Keyword match: boost memories whose name/description matches query terms
            let queryTerms = query.lowercased().components(separatedBy: .whitespaces)
            let memText = "\(entry.name) \(entry.description)".lowercased()
            let matchCount = queryTerms.filter { memText.contains($0) }.count
            if !queryTerms.isEmpty {
                score += (Double(matchCount) / Double(queryTerms.count)) * 0.5
            }
            return (entry, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Memory Aging

    /// Compute staleness for a memory entry.
    /// Matches CC's memoryAge: days since last modification.
    public func ageInDays(of entry: MemoryEntry) -> Int {
        let now = Date()
        return max(0, Int(now.timeIntervalSince(entry.lastModified) / 86400))
    }

    /// Generate a freshness warning for a memory.
    /// Matches CC's memoryFreshnessText: "This memory is N days old."
    public func freshnessNote(for entry: MemoryEntry) -> String? {
        let days = ageInDays(of: entry)
        guard days > 1 else { return nil }
        return "This memory is \(days) days old. Memories are point-in-time observations. Verify against current code."
    }

    /// Build a freshness-tagged system reminder for a memory.
    /// Matches CC's system-reminder wrapping of memory content.
    public func buildSystemReminder(for entry: MemoryEntry) -> String {
        var result = "## Memory: \(entry.name)\n"
        result += "Type: \(entry.type.rawValue)\n"
        if let note = freshnessNote(for: entry) {
            result += "<system-reminder>\(note)</system-reminder>\n"
        }
        result += "\n\(entry.body)"
        return result
    }

    // MARK: - Team Memory

    /// Read team memory entrypoint (team/MEMORY.md).
    public func readTeamEntrypoint() -> String? {
        guard let team = teamDir else { return nil }
        let url = team.appendingPathComponent("MEMORY.md")
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Scan team memory directory.
    public func scanTeam() -> [MemoryEntry] {
        guard let team = teamDir else { return [] }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: team,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
            .compactMap { readMemoryFile(at: $0) }
    }

    // MARK: - Save Two-Step

    /// Two-step memory save matching CC's protocol:
    /// 1. Write the memory to its own .md file with frontmatter
    /// 2. Add a one-line pointer to MEMORY.md
    public func saveMemory(name: String, type: MemoryEntryType, description: String, body: String) throws {
        let entry = MemoryEntry(
            name: name,
            description: description,
            type: type,
            body: body,
            filePath: memoryDir.appendingPathComponent("\(name).md")
        )
        try writeMemory(entry)
        try addEntrypointPointer(title: name, fileName: "\(name).md", description: description)
    }

    // MARK: - Legacy API (backward-compatible with old MemoryStore tests)

    // Stored for legacy test compatibility.
    private let projectDir: String

    /// Read project-level CLAUDE.md (legacy).
    public func readProject() throws -> String? {
        let url = URL(fileURLWithPath: projectDir).appendingPathComponent("CLAUDE.md")
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return content
    }

    /// Write project-level CLAUDE.md (legacy).
    public func writeProject(_ content: String) throws {
        let url = URL(fileURLWithPath: projectDir).appendingPathComponent("CLAUDE.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Parse YAML frontmatter from content (public for test compatibility).
    public func parseFrontmatter(_ content: String) -> (frontmatter: [String: String], body: String) {
        parseFrontmatterInternal(content)
    }

    // MARK: - Helpers

    /// Read and parse a memory file from disk.
    private func readMemoryFile(at url: URL) -> MemoryEntry? {
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let (fm, body) = parseFrontmatterInternal(content)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return MemoryEntry(
            name: fm["name"] ?? url.deletingPathExtension().lastPathComponent,
            description: fm["description"] ?? "",
            type: MemoryEntryType(rawValue: fm["type"] ?? fm["metadata_type"] ?? "project") ?? .project,
            body: body,
            filePath: url,
            lastModified: modified
        )
    }

    /// Parse YAML frontmatter from memory content.
    private func parseFrontmatterInternal(_ content: String) -> ([String: String], String) {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], content)
        }
        var metadata: [String: String] = [:]
        var endIndex = 1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
            let parts = lines[i].split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                metadata[key] = value
            }
        }
        let body = lines.suffix(from: endIndex + 1).joined(separator: "\n")
        return (metadata, body)
    }
}

// MARK: - Memory Prompt Builder

extension MemoryStore {
    /// Build the memory section of the system prompt.
    /// Matches CC's loadMemoryPrompt() in memdir/memdir.ts.
    public func buildMemoryPromptSection() -> String? {
        guard let entrypoint = readEntrypoint() else { return nil }
        let teamSection = readTeamEntrypoint().map { "\n\n## Team Memory\n\($0)" } ?? ""
        return """
        ## Memory

        You have a persistent, file-based memory system at `\(memoryDir.path)`. This directory already exists — write to it directly.

        ### Types of memory

        - **user**: Contain information about the user's role, goals, responsibilities, and knowledge.
        - **feedback**: Guidance the user has given you about how to approach work.
        - **project**: Information about ongoing work, goals, initiatives, bugs, or incidents.
        - **reference**: Pointers to where information can be found in external systems.

        ### What NOT to save
        - Code patterns, conventions, architecture, file paths, or project structure — derivable from current state.
        - Git history, recent changes — `git log` is authoritative.
        - Debugging solutions — the fix is in the code.
        - Anything already documented in CLAUDE.md files.
        - Ephemeral task details: in-progress work, current conversation context.

        ### How to save
        1. Write each memory to its own .md file with YAML frontmatter (name, description, type).
        2. Add a one-line pointer to MEMORY.md.

        ### When to access
        - When memories seem relevant, or the user references prior-conversation work.
        - You MUST access memory when the user explicitly asks you to check, recall, or remember.
        - Verify memory claims against current state before acting.

        ---

        \(entrypoint)\(teamSection)
        """
    }

    /// Build a compact memory instruction section for the system prompt.
    /// Used when the full memory taxonomy is already present from a prior turn.
    public func buildCompactMemoryPrompt() -> String? {
        guard let entrypoint = readEntrypoint() else { return nil }
        return entrypoint
    }
}
