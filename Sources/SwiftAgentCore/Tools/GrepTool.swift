import Foundation

/// Searches for a regular expression pattern in file contents.
/// Uses ripgrep (rg) when available; falls back to Foundation-based regex search.
/// Mirrors Claude Code's GrepTool with full ripgrep parameter support.
public struct GrepTool: Tool {
    public init() {}

    // MARK: - Tool Identity

    public let name = "Grep"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "A powerful search tool built on ripgrep" }
    public var searchHint: String? { "search file contents with regex (ripgrep)" }
    public var isReadOnly: Bool { true }
    public var isConcurrencySafe: Bool { true }
    public var maxResultSizeChars: Int { 20_000 }
    public var strict: Bool { true }

    // MARK: - Input Schema

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "pattern": JSONSchemaProperty(type: "string", description: "The regular expression pattern to search for in file contents"),
            "path": JSONSchemaProperty(type: "string", description: "File or directory to search in (rg PATH). Defaults to current working directory."),
            "glob": JSONSchemaProperty(type: "string", description: "Glob pattern to filter files (e.g. \"*.js\", \"**/*.tsx\") - maps to rg --glob"),
            "output_mode": JSONSchemaProperty(type: "string", description: "Output mode: \"content\" shows matching lines (supports -A/-B/-C context, -n line numbers, head_limit), \"files_with_matches\" shows file paths (supports head_limit), \"count\" shows match counts (supports head_limit). Defaults to \"files_with_matches\".",
                enum: ["content", "files_with_matches", "count"]),
            "-B": JSONSchemaProperty(type: "number", description: "Number of lines to show before each match (rg -B). Requires output_mode: \"content\", ignored otherwise."),
            "-A": JSONSchemaProperty(type: "number", description: "Number of lines to show after each match (rg -A). Requires output_mode: \"content\", ignored otherwise."),
            "-C": JSONSchemaProperty(type: "number", description: "Alias for context."),
            "context": JSONSchemaProperty(type: "number", description: "Number of lines to show before and after each match (rg -C). Requires output_mode: \"content\", ignored otherwise."),
            "-n": JSONSchemaProperty(type: "boolean", description: "Show line numbers in output. Requires output_mode: \"content\", ignored otherwise. Defaults to true."),
            "-i": JSONSchemaProperty(type: "boolean", description: "Case insensitive search (rg -i)"),
            "type": JSONSchemaProperty(type: "string", description: "File type to search (rg --type). Common types: js, py, rust, go, java, etc. More efficient than include for standard file types."),
            "head_limit": JSONSchemaProperty(type: "number", description: "Limit output to first N lines/entries, equivalent to \"| head -N\". Works across all output modes. Defaults to 250. Pass 0 for unlimited."),
            "offset": JSONSchemaProperty(type: "number", description: "Skip first N lines/entries before applying head_limit, equivalent to \"| tail -n +N | head -N\". Defaults to 0."),
            "multiline": JSONSchemaProperty(type: "boolean", description: "Enable multiline mode where . matches newlines and patterns can span lines (rg -U --multiline-dotall). Default: false."),
            "-o": JSONSchemaProperty(type: "boolean", description: "Print only the matched (non-empty) parts of each matching line, one match per output line (rg -o / --only-matching). Requires output_mode: \"content\", ignored otherwise. Defaults to false."),
        ], required: ["pattern"])
    }

    public var outputSchema: JSONSchema? {
        JSONSchema(type: "object", properties: [
            "mode": JSONSchemaProperty(type: "string", enum: ["content", "files_with_matches", "count"]),
            "numFiles": JSONSchemaProperty(type: "number"),
            "filenames": JSONSchemaProperty(type: "array", description: "Array of matching file paths"),
            "content": JSONSchemaProperty(type: "string"),
            "numLines": JSONSchemaProperty(type: "number"),
            "numMatches": JSONSchemaProperty(type: "number"),
            "appliedLimit": JSONSchemaProperty(type: "number"),
            "appliedOffset": JSONSchemaProperty(type: "number"),
        ])
    }

    // MARK: - Tool Protocol Overrides

    public func isSearchOrReadCommand(_ input: [String: JSONValue]) -> SearchOrReadResult {
        SearchOrReadResult(isSearch: true)
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        guard case .string(let pattern) = input["pattern"] else { return nil }
        return "Searching for \(pattern)"
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        guard case .string(let pattern) = input["pattern"] else { return "Searching" }
        return "Searching for \(pattern)"
    }

    public func userFacingName(_ input: [String: JSONValue]) -> String {
        "Search"
    }

    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any {
        guard case .string(let pattern) = input["pattern"] else { return "" }
        if case .string(let path) = input["path"] {
            return "\(pattern) in \(path)"
        }
        return pattern
    }

    public func getPath(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["path"] {
            return path
        }
        return input.stringValue("file_path")
    }

    // MARK: - Execute

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let pattern) = input["pattern"] else {
            return ToolResult(content: "Error: pattern is required", isError: true)
        }

        let searchPath: String
        if case .string(let customPath) = input["path"] {
            searchPath = expandPath(customPath, relativeTo: context.workingDirectory)
        } else {
            searchPath = context.workingDirectory
        }

        let outputMode = GrepOutputMode(rawValue: input.stringValue("output_mode") ?? "files_with_matches") ?? .filesWithMatches
        let headLimit = input.intValue("head_limit")
        let offset = input.intValue("offset") ?? 0
        let showLineNumbers = input.boolValue("-n") ?? true
        let caseInsensitive = input.boolValue("-i") ?? false
        let multiline = input.boolValue("multiline") ?? false
        let onlyMatching = input.boolValue("-o") ?? false
        let contextLines = input.intValue("context") ?? input.intValue("-C")
        let linesBefore = input.intValue("-B")
        let linesAfter = input.intValue("-A")
        let typeFilter = input.stringValue("type")
        let fileGlob = input.stringValue("glob")

        let globPatterns: [String]
        if let fileGlob { globPatterns = parseGlobPatterns(fileGlob) }
        else { globPatterns = [] }

        // Try ripgrep first
        if let rgPath = findRipgrep() {
            return try executeRipgrep(
                pattern: pattern,
                searchPath: searchPath,
                outputMode: outputMode,
                headLimit: headLimit,
                offset: offset,
                showLineNumbers: showLineNumbers,
                caseInsensitive: caseInsensitive,
                multiline: multiline,
                onlyMatching: onlyMatching,
                contextLines: contextLines,
                linesBefore: linesBefore,
                linesAfter: linesAfter,
                typeFilter: typeFilter,
                globPatterns: globPatterns,
                rgPath: rgPath,
                context: context
            )
        }

        // Fall back to Foundation-based search
        return try executeFoundation(
            pattern: pattern,
            searchPath: searchPath,
            outputMode: outputMode,
            headLimit: headLimit,
            offset: offset,
            showLineNumbers: showLineNumbers,
            caseInsensitive: caseInsensitive,
            multiline: multiline,
            onlyMatching: onlyMatching,
            contextLines: contextLines,
            linesBefore: linesBefore,
            linesAfter: linesAfter,
            typeFilter: typeFilter,
            globPatterns: globPatterns,
            context: context
        )
    }

    // MARK: - Ripgrep Execution

    private func executeRipgrep(
        pattern: String,
        searchPath: String,
        outputMode: GrepOutputMode,
        headLimit: Int?,
        offset: Int,
        showLineNumbers: Bool,
        caseInsensitive: Bool,
        multiline: Bool,
        onlyMatching: Bool,
        contextLines: Int?,
        linesBefore: Int?,
        linesAfter: Int?,
        typeFilter: String?,
        globPatterns: [String],
        rgPath: String,
        context toolContext: ToolUseContext
    ) throws -> ToolResult {
        var args = ["--hidden"]

        // Exclude VCS directories
        for dir in VCS_DIRECTORIES {
            args.append(contentsOf: ["--glob", "!\(dir)"])
        }

        // Limit line length to prevent base64/minified content cluttering output
        args.append(contentsOf: ["--max-columns", "500"])

        // Multiline mode
        if multiline {
            args.append(contentsOf: ["-U", "--multiline-dotall"])
        }

        // Case insensitive
        if caseInsensitive {
            args.append("-i")
        }

        // Output mode
        switch outputMode {
        case .filesWithMatches:
            args.append("-l")
        case .count:
            args.append("-c")
        case .content:
            break
        }

        // Line numbers (content mode only)
        if showLineNumbers && outputMode == .content {
            args.append("-n")
        }

        // Only matching (content mode only)
        if onlyMatching && outputMode == .content {
            args.append("-o")
        }

        // Context flags (content mode only)
        if outputMode == .content {
            if let c = contextLines {
                args.append(contentsOf: ["-C", "\(c)"])
            } else {
                if let b = linesBefore {
                    args.append(contentsOf: ["-B", "\(b)"])
                }
                if let a = linesAfter {
                    args.append(contentsOf: ["-A", "\(a)"])
                }
            }
        }

        // Pattern (use -e if starts with dash)
        if pattern.hasPrefix("-") {
            args.append(contentsOf: ["-e", pattern])
        } else {
            args.append(pattern)
        }

        // Type filter
        if let type = typeFilter {
            args.append(contentsOf: ["--type", type])
        }

        // Glob patterns
        for g in globPatterns {
            args.append(contentsOf: ["--glob", g])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rgPath)
        process.arguments = args + [searchPath]
        process.currentDirectoryURL = URL(fileURLWithPath: searchPath)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ToolResult(content: "Error executing rg: \(error.localizedDescription)", isError: true)
        }

        let outputBuffer = LockedProcessBuffer()
        let errorBuffer = LockedProcessBuffer()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBuffer.append(outPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBuffer.append(errPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()

        let outputData = outputBuffer.data()
        let errData = errorBuffer.data()
        let outputStr = String(data: outputData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        // Handle errors
        if process.terminationStatus == 2 {
            return ToolResult(content: "Error: \(errStr.isEmpty ? "ripgrep error" : errStr)", isError: true)
        }

        let rawLines = outputStr
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        let effectiveHeadLimit = headLimit ?? DEFAULT_HEAD_LIMIT

        switch outputMode {
        case .content:
            let (items, appliedLimit) = applyHeadLimit(rawLines, limit: effectiveHeadLimit, offset: offset)
            let finalLines = items.map { relativizePathInLine($0, from: toolContext.workingDirectory) }
            let result = finalLines.joined(separator: "\n")
            if result.isEmpty {
                return ToolResult(content: "No matches found")
            }
            var suffix = ""
            if let lim = appliedLimit { suffix += "\n\n[Showing results with pagination = limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")]" }
            return ToolResult(content: result + suffix)

        case .count:
            let (items, appliedLimit) = applyHeadLimit(rawLines, limit: effectiveHeadLimit, offset: offset)
            let finalLines = items.map { relativizePathInLine($0, from: toolContext.workingDirectory) }
            let (totalMatches, fileCount) = parseCountLines(finalLines)
            let result = finalLines.joined(separator: "\n")
            if result.isEmpty {
                return ToolResult(content: "No matches found")
            }
            let summary = "\n\nFound \(totalMatches) total \(totalMatches == 1 ? "occurrence" : "occurrences") across \(fileCount) \(fileCount == 1 ? "file" : "files")."
            var pagination = ""
            if let lim = appliedLimit { pagination = " with pagination = limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")" }
            return ToolResult(content: result + summary + pagination)

        case .filesWithMatches:
            let (items, appliedLimit) = applyHeadLimit(rawLines, limit: effectiveHeadLimit, offset: offset)
            let finalFiles = items.map { relativizePath($0, from: toolContext.workingDirectory) }
            if finalFiles.isEmpty {
                return ToolResult(content: "No files found")
            }
            let prefix = "Found \(finalFiles.count) \(finalFiles.count == 1 ? "file" : "files")"
            var suffix = ""
            if let lim = appliedLimit { suffix = " limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")" }
            return ToolResult(content: prefix + suffix + "\n" + finalFiles.joined(separator: "\n"))
        }
    }

    // MARK: - Foundation-based Search (fallback)

    private func executeFoundation(
        pattern: String,
        searchPath: String,
        outputMode: GrepOutputMode,
        headLimit: Int?,
        offset: Int,
        showLineNumbers: Bool,
        caseInsensitive: Bool,
        multiline: Bool,
        onlyMatching: Bool,
        contextLines: Int?,
        linesBefore: Int?,
        linesAfter: Int?,
        typeFilter: String?,
        globPatterns: [String],
        context toolContext: ToolUseContext
    ) throws -> ToolResult {
        var regexOptions: NSRegularExpression.Options = []
        if caseInsensitive { regexOptions.insert(.caseInsensitive) }
        if multiline { regexOptions.insert(.dotMatchesLineSeparators) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return ToolResult(content: "Error: invalid regular expression: \(pattern)", isError: true)
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let pathExists = fm.fileExists(atPath: searchPath, isDirectory: &isDir)

        let files: [String]
        if pathExists && !isDir.boolValue {
            files = [searchPath]
        } else if pathExists {
            files = collectFiles(in: searchPath, globPatterns: globPatterns, typeFilter: typeFilter)
        } else {
            return ToolResult(content: "Error: path not found: \(searchPath)", isError: true)
        }

        var allMatches: [(file: String, line: Int, content: String)] = []

        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                if line.count > 500 { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    allMatches.append((relativizePath(file, from: toolContext.workingDirectory), i + 1, line))
                }
            }
        }

        let effectiveHeadLimit = headLimit ?? DEFAULT_HEAD_LIMIT
        let startIdx = min(offset, allMatches.count)
        let endIdx: Int
        if effectiveHeadLimit == 0 {
            endIdx = allMatches.count
        } else {
            endIdx = min(startIdx + effectiveHeadLimit, allMatches.count)
        }
        let limited = Array(allMatches[startIdx..<endIdx])
        let wasTruncated = allMatches.count - startIdx > (effectiveHeadLimit == 0 ? allMatches.count : effectiveHeadLimit)
        let appliedLimit = wasTruncated ? effectiveHeadLimit : nil

        var paginationSuffix = ""
        if let lim = appliedLimit { paginationSuffix += "\n\n[Showing results with pagination = limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")]" }

        switch outputMode {
        case .filesWithMatches:
            var seen = Set<String>()
            let files = limited.map { $0.file }.filter { seen.insert($0).inserted }
            let result = files.joined(separator: "\n")
            if result.isEmpty { return ToolResult(content: "No files found") }
            let prefix = "Found \(files.count) \(files.count == 1 ? "file" : "files")"
            var suffix = ""
            if let lim = appliedLimit { suffix = " limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")" }
            return ToolResult(content: prefix + suffix + "\n" + result)

        case .count:
            var counts: [String: Int] = [:]
            for match in limited {
                counts[match.file, default: 0] += 1
            }
            let lines = counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }
            let result = lines.joined(separator: "\n")
            if result.isEmpty { return ToolResult(content: "No matches found") }
            let total = counts.values.reduce(0, +)
            let summary = "\n\nFound \(total) total \(total == 1 ? "occurrence" : "occurrences") across \(counts.count) \(counts.count == 1 ? "file" : "files")."
            var pagination = ""
            if let lim = appliedLimit { pagination = " with pagination = limit: \(lim)\(offset > 0 ? ", offset: \(offset)" : "")" }
            return ToolResult(content: result + summary + pagination)

        case .content:
            var output: [String] = []
            let before = linesBefore ?? 0
            let after = linesAfter ?? contextLines ?? 0

            for match in limited {
                if before > 0 || after > 0 {
                    let ctx = buildContext(file: match.file, line: match.line, lineContent: match.content,
                                          before: before, after: after, searchPath: searchPath,
                                          workingDir: toolContext.workingDirectory)
                    output.append(ctx)
                } else if showLineNumbers {
                    output.append("\(match.file):\(match.line):\(match.content)")
                } else {
                    output.append("\(match.file):\(match.content)")
                }
            }
            let result = output.joined(separator: "\n")
            return ToolResult(content: result.isEmpty ? "No matches found" : result + paginationSuffix)
        }
    }

    // MARK: - Utilities

    /// Attempts to locate the `rg` binary.
    private func findRipgrep() -> String? {
        let paths = [
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg",
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try which
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
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }

    /// Resolve a relative or absolute path.
    private func expandPath(_ path: String, relativeTo cwd: String) -> String {
        if path.hasPrefix("/") { return path }
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return (cwd as NSString).appendingPathComponent(path)
    }

    /// Make a path relative to the working directory.
    private func relativizePath(_ path: String, from cwd: String) -> String {
        guard cwd.hasSuffix("/") || path.hasPrefix(cwd + "/") else {
            if path.hasPrefix(cwd) && path.count > cwd.count {
                let idx = path.index(path.startIndex, offsetBy: cwd.count)
                if path[idx] == "/" {
                    return String(path[path.index(after: idx)...])
                }
            }
            return path
        }
        let cwdSlash = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if path.hasPrefix(cwdSlash) {
            return String(path.dropFirst(cwdSlash.count))
        }
        return path
    }

    /// Relativize a path embedded in a ripgrep output line (format: /path:content or /path:line:content).
    private func relativizePathInLine(_ line: String, from cwd: String) -> String {
        let colonIndex = line.firstIndex(of: ":") ?? line.startIndex
        if colonIndex > line.startIndex {
            let filePath = String(line[line.startIndex..<colonIndex])
            let rest = String(line[colonIndex...])
            return relativizePath(filePath, from: cwd) + rest
        }
        return line
    }

    /// Apply head_limit and offset to an array.
    private func applyHeadLimit<T>(_ items: [T], limit: Int, offset: Int) -> (items: [T], appliedLimit: Int?) {
        if limit == 0 {
            return (Array(items.dropFirst(offset)), nil)
        }
        let startIdx = min(offset, items.count)
        let endIdx = min(startIdx + limit, items.count)
        let sliced = Array(items[startIdx..<endIdx])
        let wasTruncated = items.count - startIdx > limit
        return (sliced, wasTruncated ? limit : nil)
    }

    /// Parse count lines (format: "path:count") into total matches and file count.
    private func parseCountLines(_ lines: [String]) -> (totalMatches: Int, fileCount: Int) {
        var total = 0
        var files = 0
        for line in lines {
            if let lastColon = line.lastIndex(of: ":"), lastColon < line.index(before: line.endIndex) {
                let countStr = String(line[line.index(after: lastColon)...])
                if let count = Int(countStr) {
                    total += count
                    files += 1
                }
            }
        }
        return (total, files)
    }

    /// Parse glob string into individual patterns (splitting on commas/whitespace, preserving braces).
    private func parseGlobPatterns(_ glob: String) -> [String] {
        var result: [String] = []
        let rawPatterns = glob.components(separatedBy: .whitespaces)
        for raw in rawPatterns {
            if raw.isEmpty { continue }
            if raw.contains("{") && raw.contains("}") {
                result.append(raw)
            } else {
                result.append(contentsOf: raw.components(separatedBy: ",").filter { !$0.isEmpty })
            }
        }
        return result
    }

    /// Collect files in a directory, respecting glob and type filters.
    private func collectFiles(in directory: String, globPatterns: [String], typeFilter: String?) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var results: [String] = []
        while let fileRel = enumerator.nextObject() as? String {
            let components = (fileRel as NSString).pathComponents
            if components.contains(where: { VCS_DIRECTORIES.contains($0) }) { continue }
            if !globPatterns.isEmpty {
                let filename = (fileRel as NSString).lastPathComponent
                if !globPatterns.contains(where: { fnmatchGlob($0, filename) }) { continue }
            }
            if let type = typeFilter, !matchesType((fileRel as NSString).pathExtension, type) { continue }
            results.append("\(directory)/\(fileRel)")
        }
        // Sort alphabetically for determinism
        return results.sorted()
    }

    /// Match a file extension against a known type category.
    private func matchesType(_ ext: String, _ type: String) -> Bool {
        let typeMap: [String: Set<String>] = [
            "js": ["js", "jsx", "mjs", "cjs"],
            "ts": ["ts", "tsx", "mts", "cts"],
            "py": ["py", "pyi", "pyx"],
            "rust": ["rs"],
            "go": ["go"],
            "java": ["java", "kt", "kts", "scala"],
            "swift": ["swift"],
            "c": ["c", "h"],
            "cpp": ["cpp", "cc", "cxx", "hpp", "hh", "hxx"],
            "objc": ["m", "mm"],
        ]
        guard let exts = typeMap[type] else { return true }
        return exts.contains(ext.lowercased())
    }

    /// Simple fnmatch-style glob matching.
    private func fnmatchGlob(_ pattern: String, _ string: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let withStar = escaped.replacingOccurrences(of: "\\*", with: ".*")
        let withQuestion = withStar.replacingOccurrences(of: "\\?", with: ".")
        let regexPattern = "^\(withQuestion)$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    /// Build context lines around a match.
    private func buildContext(
        file: String, line: Int, lineContent: String,
        before: Int, after: Int,
        searchPath: String, workingDir: String
    ) -> String {
        let absPath = file.hasPrefix("/") ? file : "\(searchPath)/\(file)"
        guard let fileContent = try? String(contentsOfFile: absPath, encoding: .utf8) else {
            return "\(file):\(line):\(lineContent)"
        }
        let allLines = fileContent.components(separatedBy: .newlines)
        let start = max(0, line - 1 - before)
        let end = min(allLines.count, line + after)
        var result: [String] = []
        for i in start..<end {
            let prefix = (i + 1 == line) ? ">" : " "
            result.append("\(prefix)\(file):\(i + 1):\(allLines[i])")
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Constants

    /// Version control directories to exclude from searches.
    private let VCS_DIRECTORIES: Set<String> = [
        ".git", ".svn", ".hg", ".bzr", ".jj", ".sl",
    ]

    /// Default result cap when head_limit is unspecified (prevents context bloat).
    private let DEFAULT_HEAD_LIMIT = 250
}

// MARK: - GrepOutputMode

private enum GrepOutputMode: String {
    case content
    case filesWithMatches = "files_with_matches"
    case count
}

// MARK: - [String: JSONValue] helpers

extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(_ key: String) -> String? {
        guard case .string(let s) = self[key] else { return nil }
        return s
    }

    func intValue(_ key: String) -> Int? {
        guard case .number(let n) = self[key] else { return nil }
        return Int(n)
    }

    func boolValue(_ key: String) -> Bool? {
        guard case .bool(let b) = self[key] else { return nil }
        return b
    }
}

private final class LockedProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.withLock {
            storage.append(data)
        }
    }

    func data() -> Data {
        lock.withLock { storage }
    }
}
