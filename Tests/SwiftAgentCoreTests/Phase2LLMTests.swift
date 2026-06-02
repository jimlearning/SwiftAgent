import Testing
import Foundation
@testable import SwiftAgentCore

struct StreamParserTests {
    @Test
    func parsesTextDelta() {
        let parser = LLMStreamParser()
        let json = """
        {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}
        """
        let data = json.data(using: .utf8)!
        let event = parser.parse(data: data)
        guard case .textDelta(let text) = event else {
            Issue.record("Expected textDelta, got \(String(describing: event))")
            return
        }
        #expect(text == "Hello")
    }

    @Test
    func parsesMessageStart() {
        let parser = LLMStreamParser()
        let json = """
        {"type": "message_start", "message": {"id": "msg_001", "type": "message", "role": "assistant", "model": "claude-sonnet-4-6", "content": []}}
        """
        let data = json.data(using: .utf8)!
        let event = parser.parse(data: data)
        guard case .messageStart(let msg) = event else {
            Issue.record("Expected messageStart, got \(String(describing: event))")
            return
        }
        #expect(msg.model == "claude-sonnet-4-6")
        #expect(msg.messageID == "msg_001")
    }

    @Test
    func parsesToolUseBlockStart() {
        let parser = LLMStreamParser()
        let json = """
        {"type": "content_block_start", "index": 1, "content_block": {"type": "tool_use", "id": "toolu_001", "name": "View"}}
        """
        let data = json.data(using: .utf8)!
        let event = parser.parse(data: data)
        guard case .contentBlockStart(let index, let block) = event else {
            Issue.record("Expected contentBlockStart, got \(String(describing: event))")
            return
        }
        #expect(index == 1)
        guard case .toolUse(let name, let id) = block else {
            Issue.record("Expected toolUse block")
            return
        }
        #expect(name == "View")
        #expect(id == "toolu_001")
    }

    @Test
    func parsesMessageStop() {
        let parser = LLMStreamParser()
        let json = """
        {"type": "message_stop"}
        """
        let data = json.data(using: .utf8)!
        let event = parser.parse(data: data)
        guard case .messageStop = event else {
            Issue.record("Expected messageStop, got \(String(describing: event))")
            return
        }
    }
}

struct RetryPolicyTests {
    private actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    @Test
    func succeedsOnFirstAttempt() async throws {
        let policy = RetryPolicy(maxRetries: 3)
        let counter = Counter()
        let result = try await policy.execute {
            await counter.increment()
            return 42
        }
        #expect(result == 42)
        let count = await counter.value
        #expect(count == 1)
    }

    @Test
    func retriesThenSucceeds() async throws {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 0.01, maxDelay: 0.05)
        let counter = Counter()
        let result = try await policy.execute {
            await counter.increment()
            let count = await counter.value
            if count < 3 { throw NSError(domain: "test", code: 1) }
            return "ok"
        }
        #expect(result == "ok")
        let count = await counter.value
        #expect(count == 3)
    }

    @Test
    func exhaustsRetries() async {
        let policy = RetryPolicy(maxRetries: 2, baseDelay: 0.01, maxDelay: 0.05)
        let counter = Counter()
        do {
            _ = try await policy.execute {
                await counter.increment()
                throw NSError(domain: "test", code: 1)
            }
            Issue.record("Expected error")
        } catch {
            let count = await counter.value
            #expect(count == 2)
        }
    }
}

struct ModelRegistryTests {
    @Test
    func hasRequiredModels() {
        let registry = ModelRegistry.shared
        #expect(registry.info(for: "claude-sonnet-4-6") != nil)
        #expect(registry.info(for: "claude-opus-4-7") != nil)
        #expect(registry.info(for: "claude-haiku-4-5") != nil)
    }

    @Test
    func defaultModelIsSonnet() {
        #expect(ModelRegistry.shared.defaultModel == "claude-sonnet-4-6")
    }

    @Test
    func effectiveContextWindowReservesOutput() {
        let window = ModelRegistry.shared.effectiveContextWindow(for: "claude-sonnet-4-6")
        #expect(window == 180_000)  // 200K - 20K
    }
}

