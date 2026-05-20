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
