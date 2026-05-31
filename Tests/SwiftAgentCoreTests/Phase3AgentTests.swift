import Testing
import Foundation
@testable import SwiftAgentCore

struct ContextManagerTests {
    @Test
    func countsMessages() {
        let cm = ContextManager()
        let msg = Message(type: .user, content: [.text("hello world this is a test message")])
        let count = cm.count(messages: [msg])
        #expect(count > 0)
    }

    @Test
    func effectiveWindow() {
        let cm = ContextManager()
        let window = cm.effectiveWindow(for: "claude-sonnet-4-6")
        #expect(window == 180_000)
    }

    @Test
    func shouldCompact() {
        let cm = ContextManager(compactionThreshold: 0.8)
        #expect(cm.shouldCompact(currentTokens: 160_000, windowSize: 200_000))
        #expect(!cm.shouldCompact(currentTokens: 100_000, windowSize: 200_000))
    }

    @Test
    func tokensUntilCompaction() {
        let cm = ContextManager(compactionThreshold: 0.85)
        let remaining = cm.tokensUntilCompaction(current: 120_000, window: 200_000)
        #expect(remaining == 50_000)  // 170K threshold - 120K
    }

    @Test
    func microcompact() {
        let cm = ContextManager()
        var messages: [Message] = []
        for i in 1...12 {
            messages.append(Message(type: .user, content: [.text("message \(i)")]))
        }
        let compacted = cm.microcompact(messages: messages, keepFirst: 2, keepLast: 3)
        #expect(compacted.count == 6)  // 2 first + 1 omitted + 3 last
    }

    @Test
    func selectStrategy() {
        let cm = ContextManager()
        #expect(cm.selectStrategy(currentTokens: 100_000, windowSize: 200_000, consecutiveCompactions: 0) == .none)
        #expect(cm.selectStrategy(currentTokens: 150_000, windowSize: 200_000, consecutiveCompactions: 0) == .microcompact)
        #expect(cm.selectStrategy(currentTokens: 180_000, windowSize: 200_000, consecutiveCompactions: 0) == .fullCompact)
        #expect(cm.selectStrategy(currentTokens: 195_000, windowSize: 200_000, consecutiveCompactions: 0) == .blocking)
        #expect(cm.selectStrategy(currentTokens: 120_000, windowSize: 200_000, consecutiveCompactions: 3) == .blocking)
    }
}

struct MessageNormalizerTests {
    @Test
    func normalizeReturnsWhenLastAssistantEndsWithToolUse() {
        let messages = [
            Message(type: .user, content: [.text("Find highlighting references")]),
            Message(type: .assistant, content: [
                .text("I'll search."),
                .toolUse(
                    id: "toolu_1",
                    name: "Glob",
                    input: .object([
                        "pattern": .string("**/*[Hh]ighlight*"),
                        "path": .string("/tmp"),
                    ])
                ),
            ]),
            Message(type: .user, content: [
                .toolResult(toolUseID: "toolu_1", content: .string("No files matched"), isError: false),
            ]),
        ]

        let normalized = normalizeMessagesForAPI(messages, tools: ["Glob"])

        #expect(normalized.count == 3)
        #expect(normalized.last?.type == .user)
    }

    @Test
    func normalizeStripsOnlyTrailingThinkingFromAssistant() {
        let messages = [
            Message(type: .user, content: [.text("Search")]),
            Message(type: .assistant, content: [
                .toolUse(
                    id: "toolu_1",
                    name: "Glob",
                    input: .object(["pattern": .string("**/*.swift")])
                ),
                .thinking("internal scratch", signature: nil),
                .redactedThinking("redacted"),
            ]),
            Message(type: .user, content: [
                .toolResult(toolUseID: "toolu_1", content: .string("Sources/main.swift"), isError: false),
            ]),
        ]

        let normalized = normalizeMessagesForAPI(messages, tools: ["Glob"])
        let assistant = normalized.first { $0.type == .assistant }

        #expect(assistant?.content.count == 1)
        if let block = assistant?.content.first,
           case .toolUse(let id, let name, _) = block {
            #expect(id == "toolu_1")
            #expect(name == "Glob")
        } else {
            Issue.record("Expected trailing thinking to be stripped while preserving tool_use")
        }
    }
}

