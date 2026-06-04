import ArgumentParser
import SwiftAgentCore

@main
struct EntryPoint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-agent",
        abstract: "A Swift-native AI coding agent CLI",
        version: "swift-agent \(CoreTypes.version)",
        subcommands: [ChatCommand.self, EvalCommand.self],
        defaultSubcommand: nil
    )

    func run() throws {
        print("SwiftAgent v\(CoreTypes.version) — Swift-native AI coding agent")
        print("Run 'swift-agent --help' for available commands.")
        print("Run 'swift-agent chat' to start an interactive session.")
    }
}
