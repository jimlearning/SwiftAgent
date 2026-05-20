import Foundation

/// Performs exact string replacements in an existing file.
/// Mirrors Claude Code's FileEditTool with replace_all, staleness detection, and smart matching.
public struct FileEditTool: Tool {
    public init() {}
    public let name = "Edit"
    public var searchHint: String? { "modify file contents in place" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Performs exact string replacements in an existing file." }
    public let interruptBehavior = InterruptBehavior.cancel
    public let isConcurrencySafe = false

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "The absolute path to the file to modify"),
            "old_string": JSONSchemaProperty(type: "string", description: "The text to replace"),
            "new_string": JSONSchemaProperty(type: "string", description: "The text to replace it with (must be different from old_string)"),
            "replace_all": JSONSchemaProperty(type: "boolean", description: "Replace all occurrences of old_string (default false)"),
        ], required: ["file_path", "old_string", "new_string"])
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let path) = input["file_path"],
              case .string(let old) = input["old_string"],
              case .string(let new) = input["new_string"] else {
            return ToolResult(content: "Error: file_path, old_string, and new_string are required", isError: true)
        }

        guard old != new else {
            return ToolResult(content: "Error: old_string and new_string must be different", isError: true)
        }

        let replaceAll = input["replace_all"].flatMap { if case .bool(let b) = $0 { return b }; return nil } ?? false
        let fm = FileManager.default

        // Empty old_string = new file creation (matching CC behavior)
        if old.isEmpty {
            guard !fm.fileExists(atPath: path) else {
                return ToolResult(content: "Error: Cannot create new file - file already exists at \(path)", isError: true)
            }
            do {
                let dir = (path as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try new.write(toFile: path, atomically: true, encoding: .utf8)
                let lineCount = new.components(separatedBy: "\n").count
                return ToolResult(content: "Created new file at \(path) (\(lineCount) lines, \(new.count) bytes)")
            } catch {
                return ToolResult(content: "Error creating file: \(error.localizedDescription)", isError: true)
            }
        }

        // Must be an existing file for edits
        guard fm.fileExists(atPath: path) else {
            return ToolResult(content: "Error: file not found at \(path)", isError: true)
        }

        // Reject notebook edits
        if path.hasSuffix(".ipynb") {
            return ToolResult(content: "Error: Use NotebookEditTool for .ipynb files", isError: true)
        }

        do {
            let original = try String(contentsOfFile: path, encoding: .utf8)

            // Staleness check
            let currentHash = original.hashValue
            if await FileEditTool.checkStaleness(filePath: path, currentHash: currentHash) {
                return ToolResult(content: "Warning: \(path) has been modified since it was last read. The file on disk may contain changes not reflected in the old_string match.", isError: true)
            }

            // Find matching string (try exact first, then smart matching)
            let found: String
            if original.contains(old) {
                found = old
            } else if let smart = findActualString(in: original, target: old) {
                found = smart
            } else {
                // Try similar file with different extension (matching CC behavior)
                if let alternative = findAlternativeFile(for: path, with: old) {
                    return ToolResult(content: "Error: old_string not found in \(path), but found in similar file: \(alternative)", isError: true)
                }
                return ToolResult(content: "Error: old_string not found in file. Make sure the text matches exactly, including whitespace.", isError: true)
            }

            let count = original.components(separatedBy: found).count - 1

            if !replaceAll && count > 1 {
                return ToolResult(content: "Error: \(count) occurrences of old_string found. Use more context to make the match unique, or use replace_all to replace all occurrences.", isError: true)
            }

            // Backup before edit (matching CC idempotent v1 backup)
            let backupPath = path + ".swiftagent-bak"
            try? original.write(toFile: backupPath, atomically: true, encoding: .utf8)

            let modified: String
            if replaceAll {
                modified = original.replacingOccurrences(of: found, with: new)
            } else {
                guard let range = original.range(of: found) else {
                    return ToolResult(content: "Error: old_string not found in file", isError: true)
                }
                modified = original.replacingCharacters(in: range, with: new)
            }

            try modified.write(toFile: path, atomically: true, encoding: .utf8)

            // Update read hash cache
            await FileEditTool.registerRead(filePath: path, contentHash: modified.hashValue)

            let linesChanged = computeLineDiff(original: original, modified: modified)

            if replaceAll {
                return ToolResult(content: "Replaced \(count) occurrences in \(path)\(linesChanged)")
            }
            return ToolResult(content: "Edited \(path)\(linesChanged)")
        } catch {
            return ToolResult(content: "Error editing file: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Protocol overrides

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return "Editing \(path)"
        }
        return nil
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return "Editing \((path as NSString).lastPathComponent)"
        }
        return "Editing file"
    }

    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any {
        if case .string(let path) = input["file_path"] ?? input["path"],
           case .string(let new) = input["new_string"] {
            return "\(path): \(new.prefix(80))"
        }
        return ""
    }

    // MARK: - Read hash cache (actor-protected)

    private static let hashCache = FileEditHashCache()

    static func registerRead(filePath: String, contentHash: Int) async {
        await hashCache.set(filePath, hash: contentHash)
    }

    static func checkStaleness(filePath: String, currentHash: Int) async -> Bool {
        guard let cached = await hashCache.get(filePath) else { return false }
        return cached != currentHash
    }

    // MARK: - Helpers

    /// Compute a human-readable line count diff.
    private func computeLineDiff(original: String, modified: String) -> String {
        let oldLines = original.components(separatedBy: "\n").count
        let newLines = modified.components(separatedBy: "\n").count
        let delta = newLines - oldLines
        if delta == 0 { return "" }
        let sign = delta >= 0 ? "+" : ""
        return " (\(newLines) lines [\(sign)\(delta)])"
    }

    /// Attempt smart matching for curly/smart quotes normalization.
    private func findActualString(in content: String, target: String) -> String? {
        let normalized = target
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{0060}", with: "`")

        if normalized != target && content.contains(normalized) {
            return normalized
        }

        let smartened = target.replacingOccurrences(of: "\"", with: "\u{201C}")
        if smartened != target && content.contains(smartened) {
            return smartened
        }

        return nil
    }

    /// Search for similar files with different extensions (matching CC behavior).
    private func findAlternativeFile(for path: String, with content: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }

        for entry in entries where entry.hasPrefix(baseName) && entry != (path as NSString).lastPathComponent {
            let altPath = (dir as NSString).appendingPathComponent(entry)
            if let altContent = try? String(contentsOfFile: altPath, encoding: .utf8),
               altContent.contains(content) {
                return altPath
            }
        }
        return nil
    }
}

// MARK: - Hash cache actor

private actor FileEditHashCache {
    private var cache: [String: Int] = [:]

    func get(_ path: String) -> Int? { cache[path] }
    func set(_ path: String, hash: Int) { cache[path] = hash }
}