struct SystemPromptBuilderTests {
    @Test
    func buildsPrompt() {
        let builder = SystemPromptBuilder(workingDirectory: "/test")
        let conversation = Conversation()
        let prompt = builder.build(for: conversation)
        #expect(prompt.contains("SwiftAgent"))
        #expect(prompt.contains("/test"))
        #expect(prompt.contains("__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__"))
        // "Executing actions with care" is the CC-aligned safety section (replaces old "Safety" header)
        #expect(prompt.contains("Executing actions with care"))
    }

    @Test
    func includesConversationSystemPrompt() {
        let builder = SystemPromptBuilder()
        let conversation = Conversation(systemPrompt: "You are the Explore sub-agent.")
        let prompt = builder.build(for: conversation)
        #expect(prompt.contains("You are the Explore sub-agent."))
    }

    @Test
    func defaultStaticContent() {
        let sections = SystemPromptBuilder.defaultStaticContent()
        #expect(sections.count >= 2)
    }
}

struct StreamRendererTests {
    @Test
    func rendersTextDelta() {
        let renderer = StreamRenderer()
        let output = renderer.render(event: .textDelta(text: "hello"), currentOutput: "")
        #expect(output == "hello")
    }

    @Test
    func rendersError() {
        let renderer = StreamRenderer()
        let output = renderer.render(event: .error("boom"), currentOutput: "")
        #expect(output.contains("boom"))
        #expect(output.contains("Error"))
    }

    @Test
    func sanitizeHandlesCRLF() {
        let renderer = StreamRenderer()
        let cleaned = renderer.sanitize("line1\r\nline2")
        #expect(cleaned == "line1\nline2")
    }

    @Test
    func wrapTruncates() {
        let renderer = StreamRenderer()
        let wrapped = renderer.wrap("hello world this is a long text", width: 10)
        #expect(wrapped.count <= 10)
        #expect(wrapped.hasSuffix("..."))
    }

    @Test
    func highlightCodeBlocks() {
        let renderer = StreamRenderer()
        let input = "Some text\n```swift\nlet x = 1\n```\nMore text"
        let output = renderer.highlightCodeBlocks(input)
        #expect(output.contains("let x = 1"))
    }
}

struct ToolExecutorTests {
    @Test
    func executesRegisteredTool() async throws {
        let registry = ToolRegistry()
        // Register a simple mock tool
        struct MockEcho: Tool {
            var name: String { "echo" }
            func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Echoes input" }
            var inputSchema: JSONSchema { JSONSchema(type: "object", properties: [:]) }
            var isReadOnly: Bool { true }
            var isConcurrencySafe: Bool { true }
            func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn?, parentMessage: Message?, onProgress: ToolCallProgress?) async throws -> ToolResult {
                return ToolResult(content: "echo: \(input.description)")
            }
        }
        registry.register(MockEcho())

        let executor = ToolExecutor(registry: registry)
        let result = try await executor.execute(
            name: "echo",
            input: ["message": .string("hi")],
            context: ToolUseContext(workingDirectory: "/tmp", sessionID: "s1")
        )
        #expect(!result.isError)
        #expect(result.content.contains("echo"))
    }

    @Test
    func unknownToolReturnsError() async throws {
        let executor = ToolExecutor(registry: ToolRegistry())
        let result = try await executor.execute(
            name: "nonexistent",
            input: [:],
            context: ToolUseContext(workingDirectory: "/tmp", sessionID: "s1")
        )
        #expect(result.isError)
        #expect(result.content.contains("not found"))
    }
}
