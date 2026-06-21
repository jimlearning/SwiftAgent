import Foundation

// MARK: - Discovered Project

/// A project discovered from the filesystem.
public struct DiscoveredProject: Sendable, Identifiable {
    /// The sanitized directory name (e.g. "-users-jim-swiftagent").
    public let sanitizedName: String
    /// Best-guess original path (reverse-engineered from sanitized name).
    public let originalPath: String
    /// Absolute path to the project directory on disk.
    public let storagePath: String
    /// Number of sessions (JSONL files) in this project.
    public let sessionCount: Int

    public var id: String { sanitizedName }

    public init(sanitizedName: String, originalPath: String, storagePath: String, sessionCount: Int = 0) {
        self.sanitizedName = sanitizedName
        self.originalPath = originalPath
        self.storagePath = storagePath
        self.sessionCount = sessionCount
    }
}

// MARK: - Project Discoverer

/// Scans `~/.swift-agent/projects/` for project directories.
///
/// Each project is a subdirectory named with a sanitized version of its
/// original filesystem path (e.g. `/Users/jim/SwiftAgent` → `-users-jim-swiftagent`).
/// The discoverer reverse-maps these back to plausible original paths.
///
/// ## Discovery Strategy
/// 1. List all subdirectories of `~/.swift-agent/projects/`
/// 2. Filter out non-project entries (files, special dirs)
/// 3. Count JSONL files in each directory for `sessionCount`
/// 4. Reverse-map sanitized name → original path
public final class ProjectDiscoverer: @unchecked Sendable {
    private let fileManager: FileManager

    public init() {
        self.fileManager = FileManager.default
    }

    // MARK: - Discovery

    /// Discover all projects under `~/.swift-agent/projects/`.
    /// Returns projects sorted alphabetically by sanitized name.
    public func discoverAll() -> [DiscoveredProject] {
        let projectsDir = SwiftAgentPaths.projectsDir()
        guard fileManager.fileExists(atPath: projectsDir),
              let entries = try? fileManager.contentsOfDirectory(atPath: projectsDir)
        else { return [] }

        return entries
            .filter { entry in
                // Skip hidden files/dirs, special entries, and the memory directory
                guard !entry.hasPrefix(".") else { return false }
                let fullPath = (projectsDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue
                else { return false }
                // Skip the memory subdirectory (it's not a project itself)
                guard entry != "memory" else { return false }
                return true
            }
            .map { entry in
                let fullPath = (projectsDir as NSString).appendingPathComponent(entry)
                let sessionCount = countJSONLFiles(in: fullPath)
                let originalPath = SwiftAgentPaths.unsanitizePath(entry)
                return DiscoveredProject(
                    sanitizedName: entry,
                    originalPath: originalPath,
                    storagePath: fullPath,
                    sessionCount: sessionCount
                )
            }
            .sorted { $0.sanitizedName < $1.sanitizedName }
    }

    /// Discover a specific project by its original (unsanitized) path.
    public func discover(projectPath: String) -> DiscoveredProject? {
        let sanitized = SwiftAgentPaths.sanitizePath(projectPath)
        let storagePath = SwiftAgentPaths.projectDir(forProjectPath: projectPath)

        guard fileManager.fileExists(atPath: storagePath) else { return nil }

        let sessionCount = countJSONLFiles(in: storagePath)
        return DiscoveredProject(
            sanitizedName: sanitized,
            originalPath: projectPath,
            storagePath: storagePath,
            sessionCount: sessionCount
        )
    }

    // MARK: - CRUD

    /// Create a new project directory if it doesn't exist.
    /// Returns the storage path on success.
    @discardableResult
    public func createProject(projectPath: String) throws -> String {
        let storagePath = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        try fileManager.createDirectory(atPath: storagePath, withIntermediateDirectories: true)

        // Also ensure the parent projects directory exists
        let projectsDir = SwiftAgentPaths.projectsDir()
        try? fileManager.createDirectory(atPath: projectsDir, withIntermediateDirectories: true)

        return storagePath
    }

    /// Delete a project directory and all its contents.
    public func deleteProject(projectPath: String) throws {
        let storagePath = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        guard fileManager.fileExists(atPath: storagePath) else { return }
        try fileManager.removeItem(atPath: storagePath)
    }

    /// Check if a project exists on disk.
    public func exists(projectPath: String) -> Bool {
        let storagePath = SwiftAgentPaths.projectDir(forProjectPath: projectPath)
        return fileManager.fileExists(atPath: storagePath)
    }

    // MARK: - Helpers

    /// Count JSONL files in a directory (recursively, but only one level for sessions).
    private func countJSONLFiles(in directory: String) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return 0 }
        return entries.filter { $0.hasSuffix(".jsonl") }.count
    }
}
