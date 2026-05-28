import Foundation

// MARK: - Popup Item

/// A single selectable item in the inline popup menu.
public struct PopupItem {
    /// Display text shown in the list (e.g. "Sources/SwiftAgentCLI/").
    public let display: String
    /// Optional help / description shown on a second line.
    public let help: String?
    /// Text to insert into the input buffer on selection, including the trigger
    /// character (e.g. "@Sources/SwiftAgentCLI/" or "/help").
    public let insertText: String
    /// Relevance score from FuzzyMatcher (0…1). Higher = better match.
    public let score: Float
    /// Indices of matched characters within `display` for highlight rendering.
    public let matchPositions: [Int]
    /// Whether this item represents a directory (only meaningful for file data sources).
    public let isDirectory: Bool

    public init(
        display: String,
        help: String? = nil,
        insertText: String,
        score: Float,
        matchPositions: [Int] = [],
        isDirectory: Bool = false
    ) {
        self.display = display
        self.help = help
        self.insertText = insertText
        self.score = score
        self.matchPositions = matchPositions
        self.isDirectory = isDirectory
    }
}

// MARK: - Data Source Protocol

/// Data source for popup items, keyed by a search query string.
/// One implementation each for slash-commands and file-system @-mentions.
public protocol PopupDataSource: AnyObject, Sendable {
    /// Search for items matching `query` and return results sorted by descending score.
    func search(query: String) -> [PopupItem]
}

// MARK: - Command Data Source

/// Provides slash-command completions from registered built-in commands and skills.
public final class CommandDataSource: PopupDataSource, @unchecked Sendable {
    private let entries: [CommandEntry]

    private struct CommandEntry {
        let name: String          // e.g. "help", "clear"
        let displayName: String   // e.g. "/help"
        let help: String?
        let aliases: [String]
    }

    /// - Parameter commands: Array of `(name: String, help: String?)` tuples.
    ///   `name` should include the leading `/` (e.g. `"/help"`, `"/commit"`).
    /// - Parameter aliases: Optional map of command name → alias list.
    public init(
        commands: [(name: String, help: String?)],
        aliases: [String: [String]] = [:]
    ) {
        self.entries = commands.map {
            let cmdName = $0.name.hasPrefix("/") ? String($0.name.dropFirst()) : $0.name
            return CommandEntry(
                name: cmdName,
                displayName: $0.name.hasPrefix("/") ? $0.name : "/" + $0.name,
                help: $0.help,
                aliases: aliases[cmdName] ?? []
            )
        }
    }

    public func search(query: String) -> [PopupItem] {
        var items: [PopupItem] = []

        for entry in entries {
            // Search against the command name (without slash) and aliases
            let searchTargets = [entry.name] + entry.aliases
            var bestResult: (score: Float, positions: [Int], text: String)? = nil

            for target in searchTargets {
                let r = FuzzyMatcher.match(query: query, text: target)
                if r.score > (bestResult?.score ?? 0) {
                    bestResult = (r.score, r.positions, target)
                }
            }

            guard let match = bestResult, match.score > 0 else { continue }

            items.append(PopupItem(
                display: entry.displayName,
                help: entry.help,
                insertText: entry.displayName,  // "/" + name
                score: match.score,
                matchPositions: match.positions
            ))
        }

        return items.sorted { $0.score > $1.score }
    }
}

// MARK: - File Data Source

/// Provides file-system completions for @-mentions.
///
/// Uses a shared `FileSearchIndex` for fast fuzzy search across all project
/// files. On first use, the index is built in the background via `git ls-files`
/// (or `FileManager.enumerator` as fallback). Once built, all searches are
/// in-memory with no disk I/O.
///
/// Path resolution rules (to produce unambiguous paths for the AI):
/// 1. All returned paths are **relative to `workingDirectory`**.
/// 2. Directory entries have a trailing `/`.
/// 3. Hidden files (`.gitignore`, `.swiftpm/`, etc.) are hidden unless the
///    query starts with `.`.
/// 4. VCS directories (`.git`, `.svn`, `.hg`) are always excluded.
/// 5. `..` and `.` are supported for parent/self navigation.
public final class FileDataSource: PopupDataSource, @unchecked Sendable {
    private let workingDirectory: String
    private let maxResults: Int
    private let index: FileSearchIndex

    /// - Parameters:
    ///   - workingDirectory: The project root / CWD. All paths are relative to this.
    ///   - maxResults: Maximum number of items to return (default 50).
    ///   - index: Shared file search index. If nil, a new isolated index is created.
    public init(workingDirectory: String, maxResults: Int = 50, index: FileSearchIndex? = nil) {
        self.workingDirectory = workingDirectory.hasSuffix("/")
            ? String(workingDirectory.dropLast())
            : workingDirectory
        self.maxResults = maxResults
        self.index = index ?? FileSearchIndex()
    }

    public func search(query: String) -> [PopupItem] {
        let (dirPart, basenamePart) = splitQuery(query)

        // Empty query — show top-level entries (readdir, not index)
        if dirPart.isEmpty && basenamePart.isEmpty {
            index.ensureBuilt(cwd: workingDirectory)
            return getTopLevel()
        }

        // Pure filename/path search without directory prefix — use the index
        if dirPart.isEmpty && !basenamePart.isEmpty {
            index.ensureBuilt(cwd: workingDirectory)
            return index.search(query: basenamePart, cwd: workingDirectory, maxResults: maxResults)
        }

        // Directory-scoped search (has a "/" in the query)
        return searchInDirectory(dirPart: dirPart, basename: basenamePart)
    }

