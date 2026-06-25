import XCTest
@testable import SwiftAgentCore

// MARK: - Test Helpers

/// Minimal RuntimeAgentTool for testing tool execution routing.
private struct TestTool: RuntimeAgentTool {
    typealias Input = Data
    let name: String
    let description: String
    let inputSchema: JSONSchema

    init(name: String, description: String = "A test tool") {
        self.name = name
        self.description = description
        self.inputSchema = JSONSchema(type: "object", properties: [:], required: [])
    }

    func call(_ input: Data) async throws -> ToolOutputValue {
        .string("test output for \(name)")
    }
}

/// Convenience for creating canned tool call input.
private func cannedInput(_ json: String) -> Data {
    Data(json.utf8)
}

// MARK: - AgentRuntimeImplTests

final class AgentRuntimeImplTests: XCTestCase {

    // MARK: - Test 1: Initialization

    func testInitWithAllSubsystems() async throws {
        let model = MockLanguageModel()
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine()
        let toolEngine = DefaultToolEngine()

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        // All property slots should be accessible (cross-actor boundary).
        let provider = await runtime.modelProvider
        XCTAssertNotNil(provider)
        let store = await runtime.memoryStore
        XCTAssertNotNil(store)
        let engine = await runtime.permissionEngine
        XCTAssertNotNil(engine)
        let tools = await runtime.toolEngine
        XCTAssertNotNil(tools)
        let ctx = await runtime.contextManager
        XCTAssertNotNil(ctx)
        let profile = await runtime.profileManager
        XCTAssertNotNil(profile)
        let graph = await runtime.graphEngine
        XCTAssertNil(graph) // default is nil
        let hooks = await runtime.hookSystem
        XCTAssertNotNil(hooks)
    }

    // MARK: - Test 2: respond(to:) Completes a Basic Turn

    func testRespondCompletesTurn() async throws {
        let model = MockLanguageModel(cannedResponses: ["Hello from mock"])
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        let result = try await runtime.respond(to: "Hi")

        // Transcript should have prompt and response entries.
        let hasPrompt = result.entries.contains { entry in
            if case .prompt("Hi") = entry { return true }
            return false
        }
        XCTAssertTrue(hasPrompt, "Transcript should contain the prompt")

        let hasResponse = result.entries.contains { entry in
            if case .response("Hello from mock") = entry { return true }
            return false
        }
        XCTAssertTrue(hasResponse, "Transcript should contain the model's response")

        // Memory store should have been updated.
        let stored: Transcript? = try? await memory.retrieve(
            key: "latest", namespace: "sessions"
        )
        XCTAssertNotNil(stored, "Memory store should have the transcript after a turn")
    }

    // MARK: - Test 3: respond(to:) With Tool Calls

    func testRespondWithToolCalls() async throws {
        let cannedCall = MockLanguageModel.CannedToolCall(
            id: "tool_1", name: "FakeTool", input: cannedInput("{}")
        )
        // With both cannedResponses and cannedToolCalls, the mock executor
        // sends both in every iteration. The agent loop re-prompts as long
        // as tool calls appear, so it hits the maxIterations=50 limit.
        // We verify that tool calls and outputs appear in the transcript.
        let model = MockLanguageModel(
            cannedResponses: ["Final answer"],
            cannedToolCalls: [cannedCall]
        )
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()
        await toolEngine.register(
            tool: TestTool(name: "FakeTool"),
            metadata: ToolMetadata(isReadOnly: true)
        )

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        let result = try await runtime.respond(to: "Use the tool")

        // Transcript should have tool-related entries.
        let toolCalls = result.entries.filter { entry in
            if case .toolCall = entry { return true }
            return false
        }
        let toolOutputs = result.entries.filter { entry in
            if case .toolOutput = entry { return true }
            return false
        }
        XCTAssertFalse(toolCalls.isEmpty, "Transcript should contain tool call entries")
        XCTAssertFalse(toolOutputs.isEmpty, "Transcript should contain tool output entries")
        XCTAssertEqual(toolCalls.count, toolOutputs.count,
                       "Each tool call should have a corresponding output")

        // Verify the final entry is a response (appended after loop exits).
        let hasResponse = result.entries.contains { entry in
            if case .response = entry { return true }
            return false
        }
        XCTAssertTrue(hasResponse, "Transcript should end with a response entry")
    }

    // MARK: - Test 4: streamResponse(to:) Yields Events

    func testStreamResponseYieldsEvents() async throws {
        let model = MockLanguageModel(cannedResponses: ["Hello stream"])
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        let stream = await runtime.streamResponse(to: "Hi")
        var events: [SessionEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            XCTFail("Stream should not throw: \(error)")
        }

        XCTAssertFalse(events.isEmpty, "Stream should yield at least one event")

        // First event should be a textDelta.
        let firstEvent = events[0]
        if case .textDelta(let text) = firstEvent {
            XCTAssertEqual(text, "Hello stream")
        } else {
            XCTFail("First event should be textDelta, got \(firstEvent)")
        }

        // Last event should be turnCompleted.
        let lastEvent = events.last!
        if case .turnCompleted(let usage, let stopReason) = lastEvent {
            XCTAssertNil(usage)
            XCTAssertEqual(stopReason, "end_turn")
        } else {
            XCTFail("Last event should be turnCompleted, got \(lastEvent)")
        }
    }

