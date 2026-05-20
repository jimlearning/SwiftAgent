import Foundation

// MARK: - Message Factory Functions

/// Factory functions for creating messages with proper metadata.
/// Matches Claude Code's message factory functions in `utils/messages.ts`.

/// Placeholder text used when an assistant message has no content.
/// Matches CC's NO_CONTENT_MESSAGE constant.
public let NO_CONTENT_MESSAGE = "(no content)"

// MARK: - User Message Factory

/// Create a user message with full metadata.
/// Matches CC's createUserMessage.
public func createUserMessage(
    content: [ContentBlock],
    isMeta: Bool = false,
    isVirtual: Bool = false,
    toolUseResult: JSONValue? = nil,
    mcpMeta: MCPMeta? = nil,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date(),
    sourceToolAssistantUUID: String? = nil,
    permissionMode: PermissionMode? = nil,
    origin: MessageOrigin? = nil,
    imagePasteIds: [Int]? = nil,
    isCompactSummary: Bool = false,
    summarizeMetadata: SummarizeMetadata? = nil,
    isVisibleInTranscriptOnly: Bool = false,
    toolUseID: String? = nil,
    parentToolUseID: String? = nil
) -> Message {
    Message(
        uuid: uuid,
        type: .user,
        content: content,
        toolUseID: toolUseID,
        parentToolUseID: parentToolUseID,
        timestamp: timestamp,
        isMeta: isMeta,
        origin: origin,
        isVirtual: isVirtual,
        isCompactSummary: isCompactSummary,
        isVisibleInTranscriptOnly: isVisibleInTranscriptOnly,
        summarizeMetadata: summarizeMetadata,
        toolUseResult: toolUseResult,
        mcpMeta: mcpMeta,
        imagePasteIds: imagePasteIds,
        sourceToolAssistantUUID: sourceToolAssistantUUID,
        permissionMode: permissionMode
    )
}

// MARK: - Assistant Message Factory

/// Create an assistant message from content.
/// Matches CC's createAssistantMessage.
public func createAssistantMessage(
    content: [ContentBlock],
    usage: Usage? = nil,
    model: String? = nil,
    stopReason: String? = nil,
    isVirtual: Bool = false,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date(),
    requestId: String? = nil,
    stopSequence: String? = nil,
    container: String? = nil
) -> Message {
    // Guard against empty content: use NO_CONTENT_MESSAGE
    let effectiveContent: [ContentBlock]
    if content.isEmpty || content.allSatisfy({ block in
        if case .text(let text) = block {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }) {
        effectiveContent = [.text(NO_CONTENT_MESSAGE)]
    } else {
        effectiveContent = content
    }

    return Message(
        uuid: uuid,
        type: .assistant,
        content: effectiveContent,
        timestamp: timestamp,
        usage: usage,
        model: model,
        stopReason: stopReason,
        isVirtual: isVirtual,
        requestId: requestId,
        container: container,
        stopSequence: stopSequence
    )
}

// MARK: - API Error Message Factory

/// Create an assistant message from an API error.
/// Matches CC's createAssistantAPIErrorMessage.
public func createAssistantAPIErrorMessage(
    content: String,
    apiError: String? = nil,
    error: String? = nil,
    errorDetails: String? = nil,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .assistant,
        content: [.text(content)],
        timestamp: timestamp,
        isMeta: true,
        requestId: nil,
        apiError: apiError,
        error: error,
        errorDetails: errorDetails,
        isApiErrorMessage: true
    )
}

// MARK: - Interruption Message Factory

/// Create a user interruption message.
/// Matches CC's createUserInterruptionMessage.
public func createUserInterruptionMessage(
    content: [ContentBlock],
    origin: MessageOrigin? = .human,
    permissionMode: PermissionMode? = nil,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .user,
        content: content,
        timestamp: timestamp,
        origin: origin,
        permissionMode: permissionMode
    )
}

// MARK: - System Message Factory

/// Create an informational system message.
/// Matches CC's createSystemMessage.
public func createSystemMessage(
    text: String,
    level: SystemMessageLevel = .info,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text(text)],
        timestamp: timestamp,
        isMeta: true
    )
}

// MARK: - Progress Message Factory

/// Create a progress message for tool execution.
/// Matches CC's createProgressMessage.
public func createProgressMessage(
    toolUseID: String,
    parentToolUseID: String? = nil,
    content: String,
    isMeta: Bool = true,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .progress,
        content: [.text(content)],
        toolUseID: toolUseID,
        parentToolUseID: parentToolUseID,
        timestamp: timestamp,
        isMeta: isMeta
    )
}

// MARK: - Tool Use Summary Message Factory