    /// List top-level files and directories (used when popup first opens with "@").
    private func getTopLevel() -> [PopupItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: workingDirectory) else {
            return []
        }
        var items: [PopupItem] = []
        for name in contents {
            if name.hasPrefix(".") { continue }
            if vcsDirs.contains(name) { continue }
            let fullPath = (workingDirectory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }
            let displayName = isDir.boolValue ? name + "/" : name
            items.append(PopupItem(
                display: displayName,
                help: nil,
                insertText: "@" + displayName,
                score: 1.0,
                matchPositions: [],
                isDirectory: isDir.boolValue
            ))
        }
        items.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.display.localizedCaseInsensitiveCompare(b.display) == .orderedAscending
        }
        return Array(items.prefix(maxResults))
    }

    // MARK: - Directory-scoped search (existing behavior)

    private func searchInDirectory(dirPart: String, basename: String) -> [PopupItem] {
        let targetDir: String
        if dirPart.isEmpty {
            targetDir = workingDirectory
        } else {
            // Resolve relative path against working directory
            let resolved = (workingDirectory as NSString).appendingPathComponent(dirPart)
            targetDir = resolved
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetDir, isDirectory: &isDir),
              isDir.boolValue else {
            // Directory doesn't exist — show no results (or could fuzzy-match
            // the whole query against parent-dir contents)
            return fuzzyMatchInParent(query: dirPart + basename, targetDir: targetDir)
        }

        // List directory contents
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: targetDir) else {
            return []
        }

        let showHidden = basename.hasPrefix(".")

        let entries: [String] = contents.filter { name in
            // Always exclude VCS directories
            if vcsDirs.contains(name) { return false }
            // Exclude hidden unless query starts with "."
            if !showHidden && name.hasPrefix(".") { return false }
            return true
        }

        // Score each entry against the basename part of the query
        var items: [PopupItem] = []

        for name in entries {
            let fullPath = (targetDir as NSString).appendingPathComponent(name)
            var isDirFlag: ObjCBool = false
            let exists = fm.fileExists(atPath: fullPath, isDirectory: &isDirFlag)
            guard exists else { continue }

            let isDirectory = isDirFlag.boolValue
            let displayName = isDirectory ? name + "/" : name

            let result = FuzzyMatcher.match(query: basename, text: name)

            var score = result.score
            // Boost directories slightly so they appear before same-named files
            if isDirectory && result.score > 0 { score = min(1.0, score + 0.01) }

            if score > 0 || basename.isEmpty {
                let positions = basename.isEmpty ? [] : result.positions

                // Build the relative path from workingDirectory
                let relPath = relativize(fullPath, from: workingDirectory)
                let insertRelPath = isDirectory ? relPath + "/" : relPath

                items.append(PopupItem(
                    display: displayName,
                    help: nil,
                    insertText: "@" + insertRelPath,
                    score: score,
                    matchPositions: positions,
                    isDirectory: isDirectory
                ))
            }
        }

        // Sort: by score desc, then alphabetically
        items.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.display.localizedCaseInsensitiveCompare(b.display) == .orderedAscending
        }

        return Array(items.prefix(maxResults))
    }

    // MARK: - Private helpers

    /// Split a query like "Sources/SwiftA" into dir="Sources/" and base="SwiftA".
    private func splitQuery(_ query: String) -> (dir: String, base: String) {
        if let lastSlash = query.lastIndex(of: "/") {
            let dir = String(query[...lastSlash])
            let base = String(query[query.index(after: lastSlash)...])
            return (dir, base)
        }
        return ("", query)
    }

    /// When the target directory doesn't exist, try fuzzy-matching the whole query
    /// against entries in the parent directory.
    private func fuzzyMatchInParent(query: String, targetDir: String) -> [PopupItem] {
        let parentDir = (targetDir as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: parentDir) else { return [] }

        // Use the last path component as the basename to fuzzy-match
        let baseCandidate = (targetDir as NSString).lastPathComponent

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: parentDir) else {
            return []
        }

        let showHidden = baseCandidate.hasPrefix(".")

        var items: [PopupItem] = []
        for name in contents {
            if !showHidden && name.hasPrefix(".") { continue }
            if vcsDirs.contains(name) { continue }

            let fullPath = (parentDir as NSString).appendingPathComponent(name)
            var isDirFlag: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDirFlag) else { continue }

            let isDirectory = isDirFlag.boolValue
            let displayName = isDirectory ? name + "/" : name

            let result = FuzzyMatcher.match(query: baseCandidate, text: name)
            guard result.score > 0 else { continue }

            let score = isDirectory ? min(1.0, result.score + 0.01) : result.score
            let relPath = relativize(fullPath, from: workingDirectory)
            let insertRelPath = isDirectory ? relPath + "/" : relPath

            items.append(PopupItem(
                display: displayName,
                help: nil,
                insertText: "@" + insertRelPath,
                score: score,
                matchPositions: result.positions,
                isDirectory: isDirectory
            ))
        }

        items.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.display.localizedCaseInsensitiveCompare(b.display) == .orderedAscending
        }

        return Array(items.prefix(maxResults))
    }

    private func relativize(_ path: String, from cwd: String) -> String {
        let cwdSlash = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if path.hasPrefix(cwdSlash) {
            return String(path.dropFirst(cwdSlash.count))
        }
        // If not under cwd (shouldn't happen), return absolute path
        return path
    }

    private let vcsDirs: Set<String> = [".git", ".svn", ".hg", ".bzr", ".jj", ".sl"]
}
