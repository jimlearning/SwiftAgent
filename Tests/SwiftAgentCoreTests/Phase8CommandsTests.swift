import Testing
import Foundation
@testable import SwiftAgentCore

struct CommandRegistryTests {
    @Test
    func registersCommand() {
        let registry = CommandRegistry()
        let cmd = Command(name: "test-cmd", description: "A test command", type: .local)
        registry.register(cmd)
        #expect(registry.find("test-cmd") != nil)
    }

    @Test
    func findReturnsNilForUnknown() {
        let registry = CommandRegistry()
        #expect(registry.find("nonexistent") == nil)
    }

    @Test
    func matchParsesSlashInput() {
        let registry = CommandRegistry()
        let cmd = registry.match(input: "/help")
        #expect(cmd?.command.name == "help")
    }

    @Test
    func matchReturnsNilForNonSlash() {
        let registry = CommandRegistry()
        #expect(registry.match(input: "hello") == nil)
    }

    @Test
    func matchHandlesTrailingArguments() {
        let registry = CommandRegistry()
        let cmd = registry.match(input: "/model claude-sonnet-4-6")
        #expect(cmd?.command.name == "model")
    }

    @Test
    func allCommandsReturnsSorted() {
        let registry = CommandRegistry()
        let all = registry.allCommands
        #expect(all.count >= 7)
        let names = all.map(\.name)
        #expect(names == names.sorted())
    }

    @Test
    func builtinHelpExists() {
        let registry = CommandRegistry()
        let help = registry.find("help")
        #expect(help != nil)
        #expect(help?.description.contains("available commands") == true)
    }

    @Test
    func builtinModelHasArguments() {
        let registry = CommandRegistry()
        let model = registry.find("model")
        #expect(model != nil)
        #expect(model?.arguments.isEmpty == false)
        #expect(model?.arguments.first?.name == "model-id")
    }
}