/// Create a tool use summary placeholder (used during compaction).
/// Matches CC's createToolUseSummaryMessage.
public func createToolUseSummaryMessage(
    toolUseID: String,
    toolName: String,
    summary: String,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .toolUseSummary,
        content: [.text(summary)],
        toolUseID: toolUseID,
        timestamp: timestamp,
        isMeta: true,
        isCompactSummary: true
    )
}

// MARK: - Microcompact Boundary Message Factory

/// Create a microcompact boundary message.
/// Matches CC's createMicrocompactBoundaryMessage.
public func createMicrocompactBoundaryMessage(
    preTokens: Int,
    tokensSaved: Int,
    compactedToolIds: [String] = [],
    clearedAttachmentUUIDs: [String] = [],
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text("[Microcompact boundary: saved \(tokensSaved) tokens (pre: \(preTokens))]")],
        timestamp: timestamp,
        isMeta: true,
        isCompactSummary: true
    )
}

// MARK: - Tool Result Stop Message Factory

/// Create a tool result stop message (for tool execution termination).
/// Matches CC's createToolResultStopMessage.
public func createToolResultStopMessage(
    toolUseID: String,
    reason: String,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .user,
        content: [.toolResult(toolUseID: toolUseID, content: .string(reason), isError: true)],
        toolUseID: toolUseID,
        timestamp: timestamp,
        isMeta: true
    )
}

// MARK: - Stop Hook Summary Message Factory

/// Create a stop hook summary message.
/// Matches CC's createStopHookSummaryMessage.
public func createStopHookSummaryMessage(
    hookCount: Int,
    hookInfos: [StopHookInfo] = [],
    hookErrors: [String] = [],
    preventedContinuation: Bool = false,
    stopReason: String? = nil,
    hasOutput: Bool = false,
    toolUseID: String? = nil,
    hookLabel: String? = nil,
    totalDurationMs: Int = 0,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text("[Stop hook summary: \(hookCount) outputs\(preventedContinuation ? " (continuation prevented)" : "")]")],
        toolUseID: toolUseID,
        timestamp: timestamp,
        isMeta: true
    )
}

// MARK: - Tombstone Message Factory

/// Create a tombstone placeholder for orphaned messages after fallback.
/// Matches CC's tombstone message pattern.
public func createTombstoneMessage(
    originalUUID: String,
    reason: String,
    uuid: String = UUID().uuidString,
    timestamp: Date = Date()
) -> Message {
    Message(
        uuid: uuid,
        type: .tombstone,
        content: [.text("[Tombstone: message \(originalUUID) removed — \(reason)]")],
        timestamp: timestamp,
        isMeta: true
    )
}

// MARK: - Compact Boundary Message Factory

/// Create a compact boundary message that marks the boundary between pre-compact
/// and post-compact conversation state. Matches CC's createCompactBoundaryMessage
/// in utils/messages.ts.
public func createCompactBoundaryMessage(
    trigger: String,
    preTokens: Int,
    lastPreCompactMessageUuid: String? = nil,
    userContext: String? = nil,
    messagesSummarized: Int? = nil,
    uuid: String = UUID().uuidString
) -> Message {
    var content = "--- compaction boundary: \(trigger) ---"
    if let ctx = userContext {
        content += "\nuser message: \(ctx)"
    }
    if let count = messagesSummarized {
        content += "\nmessages summarized: \(count)"
    }
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text(content)],
        isMeta: true,
        isCompactSummary: true
    )
}

// MARK: - System Message Factories

/// Create a system message for memory saved notification.
/// Matches CC's createMemorySavedMessage in utils/messages.ts.
public func createMemorySavedMessage(
    writtenPaths: [String],
    uuid: String = UUID().uuidString
) -> Message {
    let content = "Memory saved: \(writtenPaths.joined(separator: ", "))"
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text(content)],
        isMeta: true
    )
}

/// Create a system message for agents killed notification.
/// Matches CC's createAgentsKilledMessage in utils/messages.ts.
public func createAgentsKilledMessage(
    agentIds: [String],
    uuid: String = UUID().uuidString
) -> Message {
    let content = "Agents killed: \(agentIds.joined(separator: ", "))"
    return Message(
        uuid: uuid,
        type: .system,
        content: [.text(content)],
        isMeta: true
    )
}

/// Create a system message for attachment injection.
/// Matches CC's createAttachmentMessage in utils/attachments.ts.
public func createAttachmentMessage(
    attachment: String,
    name: String = "attachment",
    uuid: String = UUID().uuidString
) -> Message {
    return Message(
        uuid: uuid,
        type: .attachment,
        content: [.text(attachment)],
        isMeta: true
    )
}
