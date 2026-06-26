import Foundation

/// Fast file pattern matching with glob support.
/// Uses ripgrep (rg) when available; falls back to Foundation-based search.
public struct GlobTool: Tool {
    public let name = "Glob"
    public let description = "Fast file pattern matching tool using ripgrep. Supports glob patterns like '**/*.swift'."

    private let workingDirectory: String

    private static let vcsDirs: Set<String> = [".git", ".svn", ".hg", ".bzr", ".jj", ".sl"]
    private static let maxResults = 100
    private static let skipDirs: Set<String> = [
        "node_modules", "Library", "Caches", "DerivedData",
        ".swiftpm", ".build", "Pods", "logs",
        "vendor", "bower_components", ".cache", ".npm",
        ".yarn", ".turbo", ".next", "__pycache__",
    ]

    public struct Arguments: Codable, Sendable {
        public var pattern: String
        public var path: String?

        enum CodingKeys: String, CodingKey {
            case pattern
            case path
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "pattern": JSONSchemaProperty(type: "string", description: "The glob pattern to match files against"),
            "path": JSONSchemaProperty(type: "string", description: "The directory to search in. If not specified, the current working directory will be used. IMPORTANT: Omit this field to use the default directory. Must be a valid directory path if provided."),
        ], required: ["pattern"])
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let searchPath = arguments.path ?? workingDirectory

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: searchPath, isDirectory: &isDir), isDir.boolValue else {
            return .string("Error: path is not a valid directory: \(searchPath)")
        }

        if let rgPath = findRipgrep() {
            return executeRipgrep(pattern: arguments.pattern, searchPath: searchPath, rgPath: rgPath)
        }

        return executeFoundation(pattern: arguments.pattern, searchPath: searchPath)
    }

    // MARK: - Ripgrep

    private func executeRipgrep(pattern: String, searchPath: String, rgPath: String) -> ToolOutputValue {
        var args: [String] = [
            "--files",
            "--glob", pattern,
            "--sort=modified",
            "--no-ignore",
            "--hidden",
        ]
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

        do { try process.run() } catch {
            return .string("Error executing rg: \(error.localizedDescription)")
        }

        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: outputData, encoding: .utf8) else {
            return .string("No files matched")
        }

        let allPaths = output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        let truncated = allPaths.count > Self.maxResults
        let limited = Array(allPaths.prefix(Self.maxResults))
        let relativized = limited.map { relativize($0) }

        var result = relativized.joined(separator: "\n")
        if result.isEmpty { result = "No files matched" }
        if truncated { result += "\n(Results are truncated. Consider using a more specific path or pattern.)" }

        return .string(result)
    }

    // MARK: - Foundation fallback

    private func executeFoundation(pattern: String, searchPath: String) -> ToolOutputValue {
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
                return .string("No files matched")
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
        let relativized = limited.map { relativize($0) }

        var output = relativized.joined(separator: "\n")
        if output.isEmpty { output = "No files matched" }
        if truncated { output += "\n(Results are truncated. Consider using a more specific path or pattern.)" }

        return .string(output)
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

    private func relativize(_ path: String) -> String {
        if path.hasPrefix(workingDirectory + "/") {
            return String(path.dropFirst(workingDirectory.count + 1))
        }
        return path
    }

    private func findRipgrep() -> String? {
        let paths = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]
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
