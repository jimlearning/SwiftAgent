import Testing
import Foundation
@testable import SwiftAgentCore

struct PermissionEngineTests {
    @Test
    func bypassModeAllowsEverything() async {
        let engine = PermissionEngine()
        let result = await engine.check(
            toolName: "Bash",
            input: ["command": .string("rm -rf /")],
            mode: .bypassPermissions,
            context: testCtx
        )
        // Safety check should still block
        #expect(result.decision == .deny)
    }

    @Test
    func bypassModeAllowsSafe() async {
        let engine = PermissionEngine()
        let result = await engine.check(
            toolName: "Read",
            input: ["file_path": .string("/tmp/test.txt")],
            mode: .bypassPermissions,
            context: testCtx
        )
        #expect(result.decision == .allow)
    }

    @Test
    func planModeAsksForEdit() async {
        let engine = PermissionEngine()
        let result = await engine.check(
            toolName: "Write",
            input: ["file_path": .string("/tmp/test.txt"), "content": .string("x")],
            mode: .plan,
            context: testCtx
        )
        #expect(result.decision == .ask)
    }

    @Test
    func acceptEditsAllowsReads() async {
        let engine = PermissionEngine()
        let result = await engine.check(
            toolName: "Read",
            input: ["file_path": .string("/tmp/test.txt")],
            mode: .acceptEdits,
            context: testCtx
        )
        #expect(result.decision == .allow)
    }

    @Test
    func defaultModeAllowsSafeTools() async {
        let engine = PermissionEngine()
        let result = await engine.check(
            toolName: "Read",
            input: ["file_path": .string("/tmp/test.txt")],
            mode: .default,
            context: testCtx
        )
        #expect(result.decision == .allow)
    }
}

struct PermissionStoreTests {
    @Test
    func rulesForToolExactMatch() {
        var store = PermissionStore()
        store.addRule(PermissionRule(ruleBehavior: .deny, ruleValue: PermissionRuleValue(toolName: "Bash")))
        store.addRule(PermissionRule(ruleBehavior: .allow, ruleValue: PermissionRuleValue(toolName: "Read")))

        let rules = store.rules(for: "Bash", context: testCtx)
        #expect(rules.count == 1)
        #expect(rules[0].ruleBehavior == PermissionBehavior.deny)
    }

    @Test
    func aggregateDenyWins() {
        let result = PermissionStore.aggregate([.allow, .ask, .deny])
        #expect(result == .deny)
    }

    @Test
    func aggregateAskOverAllow() {
        let result = PermissionStore.aggregate([.allow, .ask])
        #expect(result == .ask)
    }

    @Test
    func aggregateAllAllow() {
        let result = PermissionStore.aggregate([.allow, .allow])
        #expect(result == .allow)
    }
}

struct SafetyCheckerTests {
    @Test
    func detectsForkBomb() {
        let checker = SafetyChecker()
        let reason = checker.check(toolName: "Bash", input: ["command": .string(":(){ :|:& };:")])
        #expect(reason != nil)
    }

    @Test
    func blocksRmRoot() {
        let checker = SafetyChecker()
        let reason = checker.check(toolName: "Bash", input: ["command": .string("sudo rm -rf /")])
        #expect(reason != nil)
    }

    @Test
    func allowsSafeBashCommand() {
        let checker = SafetyChecker()
        let reason = checker.check(toolName: "Bash", input: ["command": .string("ls -la")])
        #expect(reason == nil)
    }

    @Test
    func blocksSystemDirectoryWrite() {
        let checker = SafetyChecker()
        let reason = checker.check(toolName: "Write", input: [
            "file_path": .string("/etc/config.txt"),
            "content": .string("x")
        ])
        #expect(reason != nil)
    }
}
