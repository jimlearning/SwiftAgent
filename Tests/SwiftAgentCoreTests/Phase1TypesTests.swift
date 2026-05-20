import Testing
import Foundation
@testable import SwiftAgentCore

struct ConversationTests {
    @Test
    func roleCodableRoundtrip() throws {
        let roles: [MessageRole] = [.system, .user, .assistant]
        for role in roles {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(MessageRole.self, from: data)
            #expect(decoded == role)
        }
    }

    @Test
    func messageCreation() {
        let msg = Message(type: .user, content: [.text("hello")])
        #expect(msg.type == .user)
        #expect(msg.content.count == 1)
    }

    @Test
    func conversationMessagesOrder() {
        var conversation = Conversation(systemPrompt: "You are helpful.")
        let userMsg = Message(type: .user, content: [.text("hi")])
        let assistantMsg = Message(type: .assistant, content: [.text("Hello!")])
        let turn = Turn(userMessage: userMsg, assistantMessage: assistantMsg)
        conversation.turns.append(turn)

        let messages = conversation.messages
        #expect(messages.count == 3)  // system + user + assistant
        #expect(messages[0].type == .system)
        #expect(messages[1].type == .user)
        #expect(messages[2].type == .assistant)
    }

    @Test
    func jsonValueEncoding() throws {
        let obj = JSONValue.object(["key": .string("value"), "num": .number(42)])
        let data = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .object(let dict) = decoded {
            #expect(dict["key"] == .string("value"))
        } else {
            Issue.record("Expected object")
        }
    }
}

struct ToolTests {
    struct MockReadTool: Tool {
        var name: String { "View" }
        func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Read files" }
        var inputSchema: JSONSchema { JSONSchema(type: "object", properties: ["path": JSONSchemaProperty(type: "string")]) }
        var isReadOnly: Bool { true }
        var isConcurrencySafe: Bool { true }

        func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn?, parentMessage: Message?, onProgress: ToolCallProgress?) async throws -> ToolResult {
            return ToolResult(content: "file contents")
        }
    }

    @Test
    func toolProtocolDefaults() {
        let tool = MockReadTool()
        #expect(tool.isReadOnly == true)
        #expect(tool.isConcurrencySafe == true)
        #expect(tool.name == "View")
        #expect(tool.inputSchema.type == "object")
    }

    @Test
    func toolContextInitialization() {
        let ctx = ToolUseContext(workingDirectory: "/tmp", sessionID: "s1")
        #expect(ctx.workingDirectory == "/tmp")
        #expect(ctx.sessionID == "s1")
        #expect(ctx.approvalToken == nil)
    }

    @Test
    func toolResultErrorFlag() {
        let result = ToolResult(content: "err", isError: true)
        #expect(result.isError == true)
    }
}

struct PermissionTests {
    @Test
    func permissionModesAllCases() {
        #expect(PermissionMode.allCases.count == 7)
    }

    @Test
    func permissionModeCodableRoundtrip() throws {
        for mode in PermissionMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PermissionMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test
    func permissionRuleCreation() {
        let rule = PermissionRule(ruleBehavior: .ask, ruleValue: PermissionRuleValue(toolName: "Bash"))
        #expect(rule.ruleValue.toolName == "Bash")
        #expect(rule.ruleBehavior == .ask)
    }
}

struct ConfigTests {
    @Test
    func defaultSettings() {
        let s = Settings()
        #expect(s.permissionMode == .default)
        #expect(s.maxTokens == 200_000)
    }

    @Test
    func modelConfigDefaults() {
        let m = ModelConfig()
        #expect(m.provider == .firstParty)
        #expect(m.modelID == "claude-sonnet-4-6")
    }
}

struct AgentTests {
    @Test
    func agentDefinitionDefaultRole() {
        let def = AgentDefinition(name: "test", description: "desc", systemPrompt: "prompt")
        #expect(def.role == .generalPurpose)
        #expect(def.tools == nil)
    }

    @Test
    func agentContextInitialization() {
        let ctx = AgentContext(parentSessionId: "p1", workingDirectory: "/tmp")
        #expect(ctx.parentSessionId == "p1")
        #expect(ctx.permissionMode == .default)
    }
}

struct SessionTests {
    @Test
    func sessionDefaults() {
        let s = Session()
        #expect(s.tags.isEmpty)
        #expect(s.branch == nil)
    }

    @Test
    func conversationHistoryRecent() {
        var history = ConversationHistory()
        let old = Session(createdAt: Date.distantPast, updatedAt: Date.distantPast)
        let recent = Session(createdAt: Date(), updatedAt: Date())
        history.addSession(old)
        history.addSession(recent)
        let recentSessions = history.recentSessions(limit: 1)
        #expect(recentSessions.first?.id == recent.id)
    }
}

struct ClassifierTypesTests {
    @Test
    func classifierResultDefault() {
        let r = ClassifierResult(matches: true, confidence: .high, reason: "test")
        #expect(r.matches == true)
        #expect(r.confidence == .high)
        #expect(r.reason == "test")
        #expect(r.matchedDescription == nil)
    }

