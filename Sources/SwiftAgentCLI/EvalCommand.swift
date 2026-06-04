import ArgumentParser
import SwiftAgentCore
import Foundation

// MARK: - Eval Command

struct EvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Run evaluations against the LLM API",
        subcommands: [CacheHitRateCommand.self],
        defaultSubcommand: nil
    )
}

// MARK: - Cache Hit Rate Command

struct CacheHitRateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache-hit-rate",
        abstract: "Measure real prompt cache hit rate against the configured API provider."
    )

    @Option(name: .long, help: "Model to test against")
    var model: String = "deepseek-v4-flash"

    @Option(name: .long, help: "Number of conversation turns to simulate")
    var turns: Int = 5

    @Option(name: .long, help: "API base URL (default: ANTHROPIC_BASE_URL env or https://api.deepseek.com/anthropic)")
    var baseURL: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    func run() async throws {
        let resolver = APIKeyResolver()
        guard let apiKey = resolver.resolve(), !apiKey.isEmpty else {
            throw ValidationError("""
                API key not found. Set ANTHROPIC_API_KEY, run `claude /login`, \
                or add a primaryApiKey to ~/.claude.json.
                """)
        }

        let resolvedBaseURL = baseURL
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
            ?? "https://api.deepseek.com/anthropic"

        let debugLogger = verbose ? DebugLogger() : nil

        let client = LLMClient(
            apiKey: apiKey,
            baseURL: resolvedBaseURL,
            model: model,
            sessionID: "eval-\(ISO8601DateFormatter().string(from: Date()))",
            debugLogger: debugLogger
        )

        let reporter = CacheHitRateReporter(client: client, model: model)
        let report = try await reporter.run(turns: turns)

        // Print report
        let bold = "\u{001B}[1m"
        let dim = "\u{001B}[2m"
        let reset = "\u{001B}[0m"
        let green = "\u{001B}[32m"
        let yellow = "\u{001B}[33m"
        let red = "\u{001B}[31m"

        print()
        print("\(bold)SwiftAgent Cache Hit Rate Report\(reset)")
        print("\(dim)========================")
        print("Model: \(model)")
        print("Turns: \(turns)")
        print("Date: \(ISO8601DateFormatter().string(from: Date()))\(reset)")
        print()
        print("\(bold)Per-Turn Metrics\(reset)".padding(toLength: 80, withPad: " ", startingAt: 0))
        print(String(repeating: "─", count: 72))
        print(String(format: "  %@  %10@  %10@  %10@  %10@  %@", "Turn", "Input", "Cache Read", "Cache Cre.", "Comparable", "Hit Rate"))
        print(String(repeating: "─", count: 72))

        for turn in report.turns {
            let comparable = turn.inputTokens + turn.cacheRead + turn.cacheCreation
            let hitRate = comparable > 0
                ? Double(turn.cacheRead) / Double(comparable) * 100.0
                : 0.0

            let hitColor = hitRate >= 70 ? green : (hitRate >= 30 ? yellow : red)
            print(String(
                format: "  %2d  %10d  %10d  %10d  %10d  %@%5.1f%%%@",
                turn.turn,
                turn.inputTokens,
                turn.cacheRead,
                turn.cacheCreation,
                comparable,
                hitColor, hitRate, reset
            ))
        }

        // Summary
        let totalInput = report.turns.map(\.inputTokens).reduce(0, +)
        let totalRead = report.turns.map(\.cacheRead).reduce(0, +)
        let totalCreation = report.turns.map(\.cacheCreation).reduce(0, +)
        let totalComparable = totalInput + totalRead + totalCreation
        let overallHitRate = totalComparable > 0
            ? Double(totalRead) / Double(totalComparable) * 100.0
            : 0.0

        print(String(repeating: "─", count: 72))
        print(String(
            format: "  %@  %10d  %10d  %10d  %10d  %@%5.1f%%%@",
            "Tot",
            totalInput,
            totalRead,
            totalCreation,
            totalComparable,
            overallHitRate >= 70 ? green : (overallHitRate >= 30 ? yellow : red),
            overallHitRate, reset
        ))
        print()

        // Assessment
        print("\(bold)Assessment:\(reset) ", terminator: "")
        if overallHitRate >= 90 {
            print("\(green)Excellent — cached prefix covers most of the request.\(reset)")
        } else if overallHitRate >= 70 {
            print("\(green)Good — acceptable cache efficiency.\(reset)")
        } else if overallHitRate >= 50 {
            print("\(yellow)Moderate — cache has room for improvement.\(reset)")
        } else if overallHitRate >= 30 {
            print("\(yellow)Low — check system prompt block structure and cache_control placement.\(reset)")
        } else {
            print("\(red)Very low — proxy may not support prompt caching for this model/param combination.\(reset)")
        }
        print()

        // Recommendations
        if overallHitRate < 50 {
            print("\(bold)Troubleshooting:\(reset)")
            if totalCreation == 0 {
                print("  • No cache_creation — the proxy didn't create any cache. Check if the provider supports prompt caching.")
            }
            if totalRead == 0 && totalCreation > 0 {
                print("  • Cache was created but not read on subsequent turns. Verify cache_control markers on system blocks form a contiguous chain.")
            }
            if let first = report.turns.first, first.cacheRead == 0, report.turns.count > 1 {
                let second = report.turns[1]
                if second.cacheRead == 0 {
                    print("  • No cache read even on turn 2. The request shape may not match the cached prefix exactly.")
                }
            }
            print()
        }

        if let path = debugLogger?.logFilePath {
            print("\(dim)Debug log: \(path)\(reset)")
        }
    }
}