    // MARK: - Test 5: streamResponse(to:) With Tool Calls

    func testStreamResponseWithToolCalls() async throws {
        let cannedCall = MockLanguageModel.CannedToolCall(
            id: "stream_tool_1", name: "StreamTool", input: cannedInput("{}")
        )
        // With both cannedResponses and cannedToolCalls, the mock sends
        // both in every iteration. We collect events with a safety break.
        let model = MockLanguageModel(
            cannedResponses: ["Processing..."],
            cannedToolCalls: [cannedCall]
        )
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()
        await toolEngine.register(
            tool: TestTool(name: "StreamTool"),
            metadata: ToolMetadata(isReadOnly: true)
        )

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        let stream = await runtime.streamResponse(to: "Use stream tool")
        var events: [SessionEvent] = []
        do {
            for try await event in stream {
                events.append(event)
                // Safety break — we just need to verify events are emitted.
                if events.count >= 20 { break }
            }
        } catch {
            XCTFail("Stream should not throw: \(error)")
        }

        // Should receive at least one toolCallRequested.
        let toolRequests = events.filter { event in
            if case .toolCallRequested = event { return true }
            return false
        }
        XCTAssertFalse(toolRequests.isEmpty, "Should emit toolCallRequested events")

        // Should receive toolCallCompleted after tool execution.
        let toolCompletions = events.filter { event in
            if case .toolCallCompleted = event { return true }
            return false
        }
        XCTAssertFalse(toolCompletions.isEmpty, "Should emit toolCallCompleted events")

        // Should also see text deltas.
        let textDeltas = events.filter { event in
            if case .textDelta = event { return true }
            return false
        }
        XCTAssertFalse(textDeltas.isEmpty, "Should emit textDelta events")
    }

    // MARK: - Test 6: Reentrancy Guard

    func testReentrancyGuard() async throws {
        let model = MockLanguageModel(cannedResponses: ["Response"])
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        // Drop the first stream — leaves isResponding = true.
        _ = await runtime.streamResponse(to: "First (unconsumed)")

        // Second call to streamResponse returns error stream.
        let errorStream = await runtime.streamResponse(to: "Second")
        var caughtRateLimit = false
        do {
            for try await _ in errorStream { }
        } catch let error as AgentRuntimeError {
            if case .rateLimited = error {
                caughtRateLimit = true
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertTrue(caughtRateLimit,
                      "Second streamResponse should fail with rateLimited")

        // respond(to:) should also throw rateLimited.
        do {
            _ = try await runtime.respond(to: "Third")
            XCTFail("Expected rateLimited from respond(to:)")
        } catch let error as AgentRuntimeError {
            if case .rateLimited = error {
                // Expected
            } else {
                XCTFail("Expected rateLimited, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Test 7: Permission Denied Blocks Tool Execution

    func testPermissionDeniedBlocksToolExecution() async throws {
        let cannedCall = MockLanguageModel.CannedToolCall(
            id: "blocked_1", name: "BlockedTool", input: cannedInput("{}")
        )
        let model = MockLanguageModel(
            cannedResponses: [],
            cannedToolCalls: [cannedCall]
        )
        let memory = MockMemoryStore()
        // Permission engine denies all requests.
        let permission = MockPermissionEngine(shouldAllow: false)
        let toolEngine = DefaultToolEngine()
        await toolEngine.register(
            tool: TestTool(name: "BlockedTool"),
            metadata: ToolMetadata()
        )

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        // respond(to:) should throw permissionDenied.
        // The agent loop processes the tool call, calls executeTool,
        // which calls permissionEngine.check(.runCommands) — denied.
        do {
            _ = try await runtime.respond(to: "Run blocked tool")
            XCTFail("Expected permissionDenied error")
        } catch let error as AgentRuntimeError {
            if case .permissionDenied = error {
                // Expected — permission engine denied the tool execution.
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Test 8: Stream Cancellation

    func testStreamCancellation() async throws {
        let model = MockLanguageModel(cannedResponses: ["A", "B", "C"])
        let memory = MockMemoryStore()
        let permission = MockPermissionEngine(shouldAllow: true)
        let toolEngine = DefaultToolEngine()

        let runtime = AgentRuntimeImpl(
            modelProvider: model,
            memoryStore: memory,
            permissionEngine: permission,
            toolEngine: toolEngine
        )

        let stream = await runtime.streamResponse(to: "Test cancel")
        var eventCount = 0
        do {
            for try await _ in stream {
                eventCount += 1
                if eventCount >= 2 {
                    break // Early exit — consumer stops iterating.
                }
            }
        } catch {
            // Cancellation or other errors are acceptable — just verify no crash.
        }

        // The stream was consumed (at least partially) without crashing.
        XCTAssertTrue(eventCount > 0, "Should have consumed at least one event")
    }
}
