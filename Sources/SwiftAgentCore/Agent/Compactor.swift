import Foundation

/// LLM-based conversation compaction service.
/// Matches Claude Code's services/compact/compact.ts and autoCompact.ts.
///
/// Produces CompactionResult values; state mutation is handled by QueryEngine.
public struct Compactor: Sendable {
    public let client: LLMClient
    public let modelRegistry: ModelRegistry

    public init(client: LLMClient, modelRegistry: ModelRegistry) {
        self.client = client
        self.modelRegistry = modelRegistry
    }

    // MARK: - Thresholds (matching CC's autoCompact.ts)

    /// Buffer tokens for autocompact threshold calculation.
    /// Matches CC's AUTOCOMPACT_BUFFER_TOKENS.
    public static let autocompactBufferTokens = 13_000

    /// Max consecutive autocompact failures before circuit breaker.
    /// Matches CC's MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES.
    public static let maxConsecutiveFailures = 3

    /// Max output tokens for the compaction summary LLM call.
    /// Matches CC's MAX_OUTPUT_TOKENS_FOR_SUMMARY.
    public static let maxOutputTokensForSummary = 20_000

    // MARK: - Effective Context Window

    /// Compute effective context window size (context window minus summary output reservation).
    /// Matches CC's getEffectiveContextWindowSize().
    public func effectiveContextWindow(for model: String) -> Int {
        let info = modelRegistry.info(for: model)
        let reserved = min(info?.maxOutput ?? 8192, Self.maxOutputTokensForSummary)
        let window = modelRegistry.effectiveContextWindow(for: model)
        return window - reserved
    }

    /// Compute the autocompact trigger threshold.
    /// Matches CC's getAutoCompactThreshold().
    public func autoCompactThreshold(for model: String) -> Int {
        effectiveContextWindow(for: model) - Self.autocompactBufferTokens
    }

    // MARK: - Auto-Compact Checks

    /// Whether autocompact should trigger for the given token count and model.
    /// Matches CC's shouldAutoCompact().
    public func shouldAutoCompact(tokenCount: Int, model: String, autoCompactEnabled: Bool = true) -> Bool {
        guard autoCompactEnabled else { return false }
        let threshold = autoCompactThreshold(for: model)
        return tokenCount >= threshold
    }

    /// Check if at the blocking limit (hard stop, no further compaction possible).
    /// Matches CC's blocking_limit check.
    public func isAtBlockingLimit(tokenCount: Int, model: String) -> Bool {
        let effective = effectiveContextWindow(for: model)
        return tokenCount >= effective - 3_000
    }

    // MARK: - Strip Images

    /// Strip image/document blocks from messages before compaction.
    /// Matches CC's stripImagesFromMessages().
    public func stripImagesFromMessages(_ messages: [Message]) -> [Message] {
        messages.map { message in
            guard message.type == .user else { return message }
            var hasMedia = false
            let newBlocks: [ContentBlock] = message.content.compactMap { block in
                switch block {
                case .image:
                    hasMedia = true
                    return .text("[image]")
                case .document:
                    hasMedia = true
                    return .text("[document]")
                case .toolResult(let toolUseID, let content, let isError):
                    // Strip images nested in tool_result content arrays
                    var toolHasMedia = false
                    let newToolContent: ToolResultContent
                    switch content {
                    case .string(let s):
                        newToolContent = .string(s)
                    case .blocks(let items):
                        let newItems = items.map { item -> ContentBlock in
                            switch item {
                            case .image:
                                toolHasMedia = true
                                return .text("[image]")
                            case .document:
                                toolHasMedia = true
                                return .text("[document]")
                            default:
                                return item
                            }
                        }
                        newToolContent = .blocks(newItems)
                    }
                    if toolHasMedia {
                        hasMedia = true
                        return .toolResult(toolUseID: toolUseID, content: newToolContent, isError: isError)
                    }
                    return block
                default:
                    return block
                }
            }
            guard hasMedia else { return message }
            return Message(type: .user, content: newBlocks)
        }
    }

    // MARK: - Compaction Prompt

    /// Build the compaction summary prompt.
    /// Matches CC's getCompactPrompt().
    public func compactPrompt(customInstructions: String? = nil) -> String {
        let base = """
        CRITICAL: Respond with TEXT ONLY. Do NOT call any tools. Tool calls will be rejected and waste the only turn.

        You are creating a detailed summary of a conversation between an AI agent and a user. All tasks described below are already completed -- you are NOT executing anything.

        Produce a structured conversation summary with these 9 sections:

        1. Primary Request and Intent:
        2. Key Technical Concepts:
        3. Files and Code Sections:
        4. Errors and fixes:
        5. Problem Solving:
        6. All user messages:
        7. Pending Tasks:
        8. Current Work:
        9. Optional Next Step:

        Wrap your output in <summary> tags. You may use <analysis> tags for a scratchpad before the summary.
        """

        guard let instructions = customInstructions, !instructions.isEmpty else { return base }
        return base + "\n\nAdditional instructions: \(instructions)"
    }

