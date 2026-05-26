import Foundation

// MARK: - Attachment Message

/// Attachment message matching CC's AttachmentMessage<T>.
/// Wraps an Attachment discriminated union with message metadata.
public struct AttachmentMessage: Sendable, Identifiable {
    public let type = "attachment"
    public let attachment: Attachment
    public let uuid: String
    public let timestamp: Date

    public var id: String { uuid }

    public init(attachment: Attachment, uuid: String = UUID().uuidString, timestamp: Date = Date()) {
        self.attachment = attachment
        self.uuid = uuid
        self.timestamp = timestamp
    }
}

// MARK: - Attachment Discriminated Union

/// Complete Attachment discriminated union matching CC's 52+ attachment types.
/// Discriminated by the `type` field.
/// NOTE: Codable not automatically synthesized due to associated values in 52+ cases.
/// Use type-erased JSON coding if serialization is needed.
public enum Attachment: Sendable {
    // MARK: Named types
    case file(FileAttachment)
    case compactFileReference(CompactFileReferenceAttachment)
    case pdfReference(PDFReferenceAttachment)
    case alreadyReadFile(AlreadyReadFileAttachment)
    case agentMention(AgentMentionAttachment)
    case asyncHookResponse(AsyncHookResponseAttachment)
    case teammateMailbox(TeammateMailboxAttachment)
    case teamContext(TeamContextAttachment)

    // MARK: Inline types
    case editedTextFile(filename: String, snippet: String)
    case editedImageFile(filename: String, content: String)
    case directory(path: String, content: String, displayPath: String)
    case selectedLinesInIDE(ideName: String, lineStart: Int, lineEnd: Int, filename: String, content: String, displayPath: String)
    case openedFileInIDE(filename: String)
    case todoReminder(content: [String: JSONValue], itemCount: Int)
    case taskReminder(content: [String: JSONValue], itemCount: Int)
    case nestedMemory(path: String, content: String, displayPath: String)
    case relevantMemories(memories: [RelevantMemoryEntry])
    case dynamicSkill(skillDir: String, skillNames: [String], displayPath: String)
    case skillListing(content: String, skillCount: Int, isInitial: Bool)
    case skillDiscovery(skills: [SkillDiscoveryEntry], signal: String, source: String)
    case queuedCommand(prompt: [ContentBlock], sourceUUID: String?, imagePasteIds: [Int]?, commandMode: String?, origin: MessageOrigin?, isMeta: Bool)
    case outputStyle(style: String)
    case diagnostics(files: [DiagnosticFile], isNew: Bool)
    case planMode(reminderType: String, isSubAgent: Bool?, planFilePath: String, planExists: Bool)
    case planModeReentry(planFilePath: String)
    case planModeExit(planFilePath: String, planExists: Bool)
    case autoMode(reminderType: String)
    case autoModeExit
    case criticalSystemReminder(content: String)
    case planFileReference(planFilePath: String, planContent: String)
    case mcpResource(server: String, uri: String, name: String, description: String?, content: [String: JSONValue])
    case commandPermissions(allowedTools: [String], model: String?)
    case taskStatus(taskId: String, taskType: String, status: String, description: String, deltaSummary: String?, outputFilePath: String?)
    case tokenUsage(used: Int, total: Int, remaining: Int)
    case budgetUSD(used: Double, total: Double, remaining: Double)
    case outputTokenUsage(turn: Int, session: Int, budget: Int?)
    case structuredOutput(data: JSONValue?)
    case invokedSkills(skills: [InvokedSkillEntry])
    case verifyPlanReminder
    case maxTurnsReached(maxTurns: Int, turnCount: Int)
    case currentSessionMemory(content: String, path: String, tokenCount: Int)
    case teammateShutdownBatch(count: Int)
    case compactionReminder
    case contextEfficiency
    case dateChange(newDate: String)
    case ultrathinkEffort(level: String)
    case deferredToolsDelta(addedNames: [String], addedLines: [String], removedNames: [String])
    case agentListingDelta(addedTypes: [String], addedLines: [String], removedTypes: [String], isInitial: Bool, showConcurrencyNote: Bool)
    case mcpInstructionsDelta(addedNames: [String], addedBlocks: [String], removedNames: [String])
    case companionIntro(name: String, species: String)
    case bagelConsole(errorCount: Int, warningCount: Int, sample: String)

