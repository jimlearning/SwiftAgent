import Foundation
import SwiftAgentCore

/// Stores the full output of collapsed tool results so they can be
/// recalled later via `/expand N` or `/expand last`.
///
/// Thread-safe (actor). Each stored result receives a sequential group
/// index that the user references in slash commands.
public actor ToolResultCache {
    private var storage: [Int: StoredGroup] = [:]
    private var nextIndex: Int = 1

    /// Store a group of tool results and return the reference index.
    @discardableResult
    public func store(results: [SingleToolResult]) -> Int {
        let index = nextIndex
        storage[index] = StoredGroup(
            index: index,
            results: results
        )
        nextIndex += 1

        // Keep only the most recent 128 groups to bound memory
        if storage.count > 128 {
            let cutoff = nextIndex - 128
            storage = storage.filter { $0.key >= cutoff }
        }
        return index
    }

    /// Retrieve a stored group by its reference index.
    public func get(_ index: Int) -> StoredGroup? {
        storage[index]
    }

    /// Retrieve the most recently stored group, or nil if none exist.
    public func last() -> StoredGroup? {
        guard let maxKey = storage.keys.max() else { return nil }
        return storage[maxKey]
    }

    /// All stored groups sorted by index ascending.
    public func all() -> [StoredGroup] {
        storage.values.sorted { $0.index < $1.index }
    }
}

/// A fully-expanded snapshot of a collapsed group, keyed by its reference index.
public struct StoredGroup: Sendable {
    public let index: Int
    public let results: [SingleToolResult]
}

/// One tool execution result within a collapsed group.
public struct SingleToolResult: Sendable, Equatable {
    public let name: String
    public let input: [String: JSONValue]
    public let output: String
    /// Whether this tool is classified as collapsible (Read/Glob/Grep/search-bash).
    public let isCollapsible: Bool

    public init(name: String, input: [String: JSONValue], output: String, isCollapsible: Bool) {
        self.name = name
        self.input = input
        self.output = output
        self.isCollapsible = isCollapsible
    }
}

extension SingleToolResult {
    /// Number of lines in the output.
    var lineCount: Int {
        output.components(separatedBy: "\n").count
    }

    /// Total character count.
    var charCount: Int { output.count }
}
