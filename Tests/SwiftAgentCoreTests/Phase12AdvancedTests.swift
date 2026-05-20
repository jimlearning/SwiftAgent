import Testing
import Foundation
@testable import SwiftAgentCore

// MARK: - HookSystem Tests

struct HookSystemTests {
    @Test
    func registersHook() async {
        let system = HookSystem()
        let hook = HookEntry(event: .sessionStart, command: "echo hello")
        await system.register(hook)
        let all = await system.listAll()
        #expect(all.count == 1)
    }

    @Test
    func removesHook() async {
        let system = HookSystem()
        let hook = HookEntry(event: .sessionStart, command: "echo hello")
        await system.register(hook)
        await system.remove(id: hook.id)
        let all = await system.listAll()
        #expect(all.isEmpty)
    }

    @Test
    func disablesHook() async {
        let system = HookSystem()
        let hook = HookEntry(event: .sessionStart, command: "echo hello")
        await system.register(hook)
        await system.disable(id: hook.id)
        let all = await system.listAll()
        #expect(all.first?.enabled == false)
    }

    @Test
    func listsByEvent() async {
        let system = HookSystem()
        await system.register(HookEntry(event: .sessionStart, command: "echo start"))
        await system.register(HookEntry(event: .sessionEnd, command: "echo end"))
        let startHooks = await system.list(for: .sessionStart)
        #expect(startHooks.count == 1)
    }

    @Test
    func registersFromHookConfig() async {
        let system = HookSystem()
        let config = HookConfig(id: "h1", event: .preToolUse, command: "echo tool-use")
        await system.register(from: config)
        let all = await system.listAll()
        #expect(all.first?.command == "echo tool-use")
    }

    @Test
    func dispatchesToMatchingEvent() async {
        let system = HookSystem()
        await system.register(HookEntry(event: .sessionStart, command: "echo hello"))
        let result = await system.dispatch(event: .sessionEnd, input: "")
        // sessionEnd hook NOT registered, so should continue
        switch result {
        case .continue: break // expected
        default: #expect(Bool(false), "Expected .continue")
        }
    }
}

// MARK: - PluginManager Tests

struct PluginManagerTests {
    @Test
    func validatesValidManifest() {
        let manifest = PluginManifest(name: "test", version: "1.0.0")
        let issues = PluginManager.validate(manifest)
        #expect(issues.isEmpty)
    }

    @Test
    func validatesEmptyName() {
        let manifest = PluginManifest(name: "")
        let issues = PluginManager.validate(manifest)
        #expect(issues.contains { $0.contains("name") })
    }

    @Test
    func validatesNameWithSpaces() {
        let manifest = PluginManifest(name: "test plugin")
        let issues = PluginManager.validate(manifest)
        #expect(issues.contains { $0.contains("spaces") })
    }

    @Test
    func unloadsPlugin() async {
        let manager = PluginManager()
        // Plugin not loaded, unload should be no-op
        await manager.unload(name: "nonexistent")
        let all = await manager.listAll()
        #expect(all.isEmpty)
    }
}

// MARK: - FeatureFlags Tests

struct FeatureFlagsTests {
    @Test
    func defaultsHasExpectedFlags() {
        let flags = FeatureFlags.defaults
        #expect(flags.isEnabled("mcp") == true)
        #expect(flags.isEnabled("telemetry") == false)
    }

    @Test
    func setsAndGetsStringFlag() {
        var flags = FeatureFlags()
        flags.set("theme", value: .string("dark"))
        #expect(flags.stringValue("theme") == "dark")
    }

    @Test
    func unknownFlagReturnsFalse() {
        let flags = FeatureFlags()
        #expect(!flags.isEnabled("nonexistent"))
    }

    @Test
    func mergesOverwritesExisting() {
        var a = FeatureFlags(flags: ["x": .boolean(true)])
        let b = FeatureFlags(flags: ["x": .boolean(false)])
        a.merge(b)
        #expect(!a.isEnabled("x"))
    }
}
