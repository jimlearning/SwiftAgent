import Foundation
import XCTest
@testable import SwiftAgentCore

// MARK: - AgentPermissionBridgeTests

final class AgentPermissionBridgeTests: XCTestCase {

    // MARK: - Test 1: runCommands maps to Bash tool check

    func testRunCommandsMapsToBash() async throws {
        let engine = makePermissionEngine(allowTools: ["Bash"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.runCommands)
        XCTAssertTrue(result, "runCommands should be allowed when Bash is allowed")
    }

    func testRunCommandsDeniedWhenBashDenied() async throws {
        let engine = makePermissionEngine(denyTools: ["Bash"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.runCommands)
        XCTAssertFalse(result, "runCommands should be denied when Bash is denied")
    }

    // MARK: - Test 2: readFiles maps to Read tool check

    func testReadFilesMapsToRead() async throws {
        let engine = makePermissionEngine(allowTools: ["Read"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.readFiles(paths: ["/tmp"]))
        XCTAssertTrue(result, "readFiles should be allowed when Read is allowed")
    }

    func testReadFilesDeniedWhenReadDenied() async throws {
        let engine = makePermissionEngine(denyTools: ["Read"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.readFiles(paths: ["/tmp"]))
        XCTAssertFalse(result, "readFiles should be denied when Read is denied")
    }

    // MARK: - Test 3: writeFiles maps to Write tool check

    func testWriteFilesMapsToWrite() async throws {
        let engine = makePermissionEngine(allowTools: ["Write"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.writeFiles(paths: ["/tmp"]))
        XCTAssertTrue(result, "writeFiles should be allowed when Write is allowed")
    }

    func testWriteFilesDeniedWhenWriteDenied() async throws {
        let engine = makePermissionEngine(denyTools: ["Write"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.writeFiles(paths: ["/tmp"]))
        XCTAssertFalse(result, "writeFiles should be denied when Write is denied")
    }

    // MARK: - Test 4: .all returns true unconditionally

    func testAllReturnsTrueUnconditionally() async throws {
        // Even with everything denied, .all returns true
        let engine = makePermissionEngine(denyTools: ["Bash", "Read", "Write", "WebFetch"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.all)
        XCTAssertTrue(result, ".all should return true unconditionally")
    }

    // MARK: - Test 5: .default respects mode

    func testDefaultReturnsTrueInDefaultMode() async throws {
        let engine = makePermissionEngine()
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.default)
        XCTAssertTrue(result, ".default should return true when mode is .default")
    }

    func testDefaultReturnsFalseInOtherMode() async throws {
        let engine = makePermissionEngine()
        let bridge = AgentPermissionBridge(engine: engine, mode: .plan)

        let result = try await bridge.check(.default)
        XCTAssertFalse(result, ".default should return false when mode is not .default")
    }

    // MARK: - Test 6: .plan respects mode

    func testPlanReturnsTrueInPlanMode() async throws {
        let engine = makePermissionEngine()
        let bridge = AgentPermissionBridge(engine: engine, mode: .plan)

        let result = try await bridge.check(.plan)
        XCTAssertTrue(result, ".plan should return true when mode is .plan")
    }

    func testPlanReturnsFalseInOtherMode() async throws {
        let engine = makePermissionEngine()
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.plan)
        XCTAssertFalse(result, ".plan should return false when mode is not .plan")
    }

    // MARK: - Test 7: Unestablished permissions default to ask (not deny)

    func testContactsNotDeniedByDefault() async throws {
        let engine = makePermissionEngine(allowTools: ["Bash", "Read", "Write"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.contacts)
        XCTAssertTrue(result, ".contacts should not be denied by default (defaults to ask)")
    }

    // MARK: - Test 8: All unestablished permissions default to ask (not deny)

    func testAllUnestablishedPermissionsNotDeniedByDefault() async throws {
        let engine = makePermissionEngine()
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let permissions: [AgentPermission] = [
            .contacts, .calendar, .location, .camera, .microphone, .delete
        ]

        for permission in permissions {
            let result = try await bridge.check(permission)
            XCTAssertTrue(result, "\(permission) should not be denied by default (defaults to ask)")
        }
    }

    // MARK: - Test 9: network maps to WebFetch tool check

    func testNetworkMapsToWebFetch() async throws {
        let engine = makePermissionEngine(allowTools: ["WebFetch"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.network(domains: ["api.example.com"]))
        XCTAssertTrue(result, "network should be allowed when WebFetch is allowed")
    }

    func testNetworkDeniedWhenWebFetchDenied() async throws {
        let engine = makePermissionEngine(denyTools: ["WebFetch"])
        let bridge = AgentPermissionBridge(engine: engine, mode: .default)

        let result = try await bridge.check(.network(domains: ["api.example.com"]))
        XCTAssertFalse(result, "network should be denied when WebFetch is denied")
    }

    // MARK: - Test 10: LanguageModelSessionImpl integration with SQLiteMemoryStore

    func testLanguageModelSessionIntegrationWithSQLiteMemoryStore() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_integration_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let memoryStore = try SQLiteMemoryStore(location: dbPath.path)
        let mockModel = MockLanguageModel(
            cannedResponses: ["Integration test response"]
        )
        let permissionEngine = MockPermissionEngine(shouldAllow: true)
        // Wrap in AgentPermissionBridge
        let bridge = AgentPermissionBridge(
            engine: PermissionEngine(),  // Use real PermissionEngine
            mode: .default
        )
        let toolEngine = DefaultToolEngine()

        let runtime = LanguageModelSessionImpl(
            modelProvider: mockModel,
            memoryStore: memoryStore,
            permissionEngine: bridge,
            toolEngine: toolEngine
        )

        let response = try await runtime.respond(to: "Hello integration test")
        let transcript = response.transcript

        XCTAssertFalse(transcript.entries.isEmpty, "Transcript should have entries")
        XCTAssertTrue(
            transcript.entries.contains(where: {
                if case .response(let text) = $0, text.contains("Integration test response") {
                    return true
                }
                return false
            }),
            "Transcript should contain the mock response"
        )

        // Verify transcript was stored in memory
        let stored: Transcript? = try await memoryStore.retrieve(key: "latest", namespace: "sessions")
        XCTAssertNotNil(stored, "Transcript should be stored in memory after respond(to:)")
    }

    // MARK: - Helpers

    /// Create a PermissionEngine with allow rules for the specified tool names.
    private func makePermissionEngine(allowTools: [String] = []) -> PermissionEngine {
        var store = PermissionStore()
        for toolName in allowTools {
            store.addRule(PermissionRule(
                source: .userSettings,
                ruleBehavior: .allow,
                ruleValue: PermissionRuleValue(toolName: toolName)
            ))
        }
        return PermissionEngine(store: store)
    }

    /// Create a PermissionEngine with deny rules for the specified tool names.
    private func makePermissionEngine(denyTools: [String]) -> PermissionEngine {
        var store = PermissionStore()
        for toolName in denyTools {
            store.addRule(PermissionRule(
                source: .userSettings,
                ruleBehavior: .deny,
                ruleValue: PermissionRuleValue(toolName: toolName)
            ))
        }
        return PermissionEngine(store: store)
    }
}
