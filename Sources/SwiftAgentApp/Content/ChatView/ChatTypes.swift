import Foundation
import SwiftUI
import SwiftAgentCore

// MARK: - ChatDisplayMessage (view-model adapter wrapping AgentMessage)

/// Adapter that presents `AgentMessage` in the shape ClarcChatKit views expect.
/// Pre-computes blocks at init time for performance and pairs tool_use + tool_result
/// into single merged ChatToolCall entries.
struct ChatDisplayMessage: Identifiable, Equatable {
    let source: AgentMessage
    let blocks: [ChatMessageBlock]

    init(source: AgentMessage) {
        self.source = source
        let buildStart = Date()
        self.blocks = ChatDisplayMessage.buildBlocks(from: source.blocks)
        ChatPerfLogger.buildBlocksEnd(
            resultCount: self.blocks.count,
            elapsedMs: Date().timeIntervalSince(buildStart) * 1000
        )
    }

    /// Pairs tool_use + tool_result blocks by toolUseID so each ChatToolCall
    /// carries both the input (name, params) and the output (result).
    private static func buildBlocks(from agentBlocks: [AgentMessageBlock]) -> [ChatMessageBlock] {
        ChatPerfLogger.buildBlocksBegin(msgId: "", blockCount: agentBlocks.count)
        var result: [ChatMessageBlock] = []
        var toolUseIndexByID: [String: Int] = [:]

        for block in agentBlocks {
            switch block {
            case .toolUse(let tu):
                let tc = ChatToolCall(toolUse: tu)
                toolUseIndexByID[tu.toolUseID] = result.count
                result.append(.toolCall(tc))
            case .toolResult(let tr):
                if let idx = toolUseIndexByID[tr.toolUseID],
                   let existingTC = result[idx].toolCall {
                    result[idx] = .toolCall(existingTC.withResult(tr))
                }
                // Orphaned results (no matching tool_use) are dropped
            case .text(let text):
                result.append(.text(text, id: UUID().uuidString))
            case .thinking(let text, _):
                result.append(.thinking(text))
            case .systemReminder(let text):
                result.append(.text(text, id: UUID().uuidString))
            }
        }
        return result
    }

    var id: String { source.id }
    var role: ChatRole {
        switch source.role {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .assistant
        }
    }
    var content: String {
        source.blocks.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }
    var isStreaming: Bool { source.isStreaming }
    var isError: Bool {
        if case .failed = threadState { return true }
        return false
    }
    var isCompactBoundary: Bool { false }
    var isResponseComplete: Bool {
        !source.isStreaming && source.blocks.contains { block in
            if case .text = block { return true }
            return false
        }
    }
    var duration: TimeInterval? { nil }
    var attachmentPaths: [AttachmentInfo] { [] }

    var threadState: ThreadState = .idle

    static func == (lhs: ChatDisplayMessage, rhs: ChatDisplayMessage) -> Bool {
        lhs.id == rhs.id && lhs.source.renderToken == rhs.source.renderToken
    }
}

enum ChatRole { case user, assistant }

// MARK: - ChatMessageBlock

enum ChatMessageBlock: Identifiable {
    case text(String, id: String)
    case toolCall(ChatToolCall)
    case thinking(String, duration: TimeInterval? = nil, isRedacted: Bool = false)

    var id: String {
        switch self {
        case .text(_, let id): return id
        case .toolCall(let tc): return tc.id
        case .thinking(let text, _, _): return "thinking:\(text.hashValue)"
        }
    }

    var text: String? {
        if case .text(let t, _) = self { return t }
        return nil
    }
    var toolCall: ChatToolCall? {
        if case .toolCall(let tc) = self { return tc }
        return nil
    }
    var isText: Bool { if case .text = self { return true }; return false }
    var isThinking: Bool { if case .thinking = self { return true }; return false }
    var thinking: String? {
        if case .thinking(let t, _, _) = self { return t }
        return nil
    }
    var thinkingDuration: TimeInterval? {
        if case .thinking(_, let d, _) = self { return d }
        return nil
    }
    var isThinkingRedacted: Bool {
        if case .thinking(_, _, let r) = self { return r }
        return false
    }
}


// MARK: - ChatToolCall

struct ChatToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    let input: JSONValue
    let result: String?
    let isError: Bool
    let isKeepAlways: Bool
    let hasNonEmptyResult: Bool

    init(toolUse: ToolUseBlock) {
        self.id = toolUse.toolUseID
        self.name = toolUse.toolName
        self.input = toolUse.rawInput ?? .object([:])
        self.result = nil
        self.isError = false
        self.isKeepAlways = ["Edit", "Write", "MultiEdit", "Agent", "AskUserQuestion", "Skill"].contains(toolUse.toolName)
        self.hasNonEmptyResult = false
    }

    /// Create a copy with the result merged from a corresponding ToolResultBlock.
    func withResult(_ tr: ToolResultBlock) -> ChatToolCall {
        ChatToolCall(
            id: self.id,
            name: self.name,
            input: self.input,
            result: tr.content,
            isError: tr.isError,
            isKeepAlways: self.isKeepAlways,
            hasNonEmptyResult: !tr.content.isEmpty
        )
    }

    // Private full init for withResult
    private init(id: String, name: String, input: JSONValue, result: String?, isError: Bool, isKeepAlways: Bool, hasNonEmptyResult: Bool) {
        self.id = id
        self.name = name
        self.input = input
        self.result = result
        self.isError = isError
        self.isKeepAlways = isKeepAlways
        self.hasNonEmptyResult = hasNonEmptyResult
    }
}

// MARK: - ToolCategory

struct ToolCategory: Equatable {
    enum Kind { case readOnly, execution, fileModification, mcp, unknown }
    let kind: Kind