struct TokenCounterTests {
    @Test
    func countsEnglishText() {
        let counter = TokenCounter()
        let tokens = counter.count("Hello world, this is a test.")
        #expect(tokens > 0)
        #expect(tokens < 50)
    }

    @Test
    func countsMessages() {
        let counter = TokenCounter()
        let msg = Message(type: .user, content: [.text("Hello! How are you?")])
        let tokens = counter.count(msg)
        #expect(tokens > 0)
    }

    @Test
    func warningLevels() {
        let counter = TokenCounter()
        #expect(counter.warningLevel(currentTokens: 50_000, contextWindow: 200_000) == .green)
        #expect(counter.warningLevel(currentTokens: 120_000, contextWindow: 200_000) == .yellow)
        #expect(counter.warningLevel(currentTokens: 160_000, contextWindow: 200_000) == .orange)
        #expect(counter.warningLevel(currentTokens: 190_000, contextWindow: 200_000) == .red)
    }

    @Test
    func wouldExceedContext() {
        let counter = TokenCounter()
        #expect(counter.wouldExceedContext(currentTokens: 170_000, additionalTokens: 20_000, contextWindow: 180_000))
        #expect(!counter.wouldExceedContext(currentTokens: 150_000, additionalTokens: 10_000, contextWindow: 180_000))
    }
}

// MARK: - Prompt Caching Tests

struct SystemPromptCachingTests {
    @Test
    func boundaryMarkerExists() {
        // Verify the boundary constant is non-empty and searchable.
        #expect(!SYSTEM_PROMPT_DYNAMIC_BOUNDARY.isEmpty)
        #expect(SYSTEM_PROMPT_DYNAMIC_BOUNDARY.contains("DYNAMIC_BOUNDARY"))
    }

    @Test
    func buildIncludesBoundaryMarker() {
        let builder = SystemPromptBuilder()
        let prompt = builder.build(for: Conversation(), toolNames: ["Bash", "Read"])
        #expect(prompt.contains(SYSTEM_PROMPT_DYNAMIC_BOUNDARY))
    }

    @Test
    func toolGuidanceInStaticPrefix() {
        // "Using your tools" is in the STATIC prefix (before boundary) in CC —
        // it's cacheable. Tool names are interpolated, but the guidance text
        // itself is static. Session-specific guidance (AskUserQuestion, Agent, !)
        // is after the boundary.
        let builder = SystemPromptBuilder()
        let prompt = builder.build(for: Conversation(), toolNames: ["Bash", "Read"])
        guard let boundaryRange = prompt.range(of: SYSTEM_PROMPT_DYNAMIC_BOUNDARY) else {
            Issue.record("Boundary marker not found in prompt")
            return
        }
        let beforeBoundary = String(prompt[..<boundaryRange.lowerBound])
        #expect(beforeBoundary.contains("Using your tools"),
                "Tool guidance should be in the static prefix (before boundary)")
    }

    @Test
    func staticPrefixExcludesEnvironmentSection() {
        // The static prefix (before boundary) should NOT contain the environment
        // section. However, the phrases "working directory" and "CLAUDE.md" do
        // appear in CC-aligned static sections ("Doing tasks" references working
        // directory context; "Executing actions" references CLAUDE.md authorization
        // files). So we check for the environment section header instead.
        let builder = SystemPromptBuilder()
        let prompt = builder.build(for: Conversation(), toolNames: ["Bash"])
        guard let boundaryRange = prompt.range(of: SYSTEM_PROMPT_DYNAMIC_BOUNDARY) else {
            Issue.record("Boundary marker not found")
            return
        }
        let afterBoundary = String(prompt[boundaryRange.upperBound...])
        // Environment section should be after the boundary (dynamic)
        #expect(afterBoundary.contains("Primary working directory"),
                "Environment section should be after the dynamic boundary")
    }
}

