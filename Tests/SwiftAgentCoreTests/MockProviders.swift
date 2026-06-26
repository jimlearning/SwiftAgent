import Foundation
import SwiftAgentCore

// MARK: - MockLanguageModel

/// Configurable mock LanguageModel that returns canned responses and
/// tool calls through its executor. Multi-turn tests push cannedResponses
/// and cannedToolCalls onto these arrays in the desired sequence.
public struct MockLanguageModel: LanguageModel, Sendable {
    public let capabilities: LanguageModelCapabilities
    public let displayName: String

    /// Predefined text responses to stream in sequence.
    public var cannedResponses: [String]

    /// Predefined tool calls to emit in sequence.
    public var cannedToolCalls: [CannedToolCall]

    public init(
        capabilities: LanguageModelCapabilities = .init(providerDisplayName: "Mock"),
        displayName: String = "Mock Model",
        cannedResponses: [String] = [],
        cannedToolCalls: [CannedToolCall] = []
    ) {
        self.capabilities = capabilities
        self.displayName = displayName
        self.cannedResponses = cannedResponses
        self.cannedToolCalls = cannedToolCalls
    }

    public func makeExecutor() -> any LanguageModelExecutor {
        MockLanguageModelExecutor(model: self)
    }

    /// A predefined tool call for the mock executor to stream.
    public struct CannedToolCall: Sendable {
        public let id: String
        public let name: String
        public let input: Data

        public init(id: String, name: String, input: Data) {
            self.id = id
            self.name = name
            self.input = input
        }
    }
}

// MARK: - MockLanguageModelExecutor

/// Mock LanguageModelExecutor that streams the parent MockLanguageModel's
/// canned responses and tool calls through the provided GenerationChannel.
public struct MockLanguageModelExecutor: LanguageModelExecutor, Sendable {
    public let model: any LanguageModel

    public init(model: any LanguageModel) {
        self.model = model
    }

    public func respond(
        to transcript: Transcript,
        tools: [SessionToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws {
        guard let mock = model as? MockLanguageModel else {
            await channel.fail(with: .invalidResponse(reason: "Executor model is not a MockLanguageModel"))
            return
        }

        // Stream canned text responses in sequence.
        for response in mock.cannedResponses {
            await channel.send(textDelta: response)
        }

        // Stream canned tool calls in sequence.
        for call in mock.cannedToolCalls {
            await channel.send(toolCallRequest: call.id, name: call.name, input: call.input)
        }

        // If nothing was canned, emit a default response.
        if mock.cannedResponses.isEmpty && mock.cannedToolCalls.isEmpty {
            await channel.send(textDelta: "Mock response")
        }

        await channel.complete(stopReason: "end_turn", usage: nil)
    }
}

// MARK: - MockMemoryStore

/// In-memory SessionMemoryStore for testing. Stores Codable values
/// in a nested dictionary keyed by namespace and key.
public actor MockMemoryStore: SessionMemoryStore {
    private var storage: [String: [String: Data]] = [:]

    public init() {}

    public func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws {
        let encoded = try JSONEncoder().encode(value)
        storage[namespace, default: [:]][key] = encoded
    }

    public func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T? {
        guard let data = storage[namespace]?[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func search(query: String, namespace: String) async throws -> [SessionMemoryEntry] {
        guard let ns = storage[namespace] else { return [] }
        let lowerQuery = query.lowercased()
        return ns.compactMap { (key: String, data: Data) -> SessionMemoryEntry? in
            let valueString = String(data: data, encoding: .utf8) ?? ""
            guard key.lowercased().contains(lowerQuery)
                    || valueString.lowercased().contains(lowerQuery) else {
                return nil
            }
            return SessionMemoryEntry(
                key: key,
                namespace: namespace,
                value: data,
                createdAt: Date(),
                updatedAt: Date(),
                metadata: [:]
            )
        }
    }

    public func summarize(namespace: String) async throws -> String {
        let count = storage[namespace]?.count ?? 0
        return "Mock summary of \(namespace): \(count) entries"
    }

    public func forget(key: String, namespace: String) async throws {
        storage[namespace]?[key] = nil
    }

    public func listNamespaces() async throws -> [String] {
        Array(storage.keys)
    }
}

// MARK: - MockPermissionEngine

/// Configurable mock SessionPermissionEngine that returns a canned Bool.
public struct MockPermissionEngine: SessionPermissionEngine, Sendable {
    /// The value returned by all `check(_:)` calls.
    public var shouldAllow: Bool

    public init(shouldAllow: Bool = true) {
        self.shouldAllow = shouldAllow
    }

    public func check(_ permission: AgentPermission) async throws -> Bool {
        shouldAllow
    }
}