    init(toolName: String) {
        switch toolName.lowercased() {
        case "read", "grep", "glob": self.kind = .readOnly
        case "bash", "powershell": self.kind = .execution
        case "edit", "multiedit", "multi_edit", "write", "notebookedit": self.kind = .fileModification
        default:
            if toolName.hasPrefix("mcp__") { self.kind = .mcp }
            else { self.kind = .unknown }
        }
    }

    var isTransient: Bool {
        kind == .readOnly || kind == .execution
    }

    var sfSymbol: String {
        switch kind {
        case .readOnly: return "magnifyingglass"
        case .execution: return "terminal"
        case .fileModification: return "pencil"
        case .mcp: return "server.rack"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Supporting Types

struct AttachmentInfo: Equatable {
    let path: String
    let name: String
    let isImage: Bool
}

struct Attachment: Identifiable, Equatable {
    enum AttachmentType: Equatable { case image, file, text, url }
    let id = UUID()
    var type: AttachmentType
    var name: String
    var path: String = ""
    var imageData: Data? = nil
    var url: URL? = nil
}

struct QueuedMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var attachments: [Attachment]
}

struct PreviewFile: Identifiable {
    let id = UUID()
    var path: String
    var name: String
    var editHunks: [EditHunk] = []

    struct EditHunk {
        let oldString: String
        let newString: String
    }
}

struct RateLimitUsage {
    let fiveHourPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayPercent: Double?
    let sevenDayResetsAt: Date?
}

struct ChatSessionStats {
    var durationMs: Double = 0
}

struct AttachmentAutoPreviewSettings {
    var image: Bool = true
    var filePath: Bool = true
    var url: Bool = true
    var longText: Bool = true
}

// MARK: - InteractiveTerminalState (referenced by ToolResultView)

enum InteractiveTerminalState {
    static let toolName = "interactive_terminal"
}

// MARK: - Duration formatting

extension TimeInterval {
    var formattedDuration: String {
        if self < 1 { return "< 1s" }
        if self < 60 { return String(format: "%.0fs", self) }
        let min = Int(self) / 60
        let sec = Int(self) % 60
        if min < 60 { return "\(min)m \(sec)s" }
        let hr = min / 60
        let remainingMin = min % 60
        return "\(hr)h \(remainingMin)m"
    }
}

// MARK: - JSONValue subscript helper

extension JSONValue {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}

// MARK: - View extension helpers

extension View {
    func pointerCursorOnHover() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Color hex init (for PulseRingView)

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - SlashCommand adapter (wraps existing SlashCommandDefinition)

/// Adapter that wraps the existing `SlashCommandDefinition` to match
/// the interface expected by ported ClarcChatKit views (InputBarView).
struct SlashCommandAdapter: Identifiable, Equatable {
    let definition: SlashCommandDefinition
    var id: String { definition.id }
    var command: String { definition.command }
    var acceptsInput: Bool { !definition.arguments.isEmpty }
    var isInteractive: Bool { false }
}

/// Bridge registry that maps existing `SlashCommandRegistry` to the
/// interface used by ported views.
@MainActor
enum SlashCommandFilter {
    static func filtered(by query: String) -> [SlashCommandAdapter] {
        let all = SlashCommandRegistry.all
        guard query.hasPrefix("/") else { return [] }
        let q = String(query.dropFirst()).lowercased()
        if q.isEmpty { return all.map(SlashCommandAdapter.init) }
        return all.filter { $0.command.lowercased().contains(q) }.map(SlashCommandAdapter.init)
    }
}

// MARK: - AtFileEntry

struct AtFileEntry: Identifiable {
    let id: String          // relativePath
    let name: String        // file name
    let directory: String   // parent directory path
    let relativePath: String
}

// MARK: - AtFileSearch

enum AtFileSearch {
    private nonisolated static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData",
        "node_modules", ".DS_Store", "Pods",
        "xcuserdata", ".xcodeproj", ".xcworkspace",
    ]

    nonisolated(unsafe) private static var fileListCache: [String: [AtFileEntry]] = [:]

    static func search(query: String, projectPath: String, maxResults: Int = 20) -> [AtFileEntry] {
        guard !projectPath.isEmpty else { return [] }
        let allFiles: [AtFileEntry]
        if let cached = fileListCache[projectPath] {
            allFiles = cached
        } else {
            allFiles = collectFiles(at: projectPath, basePath: projectPath, maxDepth: 6)
            fileListCache[projectPath] = allFiles
        }

        let q = query.lowercased()
        guard !q.isEmpty else { return Array(allFiles.prefix(maxResults)) }

        var nameMatches: [AtFileEntry] = []
        var pathMatches: [AtFileEntry] = []

        for entry in allFiles {
            if entry.name.lowercased().contains(q) {
                nameMatches.append(entry)
            } else if entry.relativePath.lowercased().contains(q) {
                pathMatches.append(entry)
            }
        }

        return Array((nameMatches + pathMatches).prefix(maxResults))
    }

    private nonisolated static func collectFiles(
        at path: String,
        basePath: String,
        maxDepth: Int,
        currentDepth: Int = 0
    ) -> [AtFileEntry] {
        guard currentDepth <= maxDepth else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [AtFileEntry] = []

        for url in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                results += collectFiles(
                    at: url.path,
                    basePath: basePath,
                    maxDepth: maxDepth,
                    currentDepth: currentDepth + 1
                )
            } else {
                let relativePath = String(url.path.dropFirst(basePath.count + 1))
                let directory = (relativePath as NSString).deletingLastPathComponent
                results.append(AtFileEntry(
                    id: relativePath,
                    name: name,
                    directory: directory,
                    relativePath: relativePath
                ))
            }
        }

        return results
    }
}
