import Foundation

/// Fast file pattern matching with glob support.
/// Mirrors Claude Code's GlobTool with result limits and VCS exclusion.
public struct GlobTool: Tool {
    public init() {}
    public let name = "Glob"
    public var searchHint: String? { "find files by name pattern or wildcard" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Fast file pattern matching tool. Supports glob patterns like '**/*.swift'." }
    public var isReadOnly: Bool { true }
    public var isConcurrencySafe: Bool { true }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "pattern": JSONSchemaProperty(type: "string", description: "The glob pattern to match files against"),
            "path": JSONSchemaProperty(type: "string", description: "The directory to search in. Defaults to working directory. Omit for default."),
        ], required: ["pattern"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let pattern) = input["pattern"] else {
            return ToolResult(content: "Error: pattern is required", isError: true)
        }

        let searchPath: String
        if case .string(let customPath) = input["path"] {
            searchPath = customPath
        } else {
            searchPath = context.workingDirectory
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: searchPath, isDirectory: &isDir), isDir.boolValue else {
            return ToolResult(content: "Error: path is not a valid directory: \(searchPath)", isError: true)
        }

        let maxResults = 100
        var results: [String] = []
        let vcsDirs: Set<String> = [".git", ".svn", ".hg", ".bzr", ".jj", ".sl"]

        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst())
            results = findFiles(withExtension: ext, in: searchPath, excludeVCS: vcsDirs)
        } else if pattern.contains("**/") {
            let afterGlob = pattern.replacingOccurrences(of: "**/", with: "")
            results = findFilesRecursive(matching: afterGlob, in: searchPath, excludeVCS: vcsDirs)
        } else if pattern.contains("*") {
            results = findFiles(matching: pattern, in: searchPath, excludeVCS: vcsDirs)
        } else {
            if fm.fileExists(atPath: pattern) {
                results = [pattern]
            }
        }

        let truncated = results.count > maxResults
        let limited = Array(results.prefix(maxResults))
        let relativized = limited.map { relativize($0, from: context.workingDirectory) }

        var output = relativized.joined(separator: "\n")
        if output.isEmpty { output = "No files matched" }
        if truncated { output += "\n[Showing \(maxResults) of \(results.count) results]" }

        return ToolResult(content: output)
    }

    // MARK: - Private

    private func findFiles(withExtension ext: String, in directory: String, excludeVCS: Set<String>) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var results: [String] = []
        while let file = enumerator.nextObject() as? String {
            if containsVCS(file, excludeVCS) { continue }
            if file.hasSuffix(ext) {
                results.append("\(directory)/\(file)")
            }
        }
        return results.sorted()
    }

    private func findFilesRecursive(matching suffix: String, in directory: String, excludeVCS: Set<String>) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var results: [String] = []
        while let file = enumerator.nextObject() as? String {
            if containsVCS(file, excludeVCS) { continue }
            if file.hasSuffix(suffix) || file == suffix {
                results.append("\(directory)/\(file)")
            }
        }
        return results.sorted()
    }

    private func findFiles(matching pattern: String, in directory: String, excludeVCS: Set<String>) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^\(escaped.replacingOccurrences(of: "\\*", with: ".*"))$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return [] }

        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var results: [String] = []
        while let file = enumerator.nextObject() as? String {
            if containsVCS(file, excludeVCS) { continue }
            let name = (file as NSString).lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if regex.firstMatch(in: name, range: range) != nil {
                results.append("\(directory)/\(file)")
            }
        }
        return results.sorted()
    }

    private func containsVCS(_ path: String, _ vcsDirs: Set<String>) -> Bool {
        let components = (path as NSString).pathComponents
        return components.contains(where: { vcsDirs.contains($0) })
    }

    private func relativize(_ path: String, from cwd: String) -> String {
        if path.hasPrefix(cwd + "/") {
            return String(path.dropFirst(cwd.count + 1))
        }
        return path
    }
}
