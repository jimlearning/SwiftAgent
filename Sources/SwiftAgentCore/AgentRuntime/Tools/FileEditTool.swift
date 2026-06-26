import Foundation

/// Performs exact string replacements in an existing file.
/// Mirrors Claude Code's FileEditTool with replace_all, staleness detection, and smart matching.
public struct FileEditTool: Tool {
    public let name = "Edit"
    public let description = "Performs exact string replacements in an existing file."

    private let workingDirectory: String

    public struct Arguments: Codable, Sendable {
        public var filePath: String
        public var oldString: String
        public var newString: String
        public var replaceAll: Bool?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case oldString = "old_string"
            case newString = "new_string"
            case replaceAll = "replace_all"
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "The absolute path to the file to modify"),
            "old_string": JSONSchemaProperty(type: "string", description: "The text to replace"),
            "new_string": JSONSchemaProperty(type: "string", description: "The text to replace it with (must be different from old_string)"),
            "replace_all": JSONSchemaProperty(type: "boolean", description: "Replace all occurrences of old_string (default false)"),
        ], required: ["file_path", "old_string", "new_string"])
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let path = arguments.filePath
        let old = arguments.oldString
        let new = arguments.newString
        let replaceAll = arguments.replaceAll ?? false

        guard old != new else {
            return .string("Error: old_string and new_string must be different")
        }

        let fm = FileManager.default

        // Empty old_string = new file creation (matching CC behavior)
        if old.isEmpty {
            guard !fm.fileExists(atPath: path) else {
                return .string("Error: Cannot create new file - file already exists at \(path)")
            }
            do {
                let dir = (path as NSString).deletingLastPathComponent
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try new.write(toFile: path, atomically: true, encoding: .utf8)
                let lineCount = new.components(separatedBy: "\n").count
                return .string("Created new file at \(path) (\(lineCount) lines, \(new.count) bytes)")
            } catch {
                return .string("Error creating file: \(error.localizedDescription)")
            }
        }

        // Must be an existing file for edits
        guard fm.fileExists(atPath: path) else {
            return .string("Error: file not found at \(path)")
        }

        // Reject notebook edits
        if path.hasSuffix(".ipynb") {
            return .string("Error: Use NotebookEditTool for .ipynb files")
        }

        do {
            let original = try String(contentsOfFile: path, encoding: .utf8)

            // Staleness check
            let currentHash = original.hashValue
            if await FileEditTool.checkStaleness(filePath: path, currentHash: currentHash) {
                return .string("Warning: \(path) has been modified since it was last read. The file on disk may contain changes not reflected in the old_string match.")
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
                    return .string("Error: old_string not found in \(path), but found in similar file: \(alternative)")
                }
                return .string("Error: old_string not found in file. Make sure the text matches exactly, including whitespace.")
            }

            let count = original.components(separatedBy: found).count - 1

            if !replaceAll && count > 1 {
                return .string("Error: \(count) occurrences of old_string found. Use more context to make the match unique, or use replace_all to replace all occurrences.")
            }

            let modified: String
            if replaceAll {
                modified = original.replacingOccurrences(of: found, with: new)
            } else {
                guard let range = original.range(of: found) else {
                    return .string("Error: old_string not found in file")
                }
                modified = original.replacingCharacters(in: range, with: new)
            }

            try modified.write(toFile: path, atomically: true, encoding: .utf8)

            // Update read hash cache
            await FileEditTool.registerRead(filePath: path, contentHash: modified.hashValue)

            let linesChanged = computeLineDiff(original: original, modified: modified)

            if replaceAll {
                return .string("Replaced \(count) occurrences in \(path)\(linesChanged)")
            }
            return .string("Edited \(path)\(linesChanged)")
        } catch {
            return .string("Error editing file: \(error.localizedDescription)")
        }
    }

    // MARK: - Read hash cache

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