struct CacheControlPlacementTests {
    @Test
    func systemPromptBoundaryCreatesGlobalStaticCacheBlock() {
        let client = LLMClient(apiKey: "test")
        let prompt = "STATIC\n\n\(SYSTEM_PROMPT_DYNAMIC_BOUNDARY)\n\nDYNAMIC"
        let formatted = client.apiFormattedSystem(prompt, enablePromptCaching: true)
        guard let blocks = formatted as? [[String: Any]], blocks.count == 2 else {
            Issue.record("Expected split system prompt blocks")
            return
        }

        #expect(blocks[0]["type"] as? String == "text")
        #expect(blocks[0]["text"] as? String == "STATIC")
        let cacheControl = blocks[0]["cache_control"] as? [String: String]
        #expect(cacheControl?["type"] == "ephemeral")
        #expect(cacheControl?["scope"] == "global")
        #expect(blocks[1]["text"] as? String == "DYNAMIC")
        #expect(blocks[1]["cache_control"] == nil)
    }

    @Test
    func systemPromptWithoutBoundaryUsesLegacySingleCacheBlock() {
        let client = LLMClient(apiKey: "test")
        let formatted = client.apiFormattedSystem("STATIC ONLY", enablePromptCaching: true)
        guard let blocks = formatted as? [[String: Any]], blocks.count == 1 else {
            Issue.record("Expected one system prompt block")
            return
        }

        let cacheControl = blocks[0]["cache_control"] as? [String: String]
        #expect(blocks[0]["text"] as? String == "STATIC ONLY")
        #expect(cacheControl?["type"] == "ephemeral")
        #expect(cacheControl?["scope"] == nil)
    }

    @Test
    func requestBodyUsesSystemGlobalCacheInsteadOfToolCache() {
        let client = LLMClient(apiKey: "test")
        let prompt = "STATIC\n\(SYSTEM_PROMPT_DYNAMIC_BOUNDARY)\nDYNAMIC"
        let tools = [
            ToolDefinition(name: "Read", description: "Read files", inputSchema: JSONSchema(type: "object")),
            ToolDefinition(name: "Write", description: "Write files", inputSchema: JSONSchema(type: "object"))
        ]
        let messages = [Message(type: .user, content: [.text("hello")])]

        let streaming = client.buildMessagesRequestBody(
            messages: messages,
            model: "deepseek-v4-pro",
            stream: true,
            systemPrompt: prompt,
            maxTokens: 1024,
            tools: tools,
            enablePromptCaching: true
        )
        let nonStreaming = client.buildMessagesRequestBody(
            messages: messages,
            model: "deepseek-v4-pro",
            stream: false,
            systemPrompt: prompt,
            maxTokens: 1024,
            tools: tools,
            enablePromptCaching: true
        )

        #expect(countCacheControl(in: streaming["messages"]) == 1)
        #expect(countCacheControl(in: streaming["system"]) == 1)
        #expect(countCacheControl(in: streaming["tools"]) == 0)
        #expect(countCacheControl(in: nonStreaming["messages"]) == 1)
        #expect(countCacheControl(in: nonStreaming["system"]) == 1)
        #expect(countCacheControl(in: nonStreaming["tools"]) == 0)
    }

    @Test
    func cacheControlOnLastTextBlock() {
        let msg = Message(type: .user, content: [.text("Hello")])
        let formatted = msg.apiFormattedWithCache
        let content = formatted["content"] as? [[String: Any]]
        guard let firstBlock = content?.first else {
            Issue.record("No content blocks")
            return
        }
        #expect(firstBlock["type"] as? String == "text")
        let cc = firstBlock["cache_control"] as? [String: String]
        #expect(cc?["type"] == "ephemeral", "cache_control should be on the last (only) text block")
    }

    @Test
    func cacheControlOnLastToolResult() {
        let msg = Message(type: .user, content: [
            .toolResult(toolUseID: "t1", content: .string("result1"), isError: false),
            .toolResult(toolUseID: "t2", content: .string("result2"), isError: false)
        ])
        let formatted = msg.apiFormattedWithCache
        let content = formatted["content"] as? [[String: Any]]
        guard let blocks = content, blocks.count == 2 else {
            Issue.record("Expected 2 content blocks")
            return
        }
        // First block: no cache_control
        #expect(blocks[0]["cache_control"] == nil)
        // Last block: has cache_control
        let cc = blocks[1]["cache_control"] as? [String: String]
        #expect(cc?["type"] == "ephemeral", "cache_control should be on last tool_result block")
    }

