import XCTest
@testable import SwiftAgentCore

// MARK: - Test Helper Types

/// Simple Codable struct for PartiallyGenerated tests.
private struct StringWrapper: Codable, Sendable {
    var value: String = ""
}

/// Simple Codable struct for diff tests.
private struct TestParams: Codable, Sendable, Equatable {
    var command: String = ""
    var timeout: Int = 0
}

/// BashParams for GenerationSchema testing.
/// Conforms to DefaultInitializable (via default property values)
/// so that generationSchemaFromMirror can create a sample instance.
private struct BashParams: Codable, Sendable, GenerationSchema {
    var command: String = ""
    var description: String? = nil
}

extension BashParams: DefaultInitializable {}

// MARK: - Phase2StreamingTests

final class Phase2StreamingTests: XCTestCase {

    // MARK: - SessionEvent Tests

    func testSessionEventHasAllSixCases() {
        // Create one instance of each case. If any case is missing, this won't compile.
        let events: [SessionEvent] = [
            .textDelta("hello"),
            .thinkingDelta("reasoning..."),
            .toolCallRequested(id: "toolu_01", name: "Bash", input: Data("{}".utf8)),
            .toolCallCompleted(id: "toolu_01", output: .string("result"), isError: false),
            .turnCompleted(usage: nil, stopReason: "end_turn"),
            .error(.toolNotFound(name: "FakeTool"))
        ]
        XCTAssertEqual(events.count, 6, "SessionEvent must have exactly 6 cases")
    }

    // MARK: - PartiallyGenerated Tests

    func testPartiallyGeneratedInitialState() {
        let pg = PartiallyGenerated<StringWrapper>()
        XCTAssertNil(pg.snapshot)
        XCTAssertNil(pg.previousSnapshot)
        XCTAssertTrue(pg.changedKeys.isEmpty)
        XCTAssertFalse(pg.isComplete)
        XCTAssertEqual(pg.rawAccumulatedText, "")
    }

    func testPartiallyGeneratedDiff() {
        let old = TestParams(command: "ls", timeout: 0)
        let new = TestParams(command: "ls", timeout: 30)

        let changed = diffSnapshots(old, new)
        XCTAssertEqual(changed, ["timeout"], "Changed keys should contain 'timeout' but not 'command'")

        // Test no changes
        let same = diffSnapshots(old, old)
        XCTAssertTrue(same.isEmpty, "Diff of identical snapshots should be empty")
    }

    // MARK: - GenerationSchema Tests

    func testGenerationSchemaForBashParams() {
        let schema = BashParams.jsonSchema

        XCTAssertEqual(schema.type, "object")
        XCTAssertNotNil(schema.properties, "Schema should have properties")
        guard let props = schema.properties else {
            XCTFail("Missing properties")
            return
        }

        // command: String (non-optional) → type "string"
        XCTAssertNotNil(props["command"], "Should have 'command' property")
        if let cmdProp = props["command"] {
            XCTAssertEqual(cmdProp.type, "string")
        }

        // description: String? (optional) → type "string"
        XCTAssertNotNil(props["description"], "Should have 'description' property")
        if let descProp = props["description"] {
            XCTAssertEqual(descProp.type, "string")
        }

        // command is required (non-optional), description is NOT required (optional)
        XCTAssertNotNil(schema.required, "Schema should have required array")
        if let required = schema.required {
            XCTAssertTrue(required.contains("command"), "command should be in required array")
            XCTAssertFalse(required.contains("description"), "description (optional) should NOT be in required array")
        }
    }

    // MARK: - RuntimeGenerationChannel Tests

    func testRuntimeGenerationChannelFinishGating() async throws {
        let channel = RuntimeGenerationChannel()
        let (stream, continuation) = AsyncThrowingStream<SessionEvent, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        await channel.setContinuation(continuation)

        // Complete the turn — this sets isFinished=true and finishes the continuation
        await channel.complete(stopReason: "end_turn", usage: nil)

        // This send should be silently dropped by the isFinished guard
        await channel.send(textDelta: "This should be dropped")

        // Collect events from the stream after all sends are done
        var events: [SessionEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // Only turnCompleted should be received — the post-complete textDelta is dropped
        XCTAssertEqual(events.count, 1, "Only turnCompleted should be received; post-complete send must be dropped")
        if case .turnCompleted(let usage, let stopReason) = events[0] {
            XCTAssertNil(usage)
            XCTAssertEqual(stopReason, "end_turn")
        } else {
            XCTFail("Expected turnCompleted event as the only event")
        }
    }

    func testRuntimeGenerationChannelTextSnapshot() async throws {
        let channel = RuntimeGenerationChannel()
        let (stream, continuation) = AsyncThrowingStream<SessionEvent, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        await channel.setContinuation(continuation)

        // Send two textDeltas — each is a SNAPSHOT (accumulated total), not an incremental delta
        await channel.send(textDelta: "Hello")
        await channel.send(textDelta: "Hello world")
        await channel.complete(stopReason: "end_turn", usage: nil)

        // Collect events from the stream after all sends are done
        var events: [SessionEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3, "Expected 3 events: 2 textDeltas + 1 turnCompleted")

        // Verify snapshot (replacement) semantics:
        // The second textDelta carries the COMPLETE accumulated text, not a delta
        if case .textDelta(let text) = events[0] {
            XCTAssertEqual(text, "Hello", "First textDelta should be 'Hello'")
        } else {
            XCTFail("Expected first event to be textDelta")
        }

        if case .textDelta(let text) = events[1] {
            XCTAssertEqual(text, "Hello world", "Second textDelta should be 'Hello world' (snapshot), not 'HelloHello world' (delta)")
        } else {
            XCTFail("Expected second event to be textDelta")
        }

        if case .turnCompleted = events[2] {
            // Expected
        } else {
            XCTFail("Expected third event to be turnCompleted")
        }
    }
}
