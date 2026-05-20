import Foundation
import ArgumentParser
import SwiftAgentCore

/// Interactive chat command — the primary interaction mode.
struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive AI coding session"
    )

    @Option(name: .long, help: "Model to use (or ANTHROPIC_MODEL env var)")
    var model: String = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"] ?? "deepseek-v4-pro"

    @Option(name: .long, help: "Permission mode: default, plan, acceptEdits, bypass")
    var permission: String = "default"

    @Option(name: .long, help: "API Key (or ANTHROPIC_API_KEY, keychain, ~/.claude.json)")
    var apiKey: String?

    @Flag(name: .long, help: "Disable colors")
    var noColor: Bool = false

    func run() async throws {
        // Resolve API key: --api-key flag > env var > keychain > ~/.claude.json
        let resolver = APIKeyResolver()
        let key = apiKey ?? resolver.resolve() ?? ""
        if key.isEmpty {
            print("Error: API key not found. SwiftAgent checks the same sources as Claude Code:")
            print("  - ANTHROPIC_API_KEY env var")
            print("  - ANTHROPIC_AUTH_TOKEN env var")
            print("  - macOS keychain (Claude Code)")
            print("  - ~/.claude.json (primaryApiKey)")
            print("Or use --api-key to pass it directly.")
            throw ExitCode.failure
        }

        let baseURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.deepseek.com/anthropic"

        let capability = TerminalCapability()
        let theme: ColorTheme = noColor ? .monochrome : .default
        let renderer = TerminalRenderer(capability: capability, theme: theme)
        let streamRenderer = StreamRenderer()

        print(renderer.renderBanner(version: "0.1.0"))
        print("Type /help for commands, /exit to quit.\n")

        // Set up engine
        let client = LLMClient(apiKey: key, baseURL: baseURL, model: model)
        let registry = ToolRegistry()
        registerBuiltinTools(into: registry)

        let state = AppState()
        _ = AppStateStore(state: state)

        // REPL
        while true {
            let prompt = "swift-agent › "

            print(prompt, terminator: "")
            fflush(stdout)

            guard let line = readLine() else { break }

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }

            // Handle slash commands via CommandRegistry
            if input.hasPrefix("/") {
                if await handleCommand(input) { break }
                continue
            }

            print()

            do {
                let stream = client.send(
                    messages: [Message(type: .user, content: [.text(input)])],
                    model: model,
                    maxTokens: 4096
                )

                for try await event in stream {
                    let output = streamRenderer.render(event: event, currentOutput: "")
                    let sanitized = output.replacingOccurrences(of: "\r\n", with: "\n")
                    if !sanitized.isEmpty {
                        print(sanitized, terminator: "")
                        fflush(stdout)
                    }
                }

                print("\n")
            } catch {
                print("\nError: \(error.localizedDescription)\n")
            }
        }

        print("\nGoodbye!")
    }

    private func handleCommand(_ input: String) async -> Bool {
        let registry = CommandRegistry()
        switch await registry.execute(input: input) {
        case .exit:
            return true
        case .text(let output):
            print(output)
        case .error(let msg):
            print("Error: \(msg)")
        case .none:
            print("Unknown command: \(input). Type /help for available commands.")
        }
        return false
    }

    private func registerBuiltinTools(into registry: ToolRegistry) {
        let taskManager = TaskManager()

        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileEditTool())
        registry.register(BashTool())
        registry.register(GlobTool())
        registry.register(GrepTool())
        registry.register(WebFetchTool())
        registry.register(WebSearchTool())
        registry.register(TodoWriteTool())
        registry.register(NotebookEditTool())
        registry.register(ConfigTool())
        registry.register(EnterWorktreeTool())
        registry.register(ExitWorktreeTool())
        registry.register(MCPTool())
        registry.register(McpAuthTool())
        registry.register(ListMcpResourcesTool())
        registry.register(ReadMcpResourceTool())
        registry.register(BriefTool())
        // Task management (shared TaskManager)
        registry.register(TaskCreateTool(taskManager: taskManager))
        registry.register(TaskGetTool(taskManager: taskManager))
        registry.register(TaskListTool(taskManager: taskManager))
        registry.register(TaskOutputTool(taskManager: taskManager))
        registry.register(TaskUpdateTool(taskManager: taskManager))
        registry.register(TaskStopTool(taskManager: taskManager))
        // Agent delegation
        registry.register(AgentTool())
        registry.register(SkillTool())
        registry.register(SendMessageTool())
        registry.register(AskUserQuestionTool())
        // Code intelligence
        registry.register(LSPTool())
        // Utility tools
        registry.register(EnterPlanModeTool())
        registry.register(ExitPlanModeV2Tool())
        // Scheduled cron
        registry.register(CronCreateTool())
        registry.register(CronDeleteTool())
        registry.register(CronListTool())
        // Platform-specific tools
        registry.register(PowerShellTool())
        // REPL mode is a concept (REPLMode.swift), not a callable tool.
        // registry.register(REPLTool())
        // Deferred tool search
        registry.register(ToolSearchTool(toolRegistry: registry))
        // Sleep / pause
        registry.register(SleepTool())
        // Missing stubs (synthetic output, remote trigger, team)
        registry.register(SyntheticOutputTool())
        registry.register(RemoteTriggerTool())
        registry.register(TeamCreateTool())
        registry.register(TeamDeleteTool())
    }
}
