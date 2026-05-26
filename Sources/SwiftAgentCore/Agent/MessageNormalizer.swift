import Foundation

// MARK: - Message Normalization

/// Filter, merge, and normalize messages for API submission.
/// Matches Claude Code's normalizeMessagesForAPI in utils/messages.ts.
///
/// Pipeline passes (in CC order):
/// 1. Filter virtual messages
/// 2. Filter progress messages
/// 3. Filter system messages to API
/// 4. Deduplicate by UUID (first occurrence wins)
/// 5. Normalize tool_use inputs in assistant messages (strip internal fields)
/// 6. Strip unavailable tool references (requires tools param)
/// 7. Filter orphaned thinking-only assistant messages
/// 8. Filter trailing thinking from last assistant message
/// 9. Filter whitespace-only assistant messages
/// 10. Merge ALL consecutive user messages
/// 11. Merge assistant messages with same message ID (backward walk)
/// 12. Smoosh system reminder siblings into tool_result content
/// 13. Sanitize error tool_result content (strip non-text from is_error)
/// 14. Ensure non-empty assistant content (placeholder for empty arrays)
/// 15. Normalize content (strip empty text blocks)
/// 16. Apply aggregate tool result budget (CC's applyToolResultBudget)
/// 17. Ensure tool_use / tool_result pairing
///
/// - Parameters:
///   - messages: Messages to normalize.
///   - tools: Available tool names for filtering tool_use references. Matches CC's
///     availableToolNames set — strips tool_reference and tool_use blocks that
///     reference unavailable tools to prevent 400 API errors.
public func normalizeMessagesForAPI(_ messages: [Message], tools: [String] = []) -> [Message] {
    // Pass 1: Filter virtual messages (display-only, never sent to API)
    var result = messages.filter { !$0.isVirtual }

    // Pass 2: Filter progress messages (never sent to API)
    result = result.filter { $0.type != .progress }

    // Pass 3: Filter system messages for API submission.
    // Matches CC's filter where only local_command system messages are kept
    // (converted to user messages so the model can reference command output).
    // All other system messages are display-only. SA doesn't use local_command
    // messages yet, so all system messages are filtered out.
    result = result.filter { $0.type != .system }

    // Pass 5: Deduplicate by UUID — first occurrence wins.
    // Matches CC's UUID-based dedup that prevents duplicate messages
    // from re-emission during retries or compactions from corrupting the conversation.
    var seenUUIDs = Set<String>()
    result = result.filter { seenUUIDs.insert($0.uuid).inserted }

    // Pass 5: Normalize tool_use inputs in assistant messages.
    // Matches CC's normalizeToolInputForAPI call during assistant message
    // processing in normalizeMessagesForAPI — strips internal-only fields
    // (plan/planFilePath from ExitPlanModeV2, synthetic edits from FileEdit)
    // before sending tool_use blocks back to the API, preventing the model
    // from seeing injected fields that aren't part of the tool schema.
    result = result.map { msg in
        guard msg.type == .assistant else { return msg }
        var blocks = msg.content
        var changed = false
        for (i, block) in blocks.enumerated() {
            switch block {
            case .toolUse(let id, let name, let input):
                if case .object(let dict) = input {
                    let normalized = normalizeToolInputForAPI(toolName: name, input: dict)
                    if normalized.count != dict.count {
                        blocks[i] = .toolUse(id: id, name: name, input: .object(normalized))
                        changed = true
                    }
                }
            case .serverToolUse(let id, let name, let input):
                if case .object(let dict) = input {
                    let normalized = normalizeToolInputForAPI(toolName: name, input: dict)
                    if normalized.count != dict.count {
                        blocks[i] = .serverToolUse(id: id, name: name, input: .object(normalized))
                        changed = true
                    }
                }
            default:
                break
            }
        }
        if !changed { return msg }
        return Message(
            uuid: msg.uuid, type: msg.type, content: blocks,
            toolUseID: msg.toolUseID, parentToolUseID: msg.parentToolUseID,
            timestamp: msg.timestamp, isMeta: msg.isMeta,
            usage: msg.usage, model: msg.model, stopReason: msg.stopReason,
            origin: msg.origin, isVirtual: msg.isVirtual,
            isCompactSummary: msg.isCompactSummary,
            isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
            summarizeMetadata: msg.summarizeMetadata,
            toolUseResult: msg.toolUseResult, mcpMeta: msg.mcpMeta,
            imagePasteIds: msg.imagePasteIds,
            sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
            permissionMode: msg.permissionMode,
            requestId: msg.requestId,
            apiError: msg.apiError, error: msg.error,
            errorDetails: msg.errorDetails,
            isApiErrorMessage: msg.isApiErrorMessage,
            container: msg.container, stopSequence: msg.stopSequence
        )
    }

    // Pass 6: Strip tool_reference blocks and tool_use blocks that reference
    // tools not in the available set. Matches CC's stripUnavailableToolReferencesFromUserMessage
    // and stripToolReferenceBlocksFromUserMessage in utils/messages.ts.
    if !tools.isEmpty {
        let availableToolNames = Set(tools)
        result = result.map { msg in
            var blocks = msg.content
            blocks = blocks.filter { block in
                switch block {
                case .toolUse(_, let name, _), .serverToolUse(_, let name, _):
                    // Strip tool_use blocks referencing unavailable tools
                    if !availableToolNames.contains(name) {
                        return false
                    }
                    return true
                case .toolReference:
                    // Strip ALL tool_reference blocks when tool search is not enabled.
                    // CC strips tool_references from user tool_result content since they
                    // reference tools via the tool search API which may not be available.
                    return false
                default:
                    return true
                }
            }
            if blocks.count == msg.content.count { return msg }
            return Message(
                uuid: msg.uuid, type: msg.type, content: blocks,
                toolUseID: msg.toolUseID, parentToolUseID: msg.parentToolUseID,
                timestamp: msg.timestamp, isMeta: msg.isMeta,
                usage: msg.usage, model: msg.model, stopReason: msg.stopReason,
                origin: msg.origin, isVirtual: msg.isVirtual,
                isCompactSummary: msg.isCompactSummary,
                isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
                summarizeMetadata: msg.summarizeMetadata,
                toolUseResult: msg.toolUseResult, mcpMeta: msg.mcpMeta,
                imagePasteIds: msg.imagePasteIds,
                sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
                permissionMode: msg.permissionMode,
                requestId: msg.requestId,
                apiError: msg.apiError, error: msg.error,
                errorDetails: msg.errorDetails,
                isApiErrorMessage: msg.isApiErrorMessage,
                container: msg.container, stopSequence: msg.stopSequence
            )
        }
    }

    // Pass 7: Filter orphaned thinking-only assistant messages
    // Messages that contain ONLY thinking blocks with no text/tool output
    // should not be sent back to the API as standalone messages.
    result = result.filter { msg in
        guard msg.type == .assistant else { return true }
        let nonThinkingBlocks = msg.content.filter { block in
            if case .thinking = block { return false }
            if case .redactedThinking = block { return false }
            return true
        }
        return !nonThinkingBlocks.isEmpty
    }

    // Pass 8: Filter trailing thinking from the last assistant message
    // The final assistant message should not end with thinking-only blocks.
    if let lastIdx = result.lastIndex(where: { $0.type == .assistant }),
       lastIdx < result.count {
        let lastAssistant = result[lastIdx]
        // Filter trailing thinking/redactedThinking blocks
        var filteredContent = lastAssistant.content
        while let lastBlock = filteredContent.last {
            switch lastBlock {
            case .thinking, .redactedThinking:
                filteredContent.removeLast()
            default:
                break
            }
        }
        // If content is now empty, replace with NO_CONTENT_MESSAGE
        let effectiveContent: [ContentBlock]
        if filteredContent.isEmpty {
            effectiveContent = [.text(NO_CONTENT_MESSAGE)]
        } else {
            effectiveContent = filteredContent
        }
        result[lastIdx] = Message(
            uuid: lastAssistant.uuid,
            type: .assistant,
            content: effectiveContent,
            timestamp: lastAssistant.timestamp,
            usage: lastAssistant.usage,
            model: lastAssistant.model,
            stopReason: lastAssistant.stopReason,
            isVirtual: lastAssistant.isVirtual,
            requestId: lastAssistant.requestId,
            container: lastAssistant.container,
            stopSequence: lastAssistant.stopSequence
        )
    }

    // Pass 9: Filter whitespace-only assistant messages
    // Replace assistant messages that contain only whitespace with NO_CONTENT_MESSAGE
    result = result.map { msg in
        guard msg.type == .assistant else { return msg }
        let hasMeaningfulContent = msg.content.contains { block in
            if case .text(let text) = block {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true // Non-text blocks are meaningful
        }
        if hasMeaningfulContent { return msg }
        // Replace with NO_CONTENT_MESSAGE
        return Message(
            uuid: msg.uuid,
            type: .assistant,
            content: [.text(NO_CONTENT_MESSAGE)],
            timestamp: msg.timestamp,
            usage: msg.usage,
            model: msg.model,
            stopReason: msg.stopReason,
            isVirtual: msg.isVirtual,
            requestId: msg.requestId,
            container: msg.container,
            stopSequence: msg.stopSequence
        )
    }

    // Pass 10: Merge consecutive user messages.
    // Matches CC's merge in normalizeMessagesForAPI — merges ALL consecutive user
    // messages (not just tool-result ones), because Bedrock rejects consecutive
    // user turns and the SDK/API may fragment tool-result user messages.
    var merged: [Message] = []
    for message in result {
        if message.type == .user,
           let lastMsg = merged.last,
           lastMsg.type == .user {
            // Merge into the preceding user message
            let mergedContent = lastMsg.content + message.content
            let mergedMsg = Message(
                uuid: lastMsg.uuid,
                type: .user,
                content: mergedContent,
                toolUseID: lastMsg.toolUseID,
                timestamp: lastMsg.timestamp,
                isMeta: lastMsg.isMeta,
                origin: lastMsg.origin,
                isVirtual: lastMsg.isVirtual,
                sourceToolAssistantUUID: lastMsg.sourceToolAssistantUUID,
                permissionMode: lastMsg.permissionMode
            )
            merged[merged.count - 1] = mergedMsg
        } else if message.type == .user || message.type == .assistant {
            merged.append(message)
        }
        // Non-user/non-assistant messages (system, attachment, tombstone) are skipped
    }

    // Pass 11: Merge assistant messages with same message ID (backward walk).
    // Matches CC's merge in normalizeMessagesForAPI — walks backward from the
    // end, skipping over tool-result messages and different-ID assistants,
    // then merges by message.id. This handles interleaved streaming from
    // concurrent agents (teammates) where messages arrive non-consecutively.
    var assistantMerged: [Message] = []
    for message in merged {
        if message.type == .assistant, let msgId = message.requestId {
            var found = false
            for i in stride(from: assistantMerged.count - 1, through: 0, by: -1) {
                let prev = assistantMerged[i]
                // Stop at non-assistant messages that aren't tool-result users
                if prev.type != .assistant && !prev.content.contains(where: {
                    if case .toolResult = $0 { return true }; return false
                }) {
                    break
                }
                if prev.type == .assistant, prev.requestId == msgId {
                    let combinedContent = prev.content + message.content
                    let mergedMsg = Message(
                        uuid: prev.uuid,
                        type: .assistant,
                        content: combinedContent,
                        timestamp: prev.timestamp,
                        usage: message.usage ?? prev.usage,
                        model: message.model ?? prev.model,
                        stopReason: message.stopReason ?? prev.stopReason,
                        isVirtual: prev.isVirtual,
                        requestId: prev.requestId,
                        container: prev.container,
                        stopSequence: message.stopSequence ?? prev.stopSequence
                    )
                    assistantMerged[i] = mergedMsg
                    found = true
                    break
                }
            }
            if !found {
                assistantMerged.append(message)
            }
        } else {
            assistantMerged.append(message)
        }
    }

    // Pass 12: Smoosh system reminder siblings into tool_result content.
    // Matches CC's smooshSystemReminderSiblings in utils/messages.ts:1835 —
    // collects <system-reminder>-prefixed text blocks from each user message
    // and folds them into the last tool_result's content. Catches siblings
    // from attachment processing, tool reference relocation, and other paths.
    // Non-system-reminder text (real user input) stays untouched.
    let smooshed = smooshSystemReminders(assistantMerged)

    // Pass 13: Sanitize error tool_result content.
    // Matches CC's sanitizeErrorToolResultContent — strips non-text blocks from
    // is_error tool_results. The API requires all content to be type text when
    // is_error is true, and rejects the combination with a 400 error. This is
    // a read-side guard for transcripts persisted before this rule was enforced.
    var sanitized = sanitizeErrorToolResultContent(smooshed)

    // Pass 14: Ensure non-empty assistant content.
    // Matches CC's ensureNonEmptyAssistantContent — inserts a placeholder text
    // block into non-final assistant messages with empty content arrays.
    // The API rejects empty non-final messages. The final message is exempt
    // (it can be empty for prefill).
    sanitized = ensureNonEmptyAssistantContent(sanitized)

    // Pass 15: Normalize content — filter empty text blocks
    let normalized = normalizeContentFromAPI_allMessages(sanitized)

    // Pass 16: Apply aggregate tool result budget.
    // Matches CC's applyToolResultBudget — enforces MAX_TOOL_RESULTS_PER_MESSAGE_CHARS
    // limit to prevent API overload from excessive tool result content.
    let budgeted = ToolResultStorage.applyToolResultBudget(messages: normalized)

    // Pass 17: Ensure tool_use / tool_result pairing.
    // Matches CC's ensureToolResultPairing in utils/messages.ts —
    // inserts synthetic error blocks for missing tool results and
    // strips orphaned tool results to prevent 400 API errors.
    return ensureToolResultPairing(budgeted)
}

// MARK: - API Content Normalization

/// Filter out empty text content blocks from API responses.
/// Matches Claude Code's normalizeContentFromAPI.
///
/// The API sometimes returns empty messages (e.g. "\n\n") which cause
/// errors when sent back to the API in the next turn.
public func normalizeContentFromAPI(_ blocks: [ContentBlock]) -> [ContentBlock] {
    blocks.filter { block in
        if case .text(let text) = block {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }
}

/// Normalize content blocks across all messages in a list.
private func normalizeContentFromAPI_allMessages(_ messages: [Message]) -> [Message] {
    messages.map { msg in
        let normalized = normalizeContentFromAPI(msg.content)
        // Preserve all metadata while using normalized content
        return Message(
            uuid: msg.uuid,
            type: msg.type,
            content: normalized,
            toolUseID: msg.toolUseID,
            parentToolUseID: msg.parentToolUseID,
            timestamp: msg.timestamp,
            isMeta: msg.isMeta,
            usage: msg.usage,
            model: msg.model,
            stopReason: msg.stopReason,
            origin: msg.origin,
            isVirtual: msg.isVirtual,
            isCompactSummary: msg.isCompactSummary,
            isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
            summarizeMetadata: msg.summarizeMetadata,
            toolUseResult: msg.toolUseResult,
            mcpMeta: msg.mcpMeta,
            imagePasteIds: msg.imagePasteIds,
            sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
            permissionMode: msg.permissionMode,
            requestId: msg.requestId,
            apiError: msg.apiError,
            error: msg.error,
            errorDetails: msg.errorDetails,
            isApiErrorMessage: msg.isApiErrorMessage,
            container: msg.container,
            stopSequence: msg.stopSequence
        )
    }
}

// MARK: - Tool Input Normalization for API

/// Strip internal-only fields from tool inputs before sending back to the API.
/// Matches Claude Code's normalizeToolInputForAPI in utils/api.ts.
///
/// CC strips fields that were added by normalizeToolInput (e.g., plan field
/// from ExitPlanModeV2 which has an empty input schema) so they aren't
/// echoed back to the model.
public func normalizeToolInputForAPI(
    toolName: String,
    input: [String: JSONValue]
) -> [String: JSONValue] {
    var normalized = input

    switch toolName {
    case "ExitPlanMode":
        // Strip injected fields before sending to API (schema expects empty object).
        // CC injects plan + planFilePath via normalizeToolInput for hooks/SDK consumers.
        if normalized["plan"] != nil || normalized["planFilePath"] != nil {
            normalized.removeValue(forKey: "plan")
            normalized.removeValue(forKey: "planFilePath")
        }
    case "Edit":
        // Strip synthetic old_string/new_string/replace_all from OLD sessions
        // that were resumed from transcripts written before synthesis was moved
        // to emission time. The 'edits' key is the old-format marker.
        if normalized["edits"] != nil {
            normalized.removeValue(forKey: "old_string")
            normalized.removeValue(forKey: "new_string")
            normalized.removeValue(forKey: "replace_all")
        }
    default:
        break
    }

    // Strip tool-search-specific fields (e.g., 'caller') that may be stored
    // in persisted sessions from previous tool-search-enabled runs. When tool
    // search is not enabled, these cause API 400 errors. Matches CC's
    // explicit block reconstruction at messages.ts:2231-2239.
    normalized.removeValue(forKey: "caller")

    return normalized
}

// MARK: - Tool Input Normalization for Execution

/// Normalize tool input before execution.
/// Matches Claude Code's normalizeToolInput in query.ts.
///
/// Strips the "cd <cwd> && " prefix from BashTool commands that CC
/// automatically prepends before executing.
public func normalizeToolInput(
    toolName: String,
    input: [String: JSONValue],
    workingDirectory: String
) -> [String: JSONValue] {
    switch toolName {
    case "Bash":
        var normalized = input
        if case .string(var cmd) = input["command"] ?? .string("") {
            let cdPrefix = "cd \(workingDirectory) && "
            if cmd.hasPrefix(cdPrefix) {
                cmd = String(cmd.dropFirst(cdPrefix.count))
                normalized["command"] = .string(cmd)
            }
        }
        return normalized
    default:
        return input
    }
}

// MARK: - System Reminder Text Detection

/// Check if a content block is a system-reminder text.
/// CC detects `<system-reminder>` tags and merges them into adjacent
/// tool_result content blocks during normalization.
public func isSystemReminderText(_ text: String) -> Bool {
    text.contains("<system-reminder>") || text.contains("</system-reminder>")
}

/// Smoosh system-reminder text blocks into adjacent tool_result content.
/// CC merges system-reminder snippets into preceding tool_result blocks
/// to avoid them being treated as standalone user input by the API.
public func smooshSystemReminders(_ messages: [Message]) -> [Message] {
    var result: [Message] = []
    for message in messages {
        guard message.type == .user else {
            result.append(message)
            continue
        }

        var blocks = message.content
        var i = 0
        while i < blocks.count {
            if case .text(let text) = blocks[i], isSystemReminderText(text) {
                // Try to merge backward into a tool_result block
                var merged = false
                for j in stride(from: i - 1, through: 0, by: -1) {
                    if case .toolResult(let toolUseID, let content, let isError) = blocks[j] {
                        let mergedContent: ToolResultContent
                        switch content {
                        case .string(let str):
                            mergedContent = .string(str + "\n" + text)
                        case .blocks(var contentBlocks):
                            contentBlocks.append(.text(text))
                            mergedContent = .blocks(contentBlocks)
                        }
                        blocks[j] = .toolResult(toolUseID: toolUseID, content: mergedContent, isError: isError)
                        blocks.remove(at: i)
                        merged = true
                        break
                    }
                }
                if merged {
                    // Don't increment i since we removed this element
                    continue
                }
            }
            i += 1
        }
        result.append(Message(
            uuid: message.uuid,
            type: .user,
            content: blocks,
            toolUseID: message.toolUseID,
            timestamp: message.timestamp,
            isMeta: message.isMeta,
            origin: message.origin,
            isVirtual: message.isVirtual,
            sourceToolAssistantUUID: message.sourceToolAssistantUUID,
            permissionMode: message.permissionMode
        ))
    }
    return result
}

// MARK: - Error Tool Result Sanitization

/// Strip non-text content blocks from is_error tool_results.
/// Matches CC's sanitizeErrorToolResultContent — the API requires all content
/// to be type text when is_error is true. Images or documents in error
/// tool_results cause 400 errors.
private func sanitizeErrorToolResultContent(_ messages: [Message]) -> [Message] {
    messages.map { msg in
        guard msg.type == .user else { return msg }
        var changed = false
        let newContent = msg.content.map { block -> ContentBlock in
            guard case .toolResult(let id, let content, let isError) = block, isError else { return block }
            switch content {
            case .string:
                return block // Single string is always text — safe
            case .blocks(let innerBlocks):
                if innerBlocks.allSatisfy({ if case .text = $0 { return true }; return false }) {
                    return block // All text — safe
                }
                changed = true
                let texts = innerBlocks.compactMap { b -> String? in
                    if case .text(let t) = b { return t }; return nil
                }
                let textOnly: ToolResultContent = texts.isEmpty
                    ? .string("")
                    : .string(texts.joined(separator: "\n\n"))
                return .toolResult(toolUseID: id, content: textOnly, isError: true)
            }
        }
        guard changed else { return msg }
        return Message(
            uuid: msg.uuid, type: msg.type, content: newContent,
            toolUseID: msg.toolUseID, parentToolUseID: msg.parentToolUseID,
            timestamp: msg.timestamp, isMeta: msg.isMeta,
            usage: msg.usage, model: msg.model, stopReason: msg.stopReason,
            origin: msg.origin, isVirtual: msg.isVirtual,
            isCompactSummary: msg.isCompactSummary,
            isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
            summarizeMetadata: msg.summarizeMetadata,
            toolUseResult: msg.toolUseResult, mcpMeta: msg.mcpMeta,
            imagePasteIds: msg.imagePasteIds,
            sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
            permissionMode: msg.permissionMode,
            requestId: msg.requestId,
            apiError: msg.apiError, error: msg.error,
            errorDetails: msg.errorDetails,
            isApiErrorMessage: msg.isApiErrorMessage,
            container: msg.container, stopSequence: msg.stopSequence
        )
    }
}

// MARK: - Non-Empty Assistant Content

/// Insert placeholder text into non-final assistant messages with empty content.
/// Matches CC's ensureNonEmptyAssistantContent — the API rejects empty content
/// arrays on non-final messages. The final message is exempt (valid for prefill).
private func ensureNonEmptyAssistantContent(_ messages: [Message]) -> [Message] {
    guard !messages.isEmpty else { return messages }
    let lastIndex = messages.count - 1
    return messages.enumerated().map { (i, msg) in
        guard msg.type == .assistant else { return msg }
        guard i != lastIndex else { return msg } // Final message can be empty
        guard msg.content.isEmpty else { return msg }
        return Message(
            uuid: msg.uuid, type: .assistant,
            content: [.text(NO_CONTENT_MESSAGE)],
            timestamp: msg.timestamp, usage: msg.usage,
            model: msg.model, stopReason: msg.stopReason,
            isVirtual: msg.isVirtual, requestId: msg.requestId,
            container: msg.container, stopSequence: msg.stopSequence
        )
    }
}

// MARK: - Tool Result Pairing

/// Ensure every tool_use has a matching tool_result, and strip orphaned results.
/// Matches CC's ensureToolResultPairing in utils/messages.ts:
/// - Inserts synthetic error blocks for tool_use without results
/// - Strips orphaned tool_results with no matching tool_use
///
/// The API rejects messages with missing or orphaned tool results (400 error).
public func ensureToolResultPairing(_ messages: [Message]) -> [Message] {
    // Collect all tool_use IDs and tool_result IDs
    var toolUseIDs = Set<String>()
    var toolResultIDs = Set<String>()

    for msg in messages {
        for block in msg.content {
            switch block {
            case .toolUse(let id, _, _), .serverToolUse(let id, _, _):
                toolUseIDs.insert(id)
            case .toolResult(let id, _, _):
                toolResultIDs.insert(id)
            default:
                break
            }
        }
    }

    // Find missing results (tool_use without tool_result) and orphaned results
    let missingResults = toolUseIDs.subtracting(toolResultIDs)
    let orphanedResults = toolResultIDs.subtracting(toolUseIDs)

    guard !missingResults.isEmpty || !orphanedResults.isEmpty else {
        return messages
    }

    var result: [Message] = []
    for var msg in messages {
        var blocks = msg.content

        // Strip orphaned tool results
        if !orphanedResults.isEmpty {
            blocks = blocks.filter { block in
                if case .toolResult(let id, _, _) = block {
                    return !orphanedResults.contains(id)
                }
                return true
            }
        }

        if !blocks.isEmpty {
            msg = Message(
                uuid: msg.uuid,
                type: msg.type,
                content: blocks,
                toolUseID: msg.toolUseID,
                parentToolUseID: msg.parentToolUseID,
                timestamp: msg.timestamp,
                isMeta: msg.isMeta,
                usage: msg.usage,
                model: msg.model,
                stopReason: msg.stopReason,
                origin: msg.origin,
                isVirtual: msg.isVirtual,
                isCompactSummary: msg.isCompactSummary,
                isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
                summarizeMetadata: msg.summarizeMetadata,
                toolUseResult: msg.toolUseResult,
                mcpMeta: msg.mcpMeta,
                imagePasteIds: msg.imagePasteIds,
                sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
                permissionMode: msg.permissionMode,
                requestId: msg.requestId,
                apiError: msg.apiError,
                error: msg.error,
                errorDetails: msg.errorDetails,
                isApiErrorMessage: msg.isApiErrorMessage,
                container: msg.container,
                stopSequence: msg.stopSequence
            )
            result.append(msg)
        }
    }

    // Insert synthetic error results for missing pairings into the
    // last user message that already has tool results.
    if !missingResults.isEmpty {
        if let lastIdx = result.lastIndex(where: { msg in
            msg.type == .user && msg.content.contains(where: { block in
                if case .toolResult = block { return true }; return false
            })
        }) {
            var lastMsg = result[lastIdx]
            var blocks = lastMsg.content
            for id in missingResults {
                blocks.append(.toolResult(toolUseID: id, content: .string("Error: no tool result"), isError: true))
            }
            lastMsg = Message(
                uuid: lastMsg.uuid,
                type: lastMsg.type,
                content: blocks,
                toolUseID: lastMsg.toolUseID,
                parentToolUseID: lastMsg.parentToolUseID,
                timestamp: lastMsg.timestamp,
                isMeta: lastMsg.isMeta,
                usage: lastMsg.usage,
                model: lastMsg.model,
                stopReason: lastMsg.stopReason,
                origin: lastMsg.origin,
                isVirtual: lastMsg.isVirtual,
                isCompactSummary: lastMsg.isCompactSummary,
                isVisibleInTranscriptOnly: lastMsg.isVisibleInTranscriptOnly,
                summarizeMetadata: lastMsg.summarizeMetadata,
                toolUseResult: lastMsg.toolUseResult,
                mcpMeta: lastMsg.mcpMeta,
                imagePasteIds: lastMsg.imagePasteIds,
                sourceToolAssistantUUID: lastMsg.sourceToolAssistantUUID,
                permissionMode: lastMsg.permissionMode,
                requestId: lastMsg.requestId,
                apiError: lastMsg.apiError,
                error: lastMsg.error,
                errorDetails: lastMsg.errorDetails,
                isApiErrorMessage: lastMsg.isApiErrorMessage,
                container: lastMsg.container,
                stopSequence: lastMsg.stopSequence
            )
            result[lastIdx] = lastMsg
        }
    }

    return result
}

// MARK: - Signature Block Stripping

/// Strip thinking blocks (thinking, redacted_thinking) from assistant messages
/// after credential changes (login/logout). Thought signatures are tied to the
/// user/session that generated them — after auth changes, they cause 400 API errors.
/// Matches CC's stripSignatureBlocks in utils/messages.ts — filters out
/// thinking/redacted_thinking blocks entirely (not just the signature).
public func stripSignatureBlocks(_ messages: [Message]) -> [Message] {
    let result = messages.map { msg -> Message in
        guard msg.type == .assistant else { return msg }

        let filtered = msg.content.filter { block in
            if case .thinking = block { return false }
            if case .redactedThinking = block { return false }
            return true
        }
        guard filtered.count != msg.content.count else { return msg }

        return Message(
            uuid: msg.uuid,
            type: msg.type,
            content: filtered,
            toolUseID: msg.toolUseID,
            parentToolUseID: msg.parentToolUseID,
            timestamp: msg.timestamp,
            isMeta: msg.isMeta,
            usage: msg.usage,
            model: msg.model,
            stopReason: msg.stopReason,
            origin: msg.origin,
            isVirtual: msg.isVirtual,
            isCompactSummary: msg.isCompactSummary,
            isVisibleInTranscriptOnly: msg.isVisibleInTranscriptOnly,
            summarizeMetadata: msg.summarizeMetadata,
            toolUseResult: msg.toolUseResult,
            mcpMeta: msg.mcpMeta,
            imagePasteIds: msg.imagePasteIds,
            sourceToolAssistantUUID: msg.sourceToolAssistantUUID,
            permissionMode: msg.permissionMode,
            requestId: msg.requestId,
            apiError: msg.apiError,
            error: msg.error,
            errorDetails: msg.errorDetails,
            isApiErrorMessage: msg.isApiErrorMessage,
            container: msg.container,
            stopSequence: msg.stopSequence
        )
    }
    return result
}
