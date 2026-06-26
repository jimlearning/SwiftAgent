import Foundation

// MARK: - SessionMemoryEntry

/// A single memory entry with metadata.
///
/// Named SessionMemoryEntry to avoid collision with the existing
/// `MemoryEntry` struct in Storage/MemoryStore.swift.
public struct SessionMemoryEntry: Sendable, Codable {
    public let key: String
    public let namespace: String
    public let value: Data
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: [String: String]

    public init(
        key: String,
        namespace: String,
        value: Data,
        createdAt: Date,
        updatedAt: Date,
        metadata: [String: String]
    ) {
        self.key = key
        self.namespace = namespace
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - SessionMemoryStore

/// Persistent agent memory. Provider-pluggable: SQLite, Firestore, Vector.
///
/// Named SessionMemoryStore to avoid collision with the existing
/// `MemoryStore` class in Storage/MemoryStore.swift.
public protocol SessionMemoryStore: Sendable {
    /// Store a value at a key within a namespace.
    func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws

    /// Retrieve a value by key and namespace.
    ///
    /// Callers must provide explicit type annotation at call site
    /// when Swift cannot infer T from context (e.g., `as String?`).
    func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T?

    /// Search for entries matching a query within a namespace.
    func search(query: String, namespace: String) async throws -> [SessionMemoryEntry]

    /// Generate a summary of all entries in a namespace.
    func summarize(namespace: String) async throws -> String

    /// Remove an entry by key and namespace.
    func forget(key: String, namespace: String) async throws

    /// List all namespace identifiers.
    func listNamespaces() async throws -> [String]
}

// MARK: - AgentStateProtocol

/// Type-slot for future @AgentState property-wrapper.
/// DESIGN ONLY — not implemented. Protocol surface reserved
/// so SessionMemoryStore can accept @AgentState-annotated properties
/// in a future phase without breaking changes.
///
/// Predicted WWDC27 shape: @AgentState<T: Codable>(key:namespace:store:)
/// with automatic SessionMemoryStore read/write, similar to @AppStorage
/// but backed by agent memory instead of UserDefaults.
public protocol AgentStateProtocol: Sendable {
    /// The key used to persist this state in SessionMemoryStore.
    var key: String { get }

    /// The namespace for this state.
    var namespace: String { get }

    /// The SessionMemoryStore backing this state.
    var store: any SessionMemoryStore { get }
}