    @Test
    func skipsThinkingBlockForCacheControl() {
        // When the last content block is a thinking block, cache_control should
        // be placed on the preceding cacheable block instead.
        let msg = Message(type: .assistant, content: [
            .thinking("Let me think..."),
            .text("Here is the answer")
        ])
        let formatted = msg.apiFormattedWithCache
        let content = formatted["content"] as? [[String: Any]]
        guard let blocks = content, blocks.count == 2 else {
            Issue.record("Expected 2 content blocks")
            return
        }
        // Thinking block (index 0): no cache_control
        #expect(blocks[0]["type"] as? String == "thinking")
        #expect(blocks[0]["cache_control"] == nil, "Thinking block should not get cache_control")
        // Text block (index 1): should have cache_control since it's the last cacheable block
        #expect(blocks[1]["type"] as? String == "text")
        let cc = blocks[1]["cache_control"] as? [String: String]
        #expect(cc?["type"] == "ephemeral", "cache_control should be on the text block after skipping thinking")
    }

    @Test
    func skipsRedactedThinkingBlock() {
        let msg = Message(type: .assistant, content: [
            .text("Response"),
            .redactedThinking("redacted")
        ])
        let formatted = msg.apiFormattedWithCache
        let content = formatted["content"] as? [[String: Any]]
        guard let blocks = content, blocks.count == 2 else {
            Issue.record("Expected 2 content blocks")
            return
        }
        // Text block (index 0): should get cache_control (last cacheable before redactedThinking)
        let cc = blocks[0]["cache_control"] as? [String: String]
        #expect(cc?["type"] == "ephemeral", "cache_control should walk back past redactedThinking")
        // Redacted thinking block (index 1): no cache_control
        #expect(blocks[1]["cache_control"] == nil)
    }

    @Test
    func allThinkingBlocksNoCacheControl() {
        // Edge case: message with only thinking blocks — no cache_control at all.
        let msg = Message(type: .assistant, content: [
            .thinking("think1"),
            .thinking("think2")
        ])
        let formatted = msg.apiFormattedWithCache
        let content = formatted["content"] as? [[String: Any]]
        guard let blocks = content else {
            Issue.record("No content blocks")
            return
        }
        for block in blocks {
            #expect(block["cache_control"] == nil, "No block should get cache_control when all are thinking")
        }
    }
}

private func countCacheControl(in value: Any?) -> Int {
    if let dict = value as? [String: Any] {
        let here = dict["cache_control"] == nil ? 0 : 1
        return here + dict.values.map { countCacheControl(in: $0) }.reduce(0, +)
    }
    if let array = value as? [Any] {
        return array.map { countCacheControl(in: $0) }.reduce(0, +)
    }
    return 0
}

struct ToolRegistryCachingTests {
    @Test
    func toolDefinitionsAreSortedAndStable() async {
        let registry = ToolRegistry()
        registry.register(WriteCacheTestTool())
        registry.register(ReadCacheTestTool())

        let first = await registry.toolDefinitions()
        let second = await registry.toolDefinitions()

        #expect(first.map(\.name) == ["Read", "Write"])
        #expect(second.map(\.name) == ["Read", "Write"])
        #expect(first.map(\.apiFormattedDescription) == second.map(\.apiFormattedDescription))
    }
}

private struct ReadCacheTestTool: Tool {
    let name = "Read"
    let inputSchema = JSONSchema(type: "object")
    func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "read"
    }
    func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn?,
        parentMessage: Message?,
        onProgress: ToolCallProgress?
    ) async throws -> ToolResult {
        ToolResult(content: "")
    }
}

private struct WriteCacheTestTool: Tool {
    let name = "Write"
    let inputSchema = JSONSchema(type: "object")
    func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "write"
    }
    func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn?,
        parentMessage: Message?,
        onProgress: ToolCallProgress?
    ) async throws -> ToolResult {
        ToolResult(content: "")
    }
}

private extension ToolDefinition {
    var apiFormattedDescription: String {
        apiFormatted["description"] as? String ?? ""
    }
}
