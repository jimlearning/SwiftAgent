import Foundation

// MARK: - MCP Metadata

/// MCP-specific metadata attached to tool results.
/// Moved from old Tool.swift — used by Conversation.Message blocks.
public struct MCPMeta: Codable, Sendable {
    public var _meta: [String: JSONValue]?
    public var structuredContent: [String: JSONValue]?

    public init(_meta: [String: JSONValue]? = nil, structuredContent: [String: JSONValue]? = nil) {
        self._meta = _meta
        self.structuredContent = structuredContent
    }
}

// MARK: - Query Source

/// Identifies where a query originated (analytics).
public enum QuerySource: String, Sendable, Codable {
    case repl = "repl_main_thread"
    case compact = "compact"
    case sessionMemory = "session_memory"
    case agent = "agent"
    case skill = "skill"
    case slashCommand = "slash_command"
    case hook = "hook"
    case cron = "cron"
    case mcp = "mcp"
    case sdk = "sdk"
}

// MARK: - Query Chain Tracking

/// Tracks query chain identity and depth across compactions.
public struct QueryChainTracking: Sendable, Codable {
    public let depth: Int
    public let chainID: String

    public init(depth: Int = 0, chainID: String = UUID().uuidString) {
        self.depth = depth
        self.chainID = chainID
    }
}

// MARK: - Notebook Cell

/// A single cell in a Jupyter/IPYNB notebook.
public struct NotebookCell: Sendable, Codable {
    public let cellType: String
    public let source: [String]
    public let outputs: [String]?

    public init(cellType: String, source: [String], outputs: [String]? = nil) {
        self.cellType = cellType
        self.source = source
        self.outputs = outputs
    }

    public var textContent: String {
        var result = "Cell [\(cellType)]:\n"
        for s in source { result += s }
        if let outputs = outputs, !outputs.isEmpty {
            result += "\nOutput:\n"
            for o in outputs { result += o + "\n" }
        }
        return result
    }
}

// MARK: - PDF Page

/// A single page extracted from a PDF document.
public struct PDFPage: Sendable {
    public let pageNumber: Int
    public let text: String

    public init(pageNumber: Int, text: String) {
        self.pageNumber = pageNumber
        self.text = text
    }

    public var textContent: String {
        "--- Page \(pageNumber) ---\n\(text)"
    }
}

