import Foundation

public struct Session: Codable, Sendable, Identifiable {
    public let id: String
    public var title: String?
    public var conversation: Conversation
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var branch: String?

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        conversation: Conversation = Conversation(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        branch: String? = nil
    ) {
        self.id = id
        self.title = title
        self.conversation = conversation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.branch = branch
    }
}

public struct SessionMetadata: Codable, Sendable {
    public var id: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var messageCount: Int
    public var tags: [String]

    public init(
        id: String,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.tags = tags
    }
}

public struct ConversationHistory: Codable, Sendable {
    public var sessions: [Session]

    public init(sessions: [Session] = []) {
        self.sessions = sessions
    }

    public mutating func addSession(_ session: Session) {
        sessions.append(session)
    }

    public func recentSessions(limit: Int = 10) -> [Session] {
        Array(sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(limit))
    }
}
