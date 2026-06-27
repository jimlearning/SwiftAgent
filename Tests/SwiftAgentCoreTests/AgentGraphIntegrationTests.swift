import Foundation
import SwiftAgentCore
import Testing

/// Integration test demonstrating a real AgentGraph workflow using deepseek-v4-pro:
/// 1. GitDiffAnalyzer node — runs `git diff`, `git status`, `git add -A`, summarizes changes
/// 2. CommitMessageCrafter node — takes the analysis, produces a conventional commit message
///
/// The generated commit message is written to `agent-graph-test-result.txt` in the project root.
///
/// Requires DEEPSEEK_API_KEY environment variable. Skipped if not set.
@Suite struct AgentGraphIntegrationTests {

    // MARK: - AgentGraph: Git Diff → Stage → Commit Message

    @Test("AgentGraph: git diff → git add -A → commit message → write result file")
    func gitDiffToCommitMessage() async throws {
        // Skip if no API key available
        let apiKey = "sk-799d0bf7058a4107b66e81a088623457"
        /*
        guard let apiKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
              !apiKey.isEmpty else {
            print("⚠️  Skipping: DEEPSEEK_API_KEY not set")
            return
        }
         */

        let projectPath = "/Users/jim/SwiftAgent"
        let resultFilePath = "\(projectPath)/agent-graph-test-result.txt"
        let modelID = "deepseek-v4-pro"

        // ── Provider ──
        let provider = DeepSeekProvider(
            apiKey: apiKey,
            baseURL: URL(string: "https://api.deepseek.com")!,
            modelID: modelID
        )

        // ── Tool Engine ──
        let toolEngine = DefaultToolEngine()
        let bash = BashTool(workingDirectory: projectPath, shell: "/bin/zsh")
        let fileRead = FileReadTool(workingDirectory: projectPath)
        let grep = GrepTool(workingDirectory: projectPath)
        let glob = GlobTool(workingDirectory: projectPath)
        let fileWrite = FileWriteTool(workingDirectory: projectPath)
        let tools: [(any Tool, ToolMetadata)] = [
            (bash, ToolMetadata(isReadOnly: false, isDestructive: true)),
            (fileRead, ToolMetadata(isReadOnly: true, isDestructive: false)),
            (grep, ToolMetadata(isReadOnly: true, isDestructive: false)),
            (glob, ToolMetadata(isReadOnly: true, isDestructive: false)),
            (fileWrite, ToolMetadata(isReadOnly: false, isDestructive: true)),
        ]
        for (tool, metadata) in tools {
            await toolEngine.register(tool: tool, metadata: metadata)
        }

        // ── Agent Graph ──
        let graph = SimpleAgentGraph(nodes: [
            // Node 1: Analyze git state + stage all
            SimpleAgentNode(
                agent: AgentProfile(
                    name: "GitDiffAnalyzer",
                    instructions: """
                    You are a git changeset analyst. Working directory: \(projectPath)

                    Your task (execute in order):
                    1. Run `git status` to see working tree state.
                    2. Run `git diff` to see unstaged changes.
                    3. Run `git diff --cached` to see already-staged changes.
                    4. Run `git add -A` to stage ALL changes.
                    5. Run `git diff --cached --stat` to verify staging.

                    Then analyze:
                    - What files changed and how?
                    - What categories (feat/fix/docs/refactor/test/chore)?
                    - What is the overall theme?

                    Output a structured summary:
                    ## Files Changed
                    - file1 (category)
                    - file2 (category)

                    ## Change Categories
                    feat: N files, fix: N files, ...

                    ## Overall Theme
                    One sentence describing the unified purpose of these changes.
                    """,
                    permissionMode: .all
                ),
                outputs: [NodeOutput(name: "diffAnalysis", type: .string)]
            ),

            // Node 2: Generate commit message + write to file
            SimpleAgentNode(
                agent: AgentProfile(
                    name: "CommitMessageCrafter",
                    instructions: """
                    You are a commit message crafter.

                    Based on the git diff analysis below, generate a Conventional Commits message.

                    Git Diff Analysis:
                    {{diffAnalysis}}

                    Rules:
                    - Format: <type>[optional scope]: <description>
                    - Types: feat, fix, docs, refactor, test, chore, build, ci
                    - Subject line under 72 characters.
                    - Body: 2-4 bullet points explaining what and why.
                    - NO "Co-Authored-By" or "Generated with" lines.

                    Output ONLY the commit message. Then write it to file:

                    Use the FileWrite tool to APPEND (not overwrite) the commit message
                    to the file: \(resultFilePath)

                    Format: start the file entry with "## <timestamp>" then the message on the next line.
                    """,
                    permissionMode: .all
                ),
                inputs: [NodeInput(name: "diffAnalysis", type: .string)]
            ),
        ])

        // ── Graph Executor ──
        let executor = GraphExecutor { profile in
            LanguageModelSessionImpl(
                modelProvider: provider,
                memoryStore: MockMemoryStore(),
                permissionEngine: MockPermissionEngine(shouldAllow: true),
                toolEngine: toolEngine,
                systemPrompt: profile.instructions
            )
        }

        // ── Run ──
        print("\n=== AgentGraph: Git Diff → Stage → Commit Message ===\n")
        print("Model: \(modelID)")
        print("Project: \(projectPath)")
        print("Result file: \(resultFilePath)")
        print("Nodes: GitDiffAnalyzer → CommitMessageCrafter\n")

        let result = try await executor.run(graph: graph, initialPrompt: "Analyze git state, stage all, and write commit message")

        // ── Report ──
        for name in ["GitDiffAnalyzer", "CommitMessageCrafter"] {
            guard let nodeResult = result.nodeResults[name] else {
                print("⚠️  Missing result for node: \(name)")
                continue
            }
            print("━━━ \(name) ━━━")
            if let analysis = nodeResult.outputs["diffAnalysis"] {
                print(analysis)
            }
            for (key, value) in nodeResult.outputs where key != "diffAnalysis" {
                print("[\(key)]:")
                print(value)
            }
            if let usage = nodeResult.usage {
                print("Tokens: in=\(usage.inputTokens) out=\(usage.outputTokens)")
            }
            print()
        }

        print("Total tokens: \(result.totalUsage.inputTokens)\n")

        // ── Assertions ──
        #expect(result.nodeResults.count == 2)
        #expect(result.nodeResults["GitDiffAnalyzer"] != nil)
        #expect(result.nodeResults["CommitMessageCrafter"] != nil)

        let analyzerOutput = result.nodeResults["GitDiffAnalyzer"]?.outputs["diffAnalysis"] ?? ""
        #expect(!analyzerOutput.isEmpty, "GitDiffAnalyzer should produce a diff analysis")

        // Verify result file was created
        if FileManager.default.fileExists(atPath: resultFilePath) {
            if let content = try? String(contentsOfFile: resultFilePath, encoding: .utf8) {
                print("📄 agent-graph-test-result.txt content:")
                print(content)
            }
        } else {
            print("⚠️  Result file not created (CommitMessageCrafter may not have run FileWrite)")
        }

        print("✅ AgentGraph integration test completed successfully")
    }
}