    /// Format the LLM summary output for user-facing display.
    /// Matches CC's formatCompactSummary().
    public func formatSummary(_ raw: String) -> String {
        var text = raw
        // Strip <analysis> block
        if let analysisRange = text.range(of: "<analysis>") {
            if let endRange = text.range(of: "</analysis>") {
                text.removeSubrange(analysisRange.lowerBound..<endRange.upperBound)
            }
        }
        // Replace <summary> tags
        text = text.replacingOccurrences(of: "<summary>", with: "Summary:")
        text = text.replacingOccurrences(of: "</summary>", with: "")
        return text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build the user-facing compact summary message.
    /// Matches CC's getCompactUserSummaryMessage().
    public func compactUserSummaryMessage(
        _ summary: String,
        suppressFollowUpQuestions: Bool = false,
        transcriptPath: String? = nil
    ) -> String {
        let formatted = formatSummary(summary)
        let header = "This session is being continued from a previous conversation that ran out of context. The summary below covers the earlier portion of the conversation."
        let suppress = suppressFollowUpQuestions
            ? "\n\nContinue the conversation from where it left off without asking the user any further questions. Resume directly -- do not acknowledge the summary, do not preface with \"I'll continue\" or similar. Pick up the last task as if the break never happened."
            : ""
        let detail = transcriptPath.map { "\n\nIf you need specific details from before compaction (like exact code snippets, error messages, or content you generated), read the full transcript at: \($0)" } ?? ""
        return "\(header)\n\n\(formatted)\(suppress)\(detail)"
    }

    // MARK: - Stream Compact Summary

    /// Stream a compaction summary from the LLM.
    /// Matches CC's streamCompactSummary().
    public func streamCompactSummary(
        messages: [Message],
        customInstructions: String?,
        model: String
    ) async throws -> String {
        let prompt = compactPrompt(customInstructions: customInstructions)
        let requestMessage = Message(type: .user, content: [.text(prompt)])

        // Strip images before sending
        let stripped = stripImagesFromMessages(messages)
        let apiMessages = stripped + [requestMessage]

        let info = modelRegistry.info(for: model)
        let maxOut = min(info?.maxOutput ?? 8192, Self.maxOutputTokensForSummary)

        let stream = client.send(
            messages: apiMessages,
            model: model,
            systemPrompt: nil,
            maxTokens: maxOut,
            tools: nil,
            thinking: .disabled,
            enablePromptCaching: false
        )

        var summaryText = ""
        for try await event in stream {
            if case .textDelta(let text) = event {
                summaryText += text
            }
        }

        let formatted = formatSummary(summaryText)
        guard !formatted.isEmpty else {
            throw CompactionError.noSummary
        }
        return formatted
    }

    // MARK: - Auto Compact

    /// Result of autoCompactIfNeeded.
    public struct AutoCompactOutcome: Sendable {
        public let result: CompactionResult
        public let newMessages: [Message]
        public let trackingUpdate: AutoCompactTrackingState
    }

    /// Auto-compact the conversation. Returns outcome for the caller to apply.
    /// Matches CC's autoCompactIfNeeded().
    public func autoCompactIfNeeded(
        messages: [Message],
        model: String,
        tracking: AutoCompactTrackingState,
        suppressFollowUpQuestions: Bool = true
    ) async throws -> AutoCompactOutcome? {
        let tokenCount = estimateTokenCount(messages)

        guard shouldAutoCompact(tokenCount: tokenCount, model: model) else {
            return nil
        }

        // Circuit breaker: stop after consecutive failures
        if let failures = tracking.consecutiveFailures, failures >= Self.maxConsecutiveFailures {
            return nil
        }

        if isAtBlockingLimit(tokenCount: tokenCount, model: model) {
            throw CompactionError.blockingLimit(tokenCount: tokenCount)
        }

        let preCompactCount = tokenCount
        let isRecompaction = tracking.compacted && tracking.turnCounter > 0

        do {
            let summary = try await streamCompactSummary(
                messages: messages,
                customInstructions: nil,
                model: model
            )

            let compactMessage = compactUserSummaryMessage(
                summary,
                suppressFollowUpQuestions: suppressFollowUpQuestions
            )

            let metadata = CompactMetadata(
                trigger: .auto,
                preTokens: preCompactCount,
                messagesSummarized: messages.count
            )
            let boundaryMarker = SystemMessage(
                subtype: .compactBoundary(
                    content: compactMessage,
                    level: .info,
                    compactMetadata: metadata,
                    logicalParentUuid: nil
                )
            )

            let summaryMessage = Message(
                type: .user,
                content: [.text(compactMessage)],
                isCompactSummary: true,
                isVisibleInTranscriptOnly: true
            )

            let postCompactMessages = buildPostCompactMessages(
                boundaryMarker: boundaryMarker,
                summaryMessages: [summaryMessage],
                attachments: [],
                hookResults: []
            )

            let truePostCount = estimateTokenCount(postCompactMessages)

            let result = CompactionResult(
                boundaryMarker: boundaryMarker,
                summaryMessages: [summaryMessage],
                attachments: [],
                hookResults: [],
                messagesToKeep: nil,
                userDisplayMessage: nil,
                preCompactTokenCount: preCompactCount,
                postCompactTokenCount: truePostCount,
                truePostCompactTokenCount: truePostCount,
                compactionUsage: nil
            )

            let newTracking = AutoCompactTrackingState(
                compacted: true,
                turnCounter: tracking.turnCounter + 1,
                turnId: UUID().uuidString,
                consecutiveFailures: nil
            )

            return AutoCompactOutcome(
                result: result,
                newMessages: postCompactMessages,
                trackingUpdate: newTracking
            )
        } catch {
            let newTracking = AutoCompactTrackingState(
                compacted: false,
                turnCounter: tracking.turnCounter,
                turnId: tracking.turnId,
                consecutiveFailures: (tracking.consecutiveFailures ?? 0) + 1
            )
            throw CompactionError.autocompactFailed(underlying: error, tracking: newTracking)
        }
    }

    // MARK: - Build Post-Compact Messages

    /// Assemble post-compact message array.
    /// Matches CC's buildPostCompactMessages().
    public func buildPostCompactMessages(
        boundaryMarker: SystemMessage,
        summaryMessages: [Message],
        attachments: [Message],
        hookResults: [Message],
        messagesToKeep: [Message]? = nil
    ) -> [Message] {
        var result: [Message] = []
        // Convert boundary system message to a proper Message
        result.append(Message(
            type: .system,
            content: [.text("[compact_boundary: \(boundaryMarker.subtype.subtypeLiteral)]")],
            isMeta: true
        ))
        result.append(contentsOf: summaryMessages)
        if let keep = messagesToKeep {
            result.append(contentsOf: keep)
        }
        result.append(contentsOf: attachments)
        result.append(contentsOf: hookResults)
        return result
    }

    // MARK: - Token Estimation

    /// Rough token count estimate (4 chars ≈ 1 token for English text).
    /// Matches CC's roughTokenCountEstimation.
    public func estimateTokenCount(_ messages: [Message]) -> Int {
        var chars = 0
        for message in messages {
            for block in message.content {
                chars += block.estimatedCharCount
            }
        }
        return max(1, chars / 4)
    }
}

// MARK: - Compaction Errors

public enum CompactionError: Error, LocalizedError {
    case noSummary
    case notEnoughMessages
    case blockingLimit(tokenCount: Int)
    case promptTooLong
    case autocompactFailed(underlying: Error, tracking: AutoCompactTrackingState)

