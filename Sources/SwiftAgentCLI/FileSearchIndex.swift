import Foundation

/// Pre-built index of all project files for fast @-mention fuzzy search.
///
/// Uses `git ls-files` (near-instant, reads git index) or falls back to
/// `FileManager.enumerator` (slower but always works).  The index is built
/// once lazily on a background queue; all subsequent searches are performed
/// entirely in-memory against the cached path list.
public final class FileSearchIndex: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.swiftagent.file-index")
    private var _cwd: String = ""
    private var _paths: [String] = []
    private var _isBuilt = false
    private var _isBuilding = false

    // MARK: - Public

    /// Trigger a background build of the index for `cwd` if not already built.
    /// Safe to call repeatedly — skips if building or already built.
    public func ensureBuilt(cwd: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if self._isBuilt || self._isBuilding { return }
            self._isBuilding = true
            self._cwd = cwd
            let discovered = Self.discoverFiles(cwd: cwd)
            self._paths = discovered
            self._isBuilt = true
        }
    }

    /// Synchronously search the currently-loaded paths (or an empty set if the
    /// index is still building). Matches the query against filename *and* the
    /// full relative path, so partial directory prefixes like "Sources/Swift"
    /// also work.
    public func search(query: String, cwd: String, maxResults: Int = 50) -> [PopupItem] {
        let paths = queue.sync { _paths }
        let showHidden = query.hasPrefix(".")

        var items: [PopupItem] = []
        items.reserveCapacity(min(paths.count, 200))

        for relativePath in paths {
            // Hidden filter
            if !showHidden {
                let components = (relativePath as NSString).pathComponents
                if components.contains(where: { $0.hasPrefix(".") }) { continue }
            }

            let name = (relativePath as NSString).lastPathComponent

            // Score against filename first (higher weight), then full path
            let nameResult = FuzzyMatcher.match(query: query, text: name)
            let pathResult = FuzzyMatcher.match(query: query, text: relativePath)
            let bestResult = nameResult.score >= pathResult.score ? nameResult : pathResult
            guard bestResult.score > 0 else { continue }

            var isDirectory = false
            var displayRelPath = relativePath

            // Determine if it's a directory (fast check: other paths with this prefix)
            if paths.contains(where: { $0 != relativePath && $0.hasPrefix(relativePath + "/") }) {
                isDirectory = true
                displayRelPath += "/"
            }

            var score = bestResult.score
            if isDirectory { score = min(1.0, score + 0.01) }

            let displayMatchPositions: [Int]
            if bestResult.score == nameResult.score {
                let prefixLen = displayRelPath.count - name.count
                displayMatchPositions = nameResult.positions.map { $0 + prefixLen }
            } else {
                displayMatchPositions = pathResult.positions
            }

            items.append(PopupItem(
                display: displayRelPath,
                help: nil,
                insertText: "@" + displayRelPath,
                score: score,
                matchPositions: displayMatchPositions,
                isDirectory: isDirectory
            ))
        }

        // Sort: score desc, directories first, then alphabetically
        items.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.display.localizedCaseInsensitiveCompare(b.display) == .orderedAscending
        }

        return Array(items.prefix(maxResults))
    }

    /// Whether the index has been fully built yet.
    public var isBuilt: Bool {
        queue.sync { _isBuilt }
    }

    /// Force a rebuild on next `ensureBuilt` (for CWD changes).
    public func invalidate() {
        queue.async { [weak self] in
            self?._paths = []
            self?._isBuilt = false
            self?._isBuilding = false
        }
    }

    // MARK: - File Discovery

    /// Tries `git ls-files` first, falls back to `FileManager.enumerator`.
    private static func discoverFiles(cwd: String) -> [String] {
        if let gitFiles = tryGitLsFiles(cwd: cwd) {
            return gitFiles
        }
        return fallbackEnumerate(cwd: cwd)
    }

    /// Run `git ls-files` to get tracked + untracked files.
    /// Returns nil if we're not in a git repo or the command fails.
    private static func tryGitLsFiles(cwd: String) -> [String]? {
        // Resolve git root so paths are relative to cwd, not git root.
        guard let gitRoot = runGit(args: ["rev-parse", "--show-toplevel"], cwd: cwd)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !gitRoot.isEmpty else {
            return nil
        }

        // Tracked files (reads git index, very fast)
        guard let trackedStr = runGit(args: [
            "-c", "core.quotepath=false",
            "ls-files",
            "--recurse-submodules",
        ], cwd: gitRoot) else {
            return nil
        }

        // Untracked files (respects .gitignore via --exclude-standard)
        let untrackedStr = runGit(args: [
            "-c", "core.quotepath=false",
            "ls-files", "--others", "--exclude-standard",
        ], cwd: gitRoot) ?? ""

        let tracked = trackedStr.components(separatedBy: "\n").filter { !$0.isEmpty }
        let untracked = untrackedStr.components(separatedBy: "\n").filter { !$0.isEmpty }
        let allFiles = tracked + untracked

        // Convert git-root-relative paths to cwd-relative
        if cwd == gitRoot {
            return allFiles
        }
        return allFiles.compactMap { path -> String? in
            let absolute = (gitRoot as NSString).appendingPathComponent(path)
            return relativize(absolute, from: cwd)
        }
    }

    /// Fallback: recursive `FileManager.enumerator` (slower but always works).
    private static func fallbackEnumerate(cwd: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: cwd) else {
            return []
        }
        var paths: [String] = []
        let vcsDirs: Set<String> = [".git", ".svn", ".hg", ".bzr", ".jj", ".sl"]

        while let relative = enumerator.nextObject() as? String {
            let components = (relative as NSString).pathComponents
            if components.contains(where: { vcsDirs.contains($0) }) { continue }
            paths.append(relative)
        }
        return paths
    }

    // MARK: - Helpers

    private static func runGit(args: [String], cwd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git", "-C", cwd] + args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        proc.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()  // discard stderr

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func relativize(_ path: String, from cwd: String) -> String {
        let cwdSlash = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if path.hasPrefix(cwdSlash) {
            return String(path.dropFirst(cwdSlash.count))
        }
        return path
    }
}
