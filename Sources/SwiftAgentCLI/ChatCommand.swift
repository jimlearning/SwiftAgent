import Foundation
import ArgumentParser
import SwiftAgentCore

/// Interactive chat command — the primary interaction mode.
/// Uses a Nanobot-style REPL: colored prompt, spinner while thinking,
/// write-once response panel, readline history.
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

    @Flag(name: .long, help: "Disable markdown rendering in responses")
    var noMarkdown: Bool = false

    func run() async throws {
        // Resolve API key
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
        print("\nType [bold]/help[/] for commands, [bold]/exit[/] to quit.\n")

        // Set up engine
        let client = LLMClient(apiKey: key, baseURL: baseURL, model: model)
        let registry = ToolRegistry()
        registerBuiltinTools(into: registry)

        let state = AppState()
        _ = AppStateStore(state: state)

        let editor = LineEditor()

        // Nanobot-style REPL
        while true {
            // Drain any keystrokes typed while the model was generating
            renderer.drainTTYInput()

            guard let line = editor.readLine(prompt: "swift-agent › ") else { break }
            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }

            // Handle slash commands
            if input.hasPrefix("/") {
                let parts = input.split(separator: " ", maxSplits: 1)
                let cmd = String(parts[0])
                if cmd == "/exit" || cmd == "/quit" { break }
                if cmd == "/clear" {
                    print(renderer.clearScreen())
                    continue
                }
                if await handleCommand(input) { break }
                continue
            }

            // Store in history (editor saves on valid input)
            editor.addEntry(input)

            print()

            // Show spinner while thinking (like nanobot's console.status)
            let spinnerTask = Task {
                var frame = 0
                while !Task.isCancelled {
                    print(renderer.renderThinkingLine(frame: frame), terminator: "")
                    fflush(stdout)
                    frame += 1
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                // Clear the spinner line
                print("\r\u{001B}[K", terminator: "")
                fflush(stdout)
            }

            var responseText = ""

            do {
                let stream = client.send(
                    messages: [Message(type: .user, content: [.text(input)])],
                    model: model,
                    maxTokens: 4096
                )

                // Buffer the entire response (Nanobot's write-once approach)
                for try await event in stream {
                    let output = streamRenderer.render(event: event, currentOutput: responseText)
                    let sanitized = output.replacingOccurrences(of: "\r\n", with: "\n")
                    if !sanitized.isEmpty {
                        responseText = sanitized
                    }
                }
            } catch {
                responseText = "Error: \(error.localizedDescription)"
            }

            // Cancel spinner and clear its line
            spinnerTask.cancel()
            // Brief pause so the spinner's cancellation handler can clear the line
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Display response in a panel (Nanobot's _print_agent_response)
            let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print(renderer.renderPanel(title: "swift-agent", content: trimmed))
                print()
            } else {
                print(renderer.renderPanel(title: "swift-agent", content: "(empty response)"))
                print()
            }
        }

        editor.save()
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
        registry.register(TaskCreateTool(taskManager: taskManager))
        registry.register(TaskGetTool(taskManager: taskManager))
        registry.register(TaskListTool(taskManager: taskManager))
        registry.register(TaskOutputTool(taskManager: taskManager))
        registry.register(TaskUpdateTool(taskManager: taskManager))
        registry.register(TaskStopTool(taskManager: taskManager))
        registry.register(AgentTool())
        registry.register(SkillTool())
        registry.register(SendMessageTool())
        registry.register(AskUserQuestionTool())
        registry.register(LSPTool())
        registry.register(EnterPlanModeTool())
        registry.register(ExitPlanModeV2Tool())
        registry.register(CronCreateTool())
        registry.register(CronDeleteTool())
        registry.register(CronListTool())
        registry.register(PowerShellTool())
        registry.register(ToolSearchTool(toolRegistry: registry))
        registry.register(SleepTool())
        registry.register(SyntheticOutputTool())
        registry.register(RemoteTriggerTool())
        registry.register(TeamCreateTool())
        registry.register(TeamDeleteTool())
    }
}