    // MARK: Hook attachments
    case hookCancelled(HookCancelledAttachment)
    case hookBlockingError(HookBlockingErrorAttachment)
    case hookNonBlockingError(HookNonBlockingErrorAttachment)
    case hookErrorDuringExecution(HookErrorDuringExecutionAttachment)
    case hookStoppedContinuation(HookStoppedContinuationAttachment)
    case hookSuccess(HookSuccessAttachment)
    case hookAdditionalContext(HookAdditionalContextAttachment)
    case hookSystemMessage(HookSystemMessageAttachment)
    case hookPermissionDecision(HookPermissionDecisionAttachment)
}

// MARK: - Attachment Type Literal

extension Attachment {
    /// CC's `attachment.type` literal string.
    public var attachmentType: String {
        switch self {
        case .file: return "file"
        case .compactFileReference: return "compact_file_reference"
        case .pdfReference: return "pdf_reference"
        case .alreadyReadFile: return "already_read_file"
        case .agentMention: return "agent_mention"
        case .asyncHookResponse: return "async_hook_response"
        case .teammateMailbox: return "teammate_mailbox"
        case .teamContext: return "team_context"
        case .editedTextFile: return "edited_text_file"
        case .editedImageFile: return "edited_image_file"
        case .directory: return "directory"
        case .selectedLinesInIDE: return "selected_lines_in_ide"
        case .openedFileInIDE: return "opened_file_in_ide"
        case .todoReminder: return "todo_reminder"
        case .taskReminder: return "task_reminder"
        case .nestedMemory: return "nested_memory"
        case .relevantMemories: return "relevant_memories"
        case .dynamicSkill: return "dynamic_skill"
        case .skillListing: return "skill_listing"
        case .skillDiscovery: return "skill_discovery"
        case .queuedCommand: return "queued_command"
        case .outputStyle: return "output_style"
        case .diagnostics: return "diagnostics"
        case .planMode: return "plan_mode"
        case .planModeReentry: return "plan_mode_reentry"
        case .planModeExit: return "plan_mode_exit"
        case .autoMode: return "auto_mode"
        case .autoModeExit: return "auto_mode_exit"
        case .criticalSystemReminder: return "critical_system_reminder"
        case .planFileReference: return "plan_file_reference"
        case .mcpResource: return "mcp_resource"
        case .commandPermissions: return "command_permissions"
        case .taskStatus: return "task_status"
        case .tokenUsage: return "token_usage"
        case .budgetUSD: return "budget_usd"
        case .outputTokenUsage: return "output_token_usage"
        case .structuredOutput: return "structured_output"
        case .invokedSkills: return "invoked_skills"
        case .verifyPlanReminder: return "verify_plan_reminder"
        case .maxTurnsReached: return "max_turns_reached"
        case .currentSessionMemory: return "current_session_memory"
        case .teammateShutdownBatch: return "teammate_shutdown_batch"
        case .compactionReminder: return "compaction_reminder"
        case .contextEfficiency: return "context_efficiency"
        case .dateChange: return "date_change"
        case .ultrathinkEffort: return "ultrathink_effort"
        case .deferredToolsDelta: return "deferred_tools_delta"
        case .agentListingDelta: return "agent_listing_delta"
        case .mcpInstructionsDelta: return "mcp_instructions_delta"
        case .companionIntro: return "companion_intro"
        case .bagelConsole: return "bagel_console"
        case .hookCancelled: return "hook_cancelled"
        case .hookBlockingError: return "hook_blocking_error"
        case .hookNonBlockingError: return "hook_non_blocking_error"
        case .hookErrorDuringExecution: return "hook_error_during_execution"
        case .hookStoppedContinuation: return "hook_stopped_continuation"
        case .hookSuccess: return "hook_success"
        case .hookAdditionalContext: return "hook_additional_context"
        case .hookSystemMessage: return "hook_system_message"
        case .hookPermissionDecision: return "hook_permission_decision"
        }
    }
}

// MARK: - Named Attachment Structs

public struct FileAttachment: Codable, Sendable {
    public let type = "file"
    public let filename: String
    public let content: String
    public let truncated: Bool?
    public let displayPath: String

    enum CodingKeys: String, CodingKey {
        case filename
        case content
        case truncated
        case displayPath
    }

    public init(filename: String, content: String, truncated: Bool? = nil, displayPath: String) {
        self.filename = filename
        self.content = content
        self.truncated = truncated
        self.displayPath = displayPath
    }
}

public struct CompactFileReferenceAttachment: Codable, Sendable {
    public let type = "compact_file_reference"
    public let filename: String
    public let displayPath: String

    enum CodingKeys: String, CodingKey {
        case filename
        case displayPath
    }

    public init(filename: String, displayPath: String) {
        self.filename = filename
        self.displayPath = displayPath
    }
}