    @Test
    func riskLevelRawValues() {
        #expect(RiskLevel.low.rawValue == "LOW")
        #expect(RiskLevel.medium.rawValue == "MEDIUM")
        #expect(RiskLevel.high.rawValue == "HIGH")
    }

    @Test
    func yoloClassifierResultDefault() {
        let r = YoloClassifierResult(shouldBlock: true, reason: "danger", model: "claude-haiku")
        #expect(r.shouldBlock == true)
        #expect(r.model == "claude-haiku")
        #expect(r.stage == nil)
    }

    @Test
    func classifierUsageFields() {
        let u = ClassifierUsage(inputTokens: 100, outputTokens: 50, cacheReadInputTokens: 10, cacheCreationInputTokens: 5)
        #expect(u.inputTokens == 100)
        #expect(u.outputTokens == 50)
        #expect(u.cacheReadInputTokens == 10)
        #expect(u.cacheCreationInputTokens == 5)
    }

    @Test
    func cacheScopeCases() {
        #expect(CacheScope.allCases.count == 2)
    }

    @Test
    func systemPromptBlockCreation() {
        let block = SystemPromptBlock(text: "You are helpful.", cacheScope: .global)
        #expect(block.text == "You are helpful.")
        #expect(block.cacheScope == .global)
    }
}

struct CompactionTypesTests {
    @Test
    func compactProgressEventCases() {
        let evt = CompactProgressEvent.compactStart
        if case .compactStart = evt {} else { Issue.record("Expected compactStart") }
    }

    @Test
    func tokenWarningStateDefaults() {
        let state = TokenWarningState()
        #expect(state.percentLeft == 100)
        #expect(!state.isAtBlockingLimit)
    }

    @Test
    func autoCompactTrackingStateDefaults() {
        let state = AutoCompactTrackingState()
        #expect(!state.compacted)
        #expect(state.turnCounter == 0)
    }

    @Test
    func compactionConstants() {
        #expect(CompactionConstants.autocompactBufferTokens == 13_000)
        #expect(CompactionConstants.maxConsecutiveAutocompactFailures == 3)
    }

    @Test
    func modelKeyEnumCount() {
        #expect(ModelKey.allCases.count == 11)
    }

    @Test
    func modelKeyCanonicalID() {
        #expect(ModelKey.haiku35.canonicalID == "claude-3-5-haiku-20241022")
        #expect(ModelKey.sonnet46.canonicalID == "claude-sonnet-4-6")
        #expect(ModelKey.opus46.canonicalID == "claude-opus-4-6")
    }

    @Test
    func canonicalModelIDsNotEmpty() {
        #expect(CANONICAL_MODEL_IDS.count == 11)
    }
}

struct ToolResultStorageTests {
    @Test
    func formatFileSizeSmall() {
        #expect(ToolResultStorage.formatFileSize(500) == "500B")
    }

    @Test
    func formatFileSizeKB() {
        let result = ToolResultStorage.formatFileSize(2500)
        #expect(result.contains("KB"))
    }

    @Test
    func shouldPersistBelowThreshold() {
        let content = String(repeating: "a", count: 100)
        #expect(!ToolResultStorage.shouldPersist(content, threshold: 50_000))
    }

    @Test
    func shouldPersistAboveThreshold() {
        let content = String(repeating: "a", count: 60_000)
        #expect(ToolResultStorage.shouldPersist(content, threshold: 50_000))
    }

    @Test
    func generatePreviewShorterThanMax() {
        let content = "hello"
        let preview = ToolResultStorage.generatePreview(content, maxBytes: 2000)
        #expect(preview == "hello")
    }

    @Test
    func generatePreviewLongerThanMax() {
        let content = String(repeating: "x", count: 3000)
        let preview = ToolResultStorage.generatePreview(content, maxBytes: 2000)
        #expect(preview.utf8.count <= 2000)
    }

    @Test
    func sanitizePathRemovesSlashes() {
        let result = ToolResultStorage.sanitizePath("/Users/jim/SwiftAgent")
        #expect(!result.contains("/"))
    }

    @Test
    func processToolResultBelowThreshold() {
        let content = "small result"
        let (out, persisted, path) = ToolResultStorage.processToolResult(
            content: content,
            toolName: "Bash",
            maxResultSizeChars: 100_000,
            toolUseId: "test1",
            cwd: "/tmp/test",
            sessionId: "s1"
        )
        #expect(!persisted)
        #expect(out == content)
        #expect(path == nil)
    }

    @Test
    func constantsMatchCC() {
        #expect(PERSISTED_OUTPUT_TAG == "<persisted-output>")
        #expect(PERSISTED_OUTPUT_CLOSING_TAG == "</persisted-output>")
        #expect(TOOL_RESULT_CLEARED_MESSAGE == "[Old tool result content cleared]")
        #expect(DEFAULT_MAX_RESULT_SIZE_CHARS == 50_000)
    }
}
