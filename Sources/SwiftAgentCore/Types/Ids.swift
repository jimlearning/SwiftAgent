import Foundation

/// Branded types for session and agent IDs, matching CC's ids.ts.
/// Prevent accidentally mixing up session IDs and agent IDs at compile time.

/// A session ID uniquely identifies a Claude Code session.
/// Matches CC's SessionId branded type.
public struct SessionId: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An agent ID uniquely identifies a subagent within a session.
/// Matches CC's AgentId branded type.
/// When present, indicates the context is a subagent (not the main session).
/// Format: `a` + optional `<label>-` + 16 hex chars.
public struct AgentId: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        // Validate format: a + optional <label>- + 16 hex chars
        let pattern = /^a(?:.+-)?[0-9a-f]{16}$/
        guard rawValue.wholeMatch(of: pattern) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// Create an AgentId without validation (use sparingly).
    public init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        guard let id = AgentId(str) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid AgentId format: \(str)"
            )
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