public struct PDFReferenceAttachment: Codable, Sendable {
    public let type = "pdf_reference"
    public let filename: String
    public let pageCount: Int
    public let fileSize: Int
    public let displayPath: String

    enum CodingKeys: String, CodingKey {
        case filename
        case pageCount
        case fileSize
        case displayPath
    }

    public init(filename: String, pageCount: Int, fileSize: Int, displayPath: String) {
        self.filename = filename
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.displayPath = displayPath
    }
}

public struct AlreadyReadFileAttachment: Codable, Sendable {
    public let type = "already_read_file"
    public let filename: String
    public let content: String
    public let truncated: Bool?
    public let displayPath: String

    enum CodingKeys: String, CodingKey {
        case filename
        case content
        case truncated
        case displayPath
    }

    public init(filename: String, content: String, truncated: Bool? = nil, displayPath: String) {
        self.filename = filename
        self.content = content
        self.truncated = truncated
        self.displayPath = displayPath
    }
}

public struct AgentMentionAttachment: Codable, Sendable {
    public let type = "agent_mention"
    public let agentType: String

    enum CodingKeys: String, CodingKey {
        case agentType
    }

    public init(agentType: String) {
        self.agentType = agentType
    }
}

public struct AsyncHookResponseAttachment: Codable, Sendable {
    public let type = "async_hook_response"
    public let processId: String
    public let hookName: String
    public let hookEvent: String
    public let toolName: String?
    public let response: [String: JSONValue]?
    public let stdout: String
    public let stderr: String
    public let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case processId
        case hookName
        case hookEvent
        case toolName
        case response
        case stdout
        case stderr
        case exitCode
    }

    public init(
        processId: String,
        hookName: String,
        hookEvent: String,
        toolName: String? = nil,
        response: [String: JSONValue]? = nil,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int? = nil
    ) {
        self.processId = processId
        self.hookName = hookName
        self.hookEvent = hookEvent
        self.toolName = toolName
        self.response = response
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public struct TeammateMailboxAttachment: Codable, Sendable {
    public let type = "teammate_mailbox"
    public let messages: [TeammateMailboxMessage]

    enum CodingKeys: String, CodingKey {
        case messages
    }

    public init(messages: [TeammateMailboxMessage]) {
        self.messages = messages
    }
}

public struct TeammateMailboxMessage: Codable, Sendable {
    public let from: String
    public let text: String
    public let timestamp: String
    public let color: String?
    public let summary: String?

    public init(from: String, text: String, timestamp: String, color: String? = nil, summary: String? = nil) {
        self.from = from
        self.text = text
        self.timestamp = timestamp
        self.color = color
        self.summary = summary
    }
}

public struct TeamContextAttachment: Codable, Sendable {
    public let type = "team_context"
    public let agentId: String
    public let agentName: String
    public let teamName: String
    public let teamConfigPath: String
    public let taskListPath: String

    enum CodingKeys: String, CodingKey {
        case agentId
        case agentName
        case teamName
        case teamConfigPath
        case taskListPath
    }

    public init(agentId: String, agentName: String, teamName: String, teamConfigPath: String, taskListPath: String) {
        self.agentId = agentId
        self.agentName = agentName
        self.teamName = teamName
        self.teamConfigPath = teamConfigPath
        self.taskListPath = taskListPath
    }
}

// MARK: - Hook Attachment Structs

public struct HookCancelledAttachment: Codable, Sendable {
    public let type = "hook_cancelled"
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String
    public let command: String?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case hookName
        case toolUseID
        case hookEvent
        case command
        case durationMs
    }

    public init(hookName: String, toolUseID: String, hookEvent: String, command: String? = nil, durationMs: Int? = nil) {
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
        self.command = command
        self.durationMs = durationMs
    }
}

public struct HookBlockingErrorAttachment: Codable, Sendable {
    public let type = "hook_blocking_error"
    public let blockingError: String
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String

    enum CodingKeys: String, CodingKey {
        case blockingError
        case hookName
        case toolUseID
        case hookEvent
    }

    public init(blockingError: String, hookName: String, toolUseID: String, hookEvent: String) {
        self.blockingError = blockingError
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
    }
}

