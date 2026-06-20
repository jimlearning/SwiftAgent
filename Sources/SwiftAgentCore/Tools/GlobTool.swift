import Foundation

/// Fast file pattern matching with glob support.
/// Uses ripgrep (rg) for speed — matches Claude Code's GlobTool which
/// delegates to `rg --files --glob`. Falls back to Foundation enumeration
/// when rg is not installed.
public struct GlobTool: Tool {
    public init() {}
    public let name = "Glob"
    public var searchHint: String? { "find files by name pattern or wildcard" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Fast file pattern matching tool using ripgrep. Supports glob patterns like '**/*.swift'." }
    public var isReadOnly: Bool { true }
    public var isConcurrencySafe: Bool { true }
    public var maxResultSizeChars: Int { 100_000 }

    private static let vcsDirs: Set<String> = [".git", ".svn", ".hg", ".bzr", ".jj", ".sl"]
    private static let maxResults = 100

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "pattern": JSONSchemaProperty(type: "string", description: "The glob pattern to match files against"),
            "path": JSONSchemaProperty(type: "string", description: "The directory to search in. If not specified, the current working directory will be used. IMPORTANT: Omit this field to use the default directory. Must be a valid directory path if provided."),
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

        // Try ripgrep first (matches CC's approach)
        if let rgPath = findRipgrep() {
            return executeRipgrep(pattern: pattern, searchPath: searchPath, rgPath: rgPath, cwd: context.workingDirectory)
        }

        // Fall back to Foundation enumeration
        return executeFoundation(pattern: pattern, searchPath: searchPath, cwd: context.workingDirectory)
    }

    // MARK: - Ripgrep (CC-aligned)

    private func executeRipgrep(pattern: String, searchPath: String, rgPath: String, cwd: String) -> ToolResult {
        var args: [String] = [
            "--files",
            "--glob", pattern,
            "--sort=modified",
            "--no-ignore",
            "--hidden",
        ]

        // Exclude VCS directories (matches CC's --glob !pattern exclusions)
        for dir in Self.vcsDirs {
            args.append(contentsOf: ["--glob", "!\(dir)"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rgPath)
        process.arguments = args + [searchPath]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ToolResult(content: "Error executing rg: \(error.localizedDescription)", isError: true)
        }

        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: outputData, encoding: .utf8) else {
            return ToolResult(content: "No files matched")
        }

        let allPaths = output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        let truncated = allPaths.count > Self.maxResults
        let limited = Array(allPaths.prefix(Self.maxResults))
        let relativized = limited.map { relativize($0, from: cwd) }

        var result = relativized.joined(separator: "\n")
        if result.isEmpty { result = "No files matched" }
        if truncated { result += "\n(Results are truncated. Consider using a more specific path or pattern.)" }

        return ToolResult(content: result)
    }

    // MARK: - Foundation fallback

    /// Foundation-based enumeration with early termination and large-dir skipping.
    /// Used when ripgrep is not installed. Terminates at `maxResults` to avoid
    /// unbounded traversal of large directory trees.
    private static let skipDirs: Set<String> = [
        "node_modules", "Library", "Caches", "DerivedData",
        ".swiftpm", ".build", "Pods", "logs",
        "vendor", "bower_components", ".cache", ".npm",
        ".yarn", ".turbo", ".next", "__pycache__",
    ]

    private func executeFoundation(pattern: String, searchPath: String, cwd: String) -> ToolResult {
        var results: [String] = []

        switch true {
        case pattern.hasPrefix("*."):
            let ext = String(pattern.dropFirst())
            results = enumerateFiles(in: searchPath) { file in file.hasSuffix(ext) }
        case pattern.contains("**/"):
            let suffix = pattern.replacingOccurrences(of: "**/", with: "")
            results = enumerateFiles(in: searchPath) { file in file.hasSuffix(suffix) || file == suffix }
        case pattern.contains("*"):
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let regexPattern = "^\(escaped.replacingOccurrences(of: "\\*", with: ".*"))$"
            guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
                return ToolResult(content: "No files matched")
            }
            results = enumerateFiles(in: searchPath) { file in
                let name = (file as NSString).lastPathComponent
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return regex.firstMatch(in: name, range: range) != nil
            }
        default:
            if FileManager.default.fileExists(atPath: pattern) {
                results = [pattern]
            }
        }

        let truncated = results.count > Self.maxResults
        let limited = Array(results.prefix(Self.maxResults))
        let relativized = limited.map { relativize($0, from: cwd) }

        var output = relativized.joined(separator: "\n")
        if output.isEmpty { output = "No files matched" }
        if truncated { output += "\n(Results are truncated. Consider using a more specific path or pattern.)" }

        return ToolResult(content: output)
    }

    private func enumerateFiles(in directory: String, matching predicate: (String) -> Bool) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var results: [String] = []
        while let file = enumerator.nextObject() as? String {
            let components = (file as NSString).pathComponents
            if components.contains(where: { Self.vcsDirs.contains($0) || Self.skipDirs.contains($0) }) { continue }
            if predicate(file) {
                results.append("\(directory)/\(file)")
                if results.count >= Self.maxResults { break }
            }
        }
        return results.sorted()
    }

    // MARK: - Helpers

    private func relativize(_ path: String, from cwd: String) -> String {
        if path.hasPrefix(cwd + "/") {
            return String(path.dropFirst(cwd.count + 1))
        }
        return path
    }

    private func findRipgrep() -> String? {
        let paths = [
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg",
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "rg"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        } catch {}
        return nil
    }
}
