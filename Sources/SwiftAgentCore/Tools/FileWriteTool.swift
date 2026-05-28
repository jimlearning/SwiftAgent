import Foundation

/// Writes a file to the local filesystem.
/// Mirrors Claude Code's FileWriteTool with LF normalization, staleness detection, and safety checks.
public struct FileWriteTool: Tool {
    public init() {}
    public let name = "Write"
    public var searchHint: String? { "create or overwrite files" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Writes a file to the local filesystem." }
    public let interruptBehavior = InterruptBehavior.cancel
    public let isConcurrencySafe = false

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "The absolute path to the file to write (must be absolute, not relative)"),
            "content": JSONSchemaProperty(type: "string", description: "The content to write to the file"),
        ], required: ["file_path", "content"])
    }

    // CC FileWriteTool does NOT override isDestructive (defaults to false).
    // isDestructive is checked per-input by the permission system separately.

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let path) = input["file_path"],
              case .string(let content) = input["content"] else {
            return ToolResult(content: "Error: file_path and content are required", isError: true)
        }

        // Normalize to LF line endings (matching Claude Code behavior)
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let fm = FileManager.default
        let isNewFile = !fm.fileExists(atPath: path)
        let originalContent = try? String(contentsOfFile: path, encoding: .utf8)

        // Staleness check: warn if file was modified since last known read
        if !isNewFile, let original = originalContent {
            let currentHash = computeContentHash(original)
            if await FileWriteTool.checkStaleness(filePath: path, currentHash: currentHash) {
                return ToolResult(content: "Warning: \(path) has been modified since it was last read. The file on disk may contain changes that will be overwritten.", isError: true)
            }
        }

        do {
            let dir = (path as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

            try normalized.write(toFile: path, atomically: true, encoding: .utf8)

            // Update read hash cache
            await FileWriteTool.registerRead(filePath: path, contentHash: computeContentHash(normalized))

            let lineCount = normalized.components(separatedBy: "\n").count

            if isNewFile {
                return ToolResult(content: "File created successfully at \(path) (\(lineCount) lines, \(normalized.count) bytes)")
            }
            let oldLineCount = originalContent?.components(separatedBy: "\n").count ?? 0
            let delta = lineCount - oldLineCount
            let deltaStr = delta >= 0 ? "+\(delta)" : "\(delta)"
            return ToolResult(content: "File updated successfully at \(path) (\(lineCount) lines [\(deltaStr)], \(normalized.count) bytes)")
        } catch {
            return ToolResult(content: "Error writing file: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Protocol overrides

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return "Writing \(path)"
        }
        return nil
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return "Writing \((path as NSString).lastPathComponent)"
        }
        return "Writing file"
    }

    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> Any {
        if case .string(let path) = input["file_path"] ?? input["path"] {
            return "\(path): new content"
        }
        return ""
    }

    // MARK: - Read hash cache (actor-protected)

    private static let hashCache = ReadHashCache()

    private func computeContentHash(_ content: String) -> Int {
        content.hashValue
    }
}

/// Actor-protected cache for read file content hashes (staleness detection).
private actor ReadHashCache {
    private var cache: [String: Int] = [:]

    func get(_ path: String) -> Int? {
        cache[path]
    }

    func set(_ path: String, hash: Int) {
        cache[path] = hash
    }
}

extension FileWriteTool {
    /// Called by ReadTool to register that a file was read at a given hash.
    static func registerRead(filePath: String, contentHash: Int) async {
        await hashCache.set(filePath, hash: contentHash)
    }

    /// Check staleness: returns true if the file hash differs from last known read.
    static func checkStaleness(filePath: String, currentHash: Int) async -> Bool {
        guard let cached = await hashCache.get(filePath) else { return false }
        return cached != currentHash
    }
}