public struct HookNonBlockingErrorAttachment: Codable, Sendable {
    public let type = "hook_non_blocking_error"
    public let hookName: String
    public let stderr: String
    public let stdout: String
    public let exitCode: Int
    public let toolUseID: String
    public let hookEvent: String
    public let command: String?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case hookName
        case stderr
        case stdout
        case exitCode
        case toolUseID
        case hookEvent
        case command
        case durationMs
    }

    public init(
        hookName: String,
        stderr: String,
        stdout: String,
        exitCode: Int,
        toolUseID: String,
        hookEvent: String,
        command: String? = nil,
        durationMs: Int? = nil
    ) {
        self.hookName = hookName
        self.stderr = stderr
        self.stdout = stdout
        self.exitCode = exitCode
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
        self.command = command
        self.durationMs = durationMs
    }
}

public struct HookErrorDuringExecutionAttachment: Codable, Sendable {
    public let type = "hook_error_during_execution"
    public let content: String
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String
    public let command: String?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case content
        case hookName
        case toolUseID
        case hookEvent
        case command
        case durationMs
    }

    public init(
        content: String,
        hookName: String,
        toolUseID: String,
        hookEvent: String,
        command: String? = nil,
        durationMs: Int? = nil
    ) {
        self.content = content
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
        self.command = command
        self.durationMs = durationMs
    }
}

public struct HookStoppedContinuationAttachment: Codable, Sendable {
    public let type = "hook_stopped_continuation"
    public let message: String
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String

    enum CodingKeys: String, CodingKey {
        case message
        case hookName
        case toolUseID
        case hookEvent
    }

    public init(message: String, hookName: String, toolUseID: String, hookEvent: String) {
        self.message = message
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
    }
}

public struct HookSuccessAttachment: Codable, Sendable {
    public let type = "hook_success"
    public let content: String
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String
    public let stdout: String?
    public let stderr: String?
    public let exitCode: Int?
    public let command: String?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case content
        case hookName
        case toolUseID
        case hookEvent
        case stdout
        case stderr
        case exitCode
        case command
        case durationMs
    }

    public init(
        content: String,
        hookName: String,
        toolUseID: String,
        hookEvent: String,
        stdout: String? = nil,
        stderr: String? = nil,
        exitCode: Int? = nil,
        command: String? = nil,
        durationMs: Int? = nil
    ) {
        self.content = content
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.command = command
        self.durationMs = durationMs
    }
}

public struct HookAdditionalContextAttachment: Codable, Sendable {
    public let type = "hook_additional_context"
    public let content: [String]
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String

    enum CodingKeys: String, CodingKey {
        case content
        case hookName
        case toolUseID
        case hookEvent
    }

    public init(content: [String], hookName: String, toolUseID: String, hookEvent: String) {
        self.content = content
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
    }
}

public struct HookSystemMessageAttachment: Codable, Sendable {
    public let type = "hook_system_message"
    public let content: String
    public let hookName: String
    public let toolUseID: String
    public let hookEvent: String

    enum CodingKeys: String, CodingKey {
        case content
        case hookName
        case toolUseID
        case hookEvent
    }

    public init(content: String, hookName: String, toolUseID: String, hookEvent: String) {
        self.content = content
        self.hookName = hookName
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
    }
}

public struct HookPermissionDecisionAttachment: Codable, Sendable {
    public let type = "hook_permission_decision"
    public let decision: String  // "allow" | "deny"
    public let toolUseID: String
    public let hookEvent: String

    enum CodingKeys: String, CodingKey {
        case decision
        case toolUseID
        case hookEvent
    }

    public init(decision: String, toolUseID: String, hookEvent: String) {
        self.decision = decision
        self.toolUseID = toolUseID
        self.hookEvent = hookEvent
    }
}

// MARK: - Supporting Types

public struct RelevantMemoryEntry: Codable, Sendable {
    public let path: String
    public let content: String
    public let mtimeMs: Double
    public let header: String?
    public let limit: Int?

    public init(path: String, content: String, mtimeMs: Double, header: String? = nil, limit: Int? = nil) {
        self.path = path
        self.content = content
        self.mtimeMs = mtimeMs
        self.header = header
        self.limit = limit
    }
}

public struct SkillDiscoveryEntry: Codable, Sendable {
    public let name: String
    public let description: String
    public let shortId: String?

    public init(name: String, description: String, shortId: String? = nil) {
        self.name = name
        self.description = description
        self.shortId = shortId
    }
}

public struct DiagnosticFile: Codable, Sendable {
    public let filename: String
    public let diagnostics: String

    public init(filename: String, diagnostics: String) {
        self.filename = filename
        self.diagnostics = diagnostics
    }
}

public struct InvokedSkillEntry: Codable, Sendable {
    public let name: String
    public let path: String
    public let content: String

    public init(name: String, path: String, content: String) {
        self.name = name
        self.path = path
        self.content = content
    }
}