    public var errorDescription: String? {
        switch self {
        case .noSummary:
            return "Failed to generate conversation summary"
        case .notEnoughMessages:
            return "Not enough messages to compact"
        case .blockingLimit(let count):
            return "Context window at blocking limit (\(count) tokens)"
        case .promptTooLong:
            return "Compaction prompt too long"
        case .autocompactFailed(let error, _):
            return "Autocompact failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - ContentBlock Helpers

extension ContentBlock {
    /// Estimated character count for token estimation.
    var estimatedCharCount: Int {
        switch self {
        case .text(let s):
            return s.count
        case .thinking(let s, _):
            return s.count
        case .redactedThinking(let s):
            return s.count
        case .toolUse(_, let name, let input):
            return name.count + inputJSONCharCount(input)
        case .serverToolUse(_, let name, let input):
            return name.count + inputJSONCharCount(input)
        case .toolResult(_, let content, _):
            switch content {
            case .string(let s): return s.count
            case .blocks(let items): return items.reduce(0) { $0 + $1.estimatedCharCount }
            }
        case .image(_, _, let data, _):
            return (data?.count ?? 0) / 4
        case .document(_, _, let data):
            return data.count / 4
        case .toolReference(let name, let desc):
            return name.count + desc.count
        }
    }

    private func inputJSONCharCount(_ value: JSONValue) -> Int {
        switch value {
        case .string(let s): return s.count
        case .number: return 4
        case .bool: return 4
        case .null: return 1
        case .array(let arr): return arr.reduce(0) { $0 + inputJSONCharCount($1) }
        case .object(let dict): return dict.reduce(0) { $0 + $1.key.count + inputJSONCharCount($1.value) }
        }
    }
}