// MARK: - Cache Hit Rate Reporter

struct TurnMetrics {
    let turn: Int
    let inputTokens: Int
    let cacheRead: Int
    let cacheCreation: Int
}

struct CacheHitRateReport {
    var turns: [TurnMetrics] = []
}

actor CacheHitRateReporter {
    private let client: LLMClient
    private let model: String

    init(client: LLMClient, model: String) {
        self.client = client
        self.model = model
    }

    nonisolated func run(turns: Int) async throws -> CacheHitRateReport {
        var report = CacheHitRateReport()
        var messages: [Message] = []

        let systemPrompt = buildSystemPrompt()
        let tools = buildTools()

        let prompts = [
            "Hello, respond with just: Ready for cache evaluation.",
            "What programming languages support pattern matching?",
            "Explain what a linked list is in one sentence.",
            "What is the time complexity of binary search?",
            "Describe a stack data structure briefly.",
            "What is a hash table used for?",
            "Explain recursion in one sentence.",
        ]

        let turnCount = min(turns, prompts.count)

        for i in 0..<turnCount {
            messages.append(Message(type: .user, content: [.text(prompts[i])]))

            // Collect usage and response
            var usageInfo: (input: Int, cacheRead: Int, cacheCreation: Int)?
            var assistantBlocks: [ContentBlock] = []
            var currentText = ""
            var currentToolName = ""
            var currentToolID = ""
            var accumulatedInputJSON = ""

            let stream = client.send(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                maxTokens: 1024,
                tools: tools,
                thinking: .disabled,
                betas: nil,
                enablePromptCaching: true
            )

            for try await event in stream {
                switch event {
                case .messageStart(let msg):
                    if let u = msg.usage {
                        usageInfo = (u.inputTokens, u.cacheReadInputTokens, u.cacheCreationInputTokens)
                    }

                case .messageDelta(_, let usage):
                    if let u = usage {
                        usageInfo = (u.inputTokens, u.cacheReadInputTokens, u.cacheCreationInputTokens)
                    }

                case .contentBlockStart(_, let block):
                    if !currentText.isEmpty {
                        assistantBlocks.append(.text(currentText))
                        currentText = ""
                    }
                    if case .toolUse(let name, let id) = block {
                        currentToolName = name
                        currentToolID = id
                        accumulatedInputJSON = ""
                    }

                case .textDelta(let text):
                    currentText += text

                case .inputJSONDelta(let delta):
                    accumulatedInputJSON += delta

                case .contentBlockStop:
                    if !currentText.isEmpty {
                        assistantBlocks.append(.text(currentText))
                        currentText = ""
                    }
                    if !currentToolID.isEmpty {
                        let input = parseJSONToValue(accumulatedInputJSON)
                        assistantBlocks.append(.toolUse(id: currentToolID, name: currentToolName, input: input))
                        currentToolID = ""
                        currentToolName = ""
                        accumulatedInputJSON = ""
                    }

                default:
                    break
                }
            }

            // Record metrics
            let metrics = TurnMetrics(
                turn: i + 1,
                inputTokens: usageInfo?.input ?? 0,
                cacheRead: usageInfo?.cacheRead ?? 0,
                cacheCreation: usageInfo?.cacheCreation ?? 0
            )
            report.turns.append(metrics)

            // Add assistant response
            messages.append(Message(type: .assistant, content: assistantBlocks))

            // If the assistant called tools, synthesize tool results so the
            // conversation remains valid per the API spec (every tool_use
            // must have a corresponding tool_result in the next user message).
            let toolCalls = assistantBlocks.compactMap { block -> (String, String)? in
                if case .toolUse(let id, let name, _) = block {
                    return (id, name)
                }
                return nil
            }
            if !toolCalls.isEmpty {
                let resultBlocks: [ContentBlock] = toolCalls.map { (id, name) in
                    .toolResult(toolUseID: id, content: .string("ok"), isError: false)
                }
                messages.append(Message(type: .user, content: resultBlocks))
            }
        }

        return report
    }

    private nonisolated func buildSystemPrompt() -> String {
        """
        You are SwiftAgent, a Swift-native AI coding agent. You help users with software engineering tasks by responding conversationally. You do NOT use tools during this evaluation.

        RESPONSE RULES:
        - Answer questions directly and concisely
        - Do NOT use any tools — respond with text only
        - Keep responses to one or two sentences
        - If you don't know something, say so

        CAPABILITIES:
        - You can read, write, and edit files
        - You can execute shell commands
        - You can search code with glob and grep
        - You can use LSP for code intelligence
        - You can manage git repositories
        - You can use MCP servers for additional tools
        - You can create and manage tasks
        - You can cache and store information
        - You can use structured thinking for complex problems

        CODING STYLE:
        - Write clean, idiomatic Swift
        - Follow Swift API design guidelines
        - Use explicit types over ambiguity
        - Prefer enums and structs over strings and booleans
        - Use proper error handling
        - Write tests for your code

        EVALUATION CONTEXT:
        This is a prompt cache evaluation session. The purpose is to measure how effectively the Anthropic Messages API caches repeated content across conversation turns. The system prompt contains both static content (always the same) and dynamic content (may change per session). The boundary between them is marked below.

        \(SYSTEM_PROMPT_DYNAMIC_BOUNDARY)

        Working directory: /Users/jim/SwiftAgent
        Platform: darwin
        Shell: zsh
        Evaluation session: cache-hit-rate
        Do NOT use any tools — respond with text only.
        """
    }

    private nonisolated func buildTools() -> [ToolDefinition] {
        [
            ToolDefinition(name: "Read", description: "Read files from the filesystem", inputSchema: JSONSchema(type: "object")),
            ToolDefinition(name: "Edit", description: "Edit files via string replacement", inputSchema: JSONSchema(type: "object")),
            ToolDefinition(name: "Bash", description: "Execute shell commands", inputSchema: JSONSchema(type: "object")),
            ToolDefinition(name: "Glob", description: "Find files matching a pattern", inputSchema: JSONSchema(type: "object")),
            ToolDefinition(name: "Grep", description: "Search file contents", inputSchema: JSONSchema(type: "object")),
        ]
    }

    private nonisolated func parseJSONToValue(_ json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let value = JSONValue.fromAny(obj) else {
            return .object([:])
        }
        return value
    }
}
